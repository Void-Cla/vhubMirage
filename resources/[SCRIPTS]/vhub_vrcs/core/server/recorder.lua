---@diagnostic disable: undefined-global, lowercase-global

-- core/server/recorder.lua — gravador de replay: escritor UNICO do .vhr e da
--                            tabela vh_race_replays. Buffer em RAM por corrida;
--                            1 flush atomico no fechamento (nunca I/O por frame).
--
-- Ciclo: open → append (N frames) → close (serializa + salva + enfileira).
-- NUNCA grava nick/PII no .vhr — so charId (vrcs.md secao 9).

VRCS = VRCS or {}

local Cfg    = VRCS.Cfg
local Schema = VRCS.Schema
local Codec  = VRCS.Codec
local Log    = VRCS.Log

local R = { active = {} }; VRCS.Recorder = R


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- abre um replay em buffer (RAM). meta = { raceId, track, kind, category, players[] }
function R.open(race_id, meta)
    if R.active[race_id] then return end

    local replay  = Schema.new_replay(meta)
    local by_char = {}
    for _, p in ipairs(replay.players) do by_char[p.charId] = p end

    R.active[race_id] = {
        replay     = replay,
        by_char    = by_char,
        count      = {},                  -- frames por charId (para o cap)
        started_ms = GetGameTimer(),
        truncated  = false,
    }
end


-- mescla a aparencia (look) do piloto recebida do client ao replay (cosmetico)
function R.set_look(race_id, char_id, look)
    local rec = R.active[race_id]
    if not rec then return end
    local p = rec.by_char[char_id]
    if not p or type(look) ~= 'table' then return end
    p.ped = look
end


-- acrescenta um CHUNK de frames (enviado pelo client) ao jogador. Teto total
-- (MAX_FRAMES) + cap por chunk (anti payload hostil). Frames vem ja arredondados
-- do client; o cap de tamanho protege o .vhr.
function R.append_chunk(race_id, char_id, frames)
    local rec = R.active[race_id]
    if not rec then return end
    local p = rec.by_char[char_id]
    if not p then return end
    if type(frames) ~= 'table' then return end

    local cap       = Cfg.MAX_FRAMES or 9000
    local chunk_cap = Cfg.MAX_CHUNK_FRAMES or 600
    local n = 0
    for _, f in ipairs(frames) do
        if n >= chunk_cap then break end
        if (rec.count[char_id] or 0) >= cap then rec.truncated = true; break end
        if type(f) == 'table' then
            p.frames[#p.frames + 1] = f
            rec.count[char_id] = (rec.count[char_id] or 0) + 1
            n = n + 1
        end
    end
end


-- ============================================================
-- CLOSE — serializa + persiste + enfileira (em thread propria, nao bloqueia o racha)
-- ============================================================

-- aplica os campos do .vhr a partir do desfecho da corrida (sem nick no arquivo)
local function apply_final(replay, finalMeta, duration_s)
    replay.duration     = duration_s
    replay.winnerCharId = tonumber(finalMeta.winner_char) or 0

    -- indexa as entradas por charId para casar com o desfecho
    local by_char = {}
    for _, e in ipairs(replay.players) do by_char[e.charId] = e end

    for _, pl in ipairs(finalMeta.players or {}) do
        local entry = by_char[tonumber(pl.char_id) or 0]
        if entry then
            entry.placement = tonumber(pl.placement) or 0
            entry.timeMs    = tonumber(pl.time_ms) or 0
            entry.finished  = pl.finished == true
            if entry.finished and entry.placement == 1 then
                entry.events[#entry.events + 1] = { time = duration_s, type = 'WINNER' }
            end
        end
    end
end


-- persiste o meta do replay (escritor unico de vh_race_replays)
local function persist_meta(replay, path, size)
    VRCS.Db.execute([[
        INSERT INTO vh_race_replays
            (race_id, track_id, kind, category, winner_char, duration_s,
             players_n, size_bytes, vhr_path, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            vhr_path = VALUES(vhr_path), size_bytes = VALUES(size_bytes),
            created_at = VALUES(created_at)
    ]], {
        replay.raceId, replay.track or '', replay.kind or 'sprint',
        replay.category or 'normal', replay.winnerCharId or 0, replay.duration or 0,
        #(replay.players or {}), size, path, os.time(),
    })
end


-- fecha o replay: pop do buffer + serializa + valida + salva .vhr + enfileira.
-- on_saved(replay, data) (opcional) e chamado no fim — o binding usa p/ entregar
-- o replay aos clientes participantes (cache in-game). Mantem o core agnostico.
function R.close(race_id, finalMeta, on_saved)
    local rec = R.active[race_id]
    R.active[race_id] = nil
    if not rec then return end

    finalMeta = finalMeta or {}

    Citizen.CreateThread(function()
        local replay = rec.replay

        -- duracao = maior t entre todos os frames recebidos dos clients
        local duration = 0
        for _, pl in ipairs(replay.players) do
            local f = pl.frames
            if f and #f > 0 then
                local lt = f[#f].t or 0
                if lt > duration then duration = lt end
            end
        end
        duration = math.floor(duration + 0.5)
        if duration <= 0 then
            Log.warn(('replay %s sem frames (clients nao enviaram) — descartado'):format(tostring(race_id)))
            return
        end
        apply_final(replay, finalMeta, duration)
        if rec.truncated then replay.truncated = true end

        -- valida o contrato antes de tocar em disco
        local ok, err = Schema.validate(replay)
        if not ok then
            Log.error(('replay %s invalido (%s) — descartado'):format(tostring(race_id), tostring(err)))
            return
        end

        -- serializa + teto de tamanho
        local data = Codec.encode(replay)
        if #data > (Cfg.MAX_REPLAY_BYTES or (12 * 1024 * 1024)) then
            Log.warn(('replay %s excede o teto (%d bytes) — descartado'):format(race_id, #data))
            return
        end

        -- path seguro: raceId e UUID validado; nome fixo BASE/<uuid>.vhr (sem traversal)
        if not Schema.is_uuid(race_id) then
            Log.error('race_id nao-UUID no close — abortado')
            return
        end
        local path  = ('%s/%s.vhr'):format(Cfg.REPLAY_DIR or 'replays', race_id)
        local saved = SaveResourceFile(GetCurrentResourceName(), path, data, #data)
        if not saved then
            Log.error(('falha ao salvar %s'):format(path))
            return
        end

        -- persiste meta + enfileira render (atomico no SQL)
        persist_meta(replay, path, #data)
        VRCS.Queue.enqueue(race_id, path)
        Log.info(('replay salvo: %s (%d bytes, %ds, %d pilotos) -> fila'):format(
            path, #data, duration, #(replay.players or {})))

        -- publisher de TESTE (Discord) — concessao Fase 1 (ver config). Recebe o
        -- .vhr serializado p/ anexar ao post (raceId + char_ids dos participantes).
        if VRCS.Publisher and VRCS.Publisher.publish_result then
            VRCS.Publisher.publish_result(replay, finalMeta, data)
        end

        -- entrega aos clientes participantes (cache in-game) — callback do binding
        if type(on_saved) == 'function' then pcall(on_saved, replay, data) end
    end)
end
