---@diagnostic disable: undefined-global, lowercase-global

-- server/runtime.lua — corrida ativa (warmup → racing → finished).
--
-- Recebe a instancia em warmup (do Lobby) e gerencia o ciclo de corrida:
--   • begin_racing      → transiciona warmup → racing, dispara RACE_START
--   • on_checkpoint     → valida CP via anti_cheat, atualiza progresso
--   • on_tick           → atualiza drift_score / top_speed com smoothing
--   • _player_finish    → marca chegada, inicia grace para os outros
--   • on_abort          → marca DNF
--   • finish            → encerra a instancia, persiste history, paga premios
--
-- Premio so existe se inst.mode == 'rankeada'. Treino, freerun e
-- timeattack-treino terminam sem payout (timeattack ranqueada tem bonus_pct).
-- Premios distribuidos via Rewards.pay (interface unica com vhub_money).


VHubRachaRuntime = {}
local RT  = VHubRachaRuntime
local Cfg = VHubRachaCfg
local AC  = VHubRachaAC
local ST  = VHubRachaState
local HIS = VHubRachaHistory
local RW  = VHubRachaRewards
local E   = VHubRachaE


-- ============================================================
-- HELPERS
-- ============================================================

local function ms() return GetGameTimer() end


local function notify(src, msg, kind)
    if src and src > 0 then
        TriggerClientEvent(E.NOTIFY, src, msg, kind or 'info')
    end
end


-- Payload CANONICO do state bag da corrida — FONTE UNICA (usado em begin/checkpoint/tick).
-- Superset coerente: todo set carrega os MESMOS campos, entao o HUD nunca perde
-- placement/starts_at entre um tick e outro (o :set substitui o valor inteiro).
local function race_bag(inst, p)
    return {
        inst_id       = inst.id,
        track_id      = inst.track_id,
        kind          = inst.kind,
        mode          = inst.mode,
        state         = inst.state,
        cp_done       = p.cp_done or 0,
        cp_total      = inst.cp_total or 0,
        lap           = p.lap or 0,
        laps          = inst.laps or 1,
        placement     = p.placement or 0,
        players_total = ST.count_players(inst),
        drift_score   = p.drift_score or 0,
        starts_at     = inst.starts_at or 0,
        started_ms    = p.started_ms or 0,
    }
end


-- Aplica telemetria (top_speed/drift) ao player com cap anti-spike e monotonia.
-- Chamado pelo on_tick (1Hz) E pelo on_checkpoint — garante que o CP que ENCERRA
-- a corrida ja carregue o pico de velocidade e o drift bancado, antes do finalize
-- rodar e descartar a instancia (causa-raiz do top_speed/drift = 0 no catalogo).
local function apply_telemetry(player, payload)
    if type(payload) ~= 'table' then return end

    if payload.top_speed then
        local s = math.max(0, math.floor(tonumber(payload.top_speed) or 0))
        if s > (player.top_speed or 0) then
            player.top_speed = math.min(s, (Cfg.MAX_SPEED_KMH or 400))
        end
    end

    if payload.drift_score then
        local now_ms      = ms()
        local last_ms     = player.last_tick_ms or now_ms
        local dt_sec      = math.max(0.001, (now_ms - last_ms) / 1000.0)
        local cap_per_sec = (Cfg.DRIFT and Cfg.DRIFT.CAP_PER_SEC) or 150
        local max_gain    = math.floor(cap_per_sec * dt_sec + 0.5)
        local reported    = math.max(0, math.floor(tonumber(payload.drift_score) or 0))
        if reported > (player.drift_score or 0) then
            local gain = math.min(reported - (player.drift_score or 0), max_gain)
            player.drift_score = (player.drift_score or 0) + gain
        end
        player.last_tick_ms = now_ms
    end
end


-- Snapshot do estado da instancia para os state bags dos players
-- (HUD/NUI le e renderiza tempo, posicao, lap, drift em tempo real)
local function sync_state_bag(inst)
    for src, p in pairs(inst.players or {}) do
        Player(src).state:set('vhub_racha', race_bag(inst, p), true)
    end
end


-- ============================================================
-- BEGIN RACING — transicao warmup → racing
-- ============================================================

-- Chamado pelo Lobby apos o countdown. Marca inicio da corrida, sincroniza
-- estado para todos, e agenda timeout duro (track.limit_seconds).
function RT.begin_racing(inst)
    inst.state = 'racing'

    local now_ms = ms()
    for src, p in pairs(inst.players) do
        p.state      = 'racing'
        p.started_ms = now_ms
        p.last_cp_ms = now_ms
        TriggerClientEvent(E.RACE_START, src, { inst_id = inst.id, started_ms = now_ms })
    end

    sync_state_bag(inst)

    -- Rede de seguranca (NAO guilhotina): so encerra instancia abandonada/travada.
    -- Piso generoso — o `limit_seconds` curto da pista NUNCA reduz isto, entao a
    -- corrida normal acaba por chegada / DNF / grace, nunca por timeout no meio.
    local safety = (Cfg.RACE_SAFETY_TIMEOUT_S or 1800) * 1000
    SetTimeout(safety, function()
        local i = ST.instance(inst.id)
        if not i or i.state ~= 'racing' then return end
        RT.finish(inst.id, 'timeout')
    end)

    -- ============================================================
    -- VRCS (soft-dep): abre o replay cinematografico se vhub_vrcs existir.
    -- Empurra so estado JA validado (sem 2a fonte). pcall = o inicio da corrida
    -- NUNCA quebra se o resource de replay estiver off/ausente.
    -- ============================================================
    pcall(function()
        local players = {}
        for psrc, pp in pairs(inst.players) do
            players[#players + 1] = { src = psrc, char_id = pp.char_id }
        end
        exports['vhub_vrcs']:onRaceStart({
            inst_id  = inst.id,
            track_id = inst.track_id,
            kind     = inst.kind,
            mode     = inst.mode,
            category = inst.category,
            players  = players,
        })
    end)
end


-- ============================================================
-- ON CHECKPOINT — cliente reportou que cruzou um CP
-- ============================================================

-- Valida via anti_cheat (distancia, tempo minimo entre CPs).
-- Atualiza cp_done, lap, e dispara _player_finish se foi o ultimo CP.
function RT.on_checkpoint(src, payload)
    local inst = ST.instance_by_src(src)
    if not inst then return end
    if inst.state ~= 'racing' then return end

    local ok, err = AC.validate_checkpoint(inst, src, payload)
    if not ok then
        notify(src, ('CP invalidado: %s'):format(tostring(err)), 'error')
        return
    end

    local player = inst.players[src]
    player.cp_done    = (player.cp_done or 0) + 1
    player.last_cp_ms = ms()

    local cp_total    = inst.cp_total or 0
    local cps_per_lap = math.max(1, math.floor(cp_total / math.max(1, inst.laps)))
    player.lap        = math.floor((player.cp_done - 1) / cps_per_lap) + 1

    -- Telemetria carregada no proprio CP: o ultimo CP (que dispara o finish)
    -- ja deixa top_speed/drift persistidos antes do finalize.
    apply_telemetry(player, payload)

    -- Sincroniza state bag (HUD reflete imediato) — fonte unica race_bag
    Player(src).state:set('vhub_racha', race_bag(inst, player), true)

    if cp_total > 0 and player.cp_done >= cp_total then
        RT._player_finish(inst, src)
    end
end


-- ============================================================
-- ON TICK — telemetria do cliente (drift_score / top_speed / best_lap)
-- ============================================================

-- Smoothing: limita ganho de drift_score por segundo (anti-cheat).
-- top_speed e best_lap aceitos com clamp em MAX_SPEED_KMH.
function RT.on_tick(src, payload)
    local inst = ST.instance_by_src(src)
    if not inst then return end
    if inst.state ~= 'racing' then return end

    local player = inst.players[src]
    if not player then return end
    if type(payload) ~= 'table' then return end

    -- top_speed / drift com cap anti-spike (fonte unica: apply_telemetry)
    apply_telemetry(player, payload)

    if payload.best_lap_ms and payload.best_lap_ms > 0 then
        if not player.best_lap_ms or payload.best_lap_ms < player.best_lap_ms then
            player.best_lap_ms = tonumber(payload.best_lap_ms)
        end
    end

    Player(src).state:set('vhub_racha', race_bag(inst, player), true)
end


-- ============================================================
-- PLAYER FINISH — jogador cruzou a chegada
-- ============================================================

-- Marca o player como finished. Se foi o primeiro, inicia grace timer para
-- os demais. Se todos terminaram, finaliza a instancia inteira.
function RT._player_finish(inst, src)
    local player = inst.players[src]
    if not player or player.finished then return end

    player.finished    = true
    player.finished_ms = ms()
    player.state      = 'finished'

    notify(src, 'Voce cruzou a linha de chegada!', 'success')

    -- Primeiro a terminar → inicia grace para os outros
    if inst.finish_grace_started_at == 0 then
        inst.finish_grace_started_at = ms()
        SetTimeout(Cfg.FINISH_GRACE_MS or 60000, function()
            local i = ST.instance(inst.id)
            if not i or i.state ~= 'racing' then return end
            RT.finish(inst.id, 'grace_expirou')
        end)
    end

    -- Todos terminaram?
    local pending = 0
    for _, p in pairs(inst.players) do
        if not p.finished then pending = pending + 1 end
    end
    if pending == 0 then RT.finish(inst.id, 'todos_terminaram') end
end


-- ============================================================
-- ON ABORT — DNF (desistencia ou morte)
-- ============================================================

function RT.on_abort(src, reason)
    local inst = ST.instance_by_src(src)
    if not inst then return end
    if inst.state ~= 'racing' then return end

    local player = inst.players[src]
    if not player then return end

    -- Quem JA cruzou a chegada nao pode virar DNF (morte/saida do carro na janela
    -- de graca eram comemoracao, nao desistencia). Antes isso gravava o vencedor
    -- como derrota — causa do "vitoria e derrota ao mesmo tempo".
    if player.finished then return end

    player.state       = 'dnf'
    player.finished    = false
    player.finished_ms = ms()
    notify(src, ('Voce desistiu (%s).'):format(reason or 'dnf'), 'error')

    -- Se todos DNF/finished, encerra
    local pending = 0
    for _, p in pairs(inst.players) do
        if not p.finished and p.state ~= 'dnf' then pending = pending + 1 end
    end
    if pending == 0 then RT.finish(inst.id, 'todos_dnf') end
end


-- ============================================================
-- FINISH — finaliza instancia (persiste + paga + libera)
-- ============================================================

-- Encerra a corrida: chama History.finalize, paga premios via Rewards.pay,
-- e remove a instancia. Em caso de falha do history, faz refund da fee.
function RT.finish(inst_id, reason)
    local inst = ST.instance(inst_id)
    if not inst then return false end
    if inst.state == 'finished' or inst.state == 'closed' then return false end

    inst.state = 'finished'
    ST.metrics.instances_finished = ST.metrics.instances_finished + 1

    local result = HIS.finalize(inst)

    -- Falha grave no history → refund todos
    if not result then
        for src, _ in pairs(inst.players) do
            RW.refund(src, inst.entry_fee or 0, 'race_failed')
            Player(src).state:set('vhub_racha', nil, true)
            ST.unbind_src(src)
        end
        ST.remove_instance(inst.id)
        return false, 'finalize_failed'
    end

    -- Distribui premios + emite RACE_FINISH
    for _, p in ipairs(result.players) do
        if (p.payout or 0) > 0 and p.src then
            RW.pay(p.src, p.payout, 'race_payout')
        end

        if p.src then
            TriggerClientEvent(E.RACE_FINISH, p.src, {
                inst_id     = inst.id,
                placement   = p.placement,
                time_ms     = p.total_time_ms,
                drift       = p.drift_score,
                payout      = p.payout,
                history_id  = result.history_id,
                winner_char = result.winner_char,
                reason      = reason or 'finished',
                mode        = inst.mode,
                -- Ranqueado (nil em treino/privada ou corrida < 2 pilotos)
                pdl_delta   = p.pdl_delta,
                pdl_new     = p.pdl_new,
                division    = p.division,
            })
            Player(p.src).state:set('vhub_racha', nil, true)
            ST.unbind_src(p.src)
        end
    end

    -- ============================================================
    -- VRCS (soft-dep): fecha o replay com o desfecho final. O nick viaja SO p/ o
    -- embed de resultado — o recorder NUNCA grava nick/PII no .vhr (so char_id).
    -- ============================================================
    pcall(function()
        local players = {}
        for _, p in ipairs(result.players) do
            players[#players + 1] = {
                char_id   = p.char_id,
                nick      = p.nick,
                placement = p.placement,
                time_ms   = p.total_time_ms,
                drift     = p.drift_score,
                top_speed = p.top_speed,
                finished  = p.finished,
            }
        end
        exports['vhub_vrcs']:onRaceClose(inst.id, {
            winner_char = result.winner_char,
            players     = players,
        })
    end)

    inst.state = 'closed'
    ST.remove_instance(inst.id)
    return true, result
end


-- ============================================================
-- LIFECYCLE — player dropped durante corrida
-- ============================================================

-- Player dropou durante racing → marca DNF
function RT.on_player_dropped(src)
    local inst = ST.instance_by_src(src)
    if not inst then return end
    if inst.state == 'racing' then RT.on_abort(src, 'dropped') end
end
