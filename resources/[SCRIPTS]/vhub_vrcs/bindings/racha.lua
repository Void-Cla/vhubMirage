---@diagnostic disable: undefined-global, lowercase-global

-- bindings/racha.lua — REGRA DE NEGOCIO: liga o vhub_racha ao core do VRCS.
--
-- ARQUITETURA (client-driven, upload POS-corrida): o SERVIDOR nao amostra. Cada
-- CLIENT grava o proprio carro 100% em RAM durante a corrida (zero rede nesse
-- periodo) e so envia, fatiado e com ACK, depois do recStop. O servidor recebe
-- os blocos, confirma cada um (recAck) e monta UM .vhr quando todos os
-- participantes confirmarem final=true OU o teto SEND_TIMEOUT_TOTAL_MS vencer
-- (replay sai com quem respondeu — nao trava a fila pelos demais). Este arquivo
-- CONSOME o core (recorder); o core nao conhece o racha.

VRCS = VRCS or {}

local Cfg      = VRCS.Cfg
local Recorder = VRCS.Recorder
local Log      = VRCS.Log

local B = {}
VRCS.Bindings = VRCS.Bindings or {}
VRCS.Bindings.Racha = B

-- inst_id (racha) -> { race_id (uuid), srcs = { [src]=char_id }, closing = bool,
--                       done = { [src]=bool } (confirmou final=true) }
B.tracking = {}

math.randomseed(GetGameTimer() + os.time())


-- ============================================================
-- HELPERS
-- ============================================================

-- gera um UUID v4 textual (casa com Schema.is_uuid)
local function uuid()
    return (('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'):gsub('[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(v)
    end))
end


-- a corrida deve ser gravada? (TESTE: so ranqueada por padrao)
local function should_record(meta)
    if not Cfg.RECORD.ranked_only then return true end
    return meta.mode == Cfg.RECORD.require_mode
       and meta.category == Cfg.RECORD.require_category
end


-- captura a identidade VISUAL do carro do jogador (server-side, autoritativo).
-- Modelo + placa + customizacao persistida da placa (Doutrina da Placa, via conce).
local function capture_vehicle(src)
    local out = { vehicle = '', plate = '', customization = nil, pedModel = '' }
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return out end
    out.pedModel = tostring(GetEntityModel(ped))   -- fallback do motorista (look vem do client)
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return out end

    out.vehicle = tostring(GetEntityModel(veh))
    local plate = GetVehicleNumberPlateText(veh)
    out.plate = plate and (plate:gsub('^%s+', ''):gsub('%s+$', '')) or ''

    pcall(function()
        if out.plate ~= '' then
            local st = exports['vhub_conce']:getVehicleState(out.plate)
            if type(st) == 'table' and type(st.customization) == 'table' then
                out.customization = st.customization
            end
        end
    end)

    return out
end


-- localiza a corrida ativa pelo race_id (validacao dos chunks do client)
local function find_by_rid(rid)
    for _, tr in pairs(B.tracking) do
        if tr.race_id == rid then return tr end
    end
    return nil
end


-- reconstroi um look LIMPO e LIMITADO (anti-bloat/anti-payload hostil)
local function sanitize_look(look)
    if type(look) ~= 'table' then return nil end
    local out = { model = tonumber(look.model) or 0, components = {}, props = {} }
    local comps = look.components or {}
    for i = 0, 11 do
        local c = comps[i] or comps[tostring(i)]
        if type(c) == 'table' then
            out.components[i] = { tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0 }
        end
    end
    local props = look.props or {}
    for i = 0, 7 do
        local p = props[i] or props[tostring(i)]
        if type(p) == 'table' then
            out.props[i] = { tonumber(p[1]) or -1, tonumber(p[2]) or 0 }
        end
    end
    return out
end


-- ============================================================
-- HOOKS — chamados pelo vhub_racha (push, sob pcall do lado de la)
-- ============================================================

-- inicio da corrida: abre o replay e MANDA cada client comecar a gravar
function B.on_race_start(meta)
    if type(meta) ~= 'table' or meta.inst_id == nil then return end
    if not should_record(meta) then return end

    local rid     = uuid()
    local srcs    = {}
    local players = {}
    for _, pl in ipairs(meta.players or {}) do
        local src = tonumber(pl.src)
        local cid = tonumber(pl.char_id) or 0
        if src and cid > 0 then
            srcs[src] = cid
            local cap = capture_vehicle(src)
            players[#players + 1] = {
                char_id       = cid,
                vehicle       = cap.vehicle,
                plate         = cap.plate,
                customization = cap.customization,
                pedModel      = cap.pedModel,
            }
        end
    end
    if next(srcs) == nil then return end

    Recorder.open(rid, {
        raceId    = rid,
        track     = meta.track_id,
        kind      = meta.kind,
        category  = meta.category,
        startTime = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        players   = players,
    })

    B.tracking[meta.inst_id] = { race_id = rid, srcs = srcs, closing = false, done = {} }

    -- manda cada participante GRAVAR o proprio carro (client-driven)
    for src in pairs(srcs) do
        TriggerClientEvent('vhub_vrcs:recStart', src, rid)
    end

    Log.info(('replay iniciado: %s (inst %s, %d pilotos)'):format(
        rid, tostring(meta.inst_id), #players))
end


-- todos os participantes rastreados ja confirmaram o upload (final=true)?
local function all_done(tr)
    for src in pairs(tr.srcs) do
        if not tr.done[src] then return false end
    end
    return true
end


-- fim da corrida: manda os clients enviarem o replay, espera ATIVAMENTE ate
-- todos confirmarem (ou o teto SEND_TIMEOUT_TOTAL_MS vencer) e ENTAO monta o
-- .vhr unico (sem push aos clients — disponivel via /replays).
function B.on_race_close(inst_id, finalMeta)
    local tr = B.tracking[inst_id]
    if not tr then return end
    if tr.closing then return end
    tr.closing = true

    -- pede o upload (sequencial, fatiado) a cada participante
    for src in pairs(tr.srcs) do
        TriggerClientEvent('vhub_vrcs:recStop', src, tr.race_id)
    end

    local rid  = tr.race_id
    local meta = finalMeta or {}

    Citizen.CreateThread(function()
        local waited = 0
        local step   = 500
        local total  = Cfg.SEND_TIMEOUT_TOTAL_MS or 60000
        while waited < total do
            if all_done(tr) then break end
            Citizen.Wait(step)
            waited = waited + step
        end
        B.tracking[inst_id] = nil
        Recorder.close(rid, meta)   -- assembla + salva + Discord + enfileira
    end)
end


-- ============================================================
-- INGEST — blocos pos-corrida do client (frames + look). Cosmetico, validado.
-- Cada bloco recebe ACK (vhub_vrcs:recAck) para o client liberar o proximo.
-- ============================================================

RegisterNetEvent('vhub_vrcs:recData')
AddEventHandler('vhub_vrcs:recData', function(rid, payload)
    local src = source
    if type(rid) ~= 'string' or type(payload) ~= 'table' then return end
    local seq = tonumber(payload.seq)
    if not seq then return end

    local tr = find_by_rid(rid)
    if not tr then return end                 -- corrida inexistente/encerrada
    local cid = tr.srcs[src]
    if not cid then return end                -- remetente nao e participante

    if type(payload.frames) == 'table' then
        Recorder.append_chunk(rid, cid, payload.frames)
    end
    if type(payload.look) == 'table' then
        Recorder.set_look(rid, cid, sanitize_look(payload.look))
    end

    if payload.final == true then
        tr.done[src] = true
    end

    -- ACK confirma que o bloco foi processado (payload bem-formado e participante
    -- valido) — Recorder.append_chunk e fire-and-forget, sem retorno de falha.
    TriggerClientEvent('vhub_vrcs:recAck', src, rid, seq, true)
end)


-- shutdown: descarta o que estiver em buffer (replay parcial perdido — residual aceito)
function B.flush_all()
    local n = 0
    for inst_id in pairs(B.tracking) do
        B.tracking[inst_id] = nil
        n = n + 1
    end
    if n > 0 then Log.warn(('%d replay(s) em andamento descartado(s) no stop'):format(n)) end
end
