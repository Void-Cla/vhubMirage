---@diagnostic disable: undefined-global, lowercase-global

-- client/recorder.lua — gravacao CLIENT-DRIVEN do proprio carro durante a corrida.
--
-- Buffer 100% em RAM durante toda a corrida (zero rede, zero risco de lag na
-- prova). So ao receber recStop o buffer e enviado, fatiado e com ACK (ver
-- bloco UPLOAD). Campos estendidos (v2) sao best-effort/cosmeticos — ver
-- Schema.TRUST; aceitavel pois a colocacao/tempo ja foram decididos pelo
-- vhub_racha antes deste artefato existir.

VRCS = VRCS or {}

local Cfg = VRCS.Cfg

local R = {
    active     = false,
    rid        = nil,
    buf        = {},
    start_ms   = 0,
    look       = nil,
    look_sent  = false,
    sampling   = false,
    sending    = false,
}


-- ============================================================
-- HELPERS
-- ============================================================

local function r2(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end
local function r1(n) return math.floor((tonumber(n) or 0) * 10 + 0.5) / 10 end
-- t precisa de precisao de MILISSEGUNDO: a 20Hz (SAMPLE_MS=50), arredondar p/
-- 0.1s jogaria 2 frames no mesmo timestamp (span=0 => snap = "frame a frame").
local function r3(n) return math.floor((tonumber(n) or 0) * 1000 + 0.5) / 1000 end

-- le uma native indexada por roda (0..3) e retorna array de 4 valores arredondados
local function wheel4(veh, fn, round)
    local out = {}
    for i = 0, 3 do out[i + 1] = round(fn(veh, i)) end
    return out
end

-- bit de inputs do jogador: throttle/brake/handbrake/horn (packed, 1 inteiro)
local function input_bits(veh)
    local bits = 0
    if GetDisabledControlNormal(2, 71) > 0.1  then bits = bits | 1 end  -- throttle (INPUT_VEH_ACCELERATE)
    if GetDisabledControlNormal(2, 72) > 0.1  then bits = bits | 2 end  -- brake (INPUT_VEH_BRAKE)
    if GetVehicleHandbrake(veh)               then bits = bits | 4 end
    if GetDisabledControlNormal(2, 86) > 0.5  then bits = bits | 8 end  -- horn (INPUT_VEH_HORN)
    return bits
end

-- bit de luzes: low/high/indicator-left/indicator-right (packed, 1 inteiro)
local function light_bits(veh)
    local bits = 0
    local lightsOn, highbeamsOn = GetVehicleLightsState(veh)
    local indicatorLeft, indicatorRight = GetVehicleIndicatorLights(veh)
    if lightsOn      then bits = bits | 1 end
    if highbeamsOn    then bits = bits | 2 end
    if indicatorLeft  then bits = bits | 4 end
    if indicatorRight then bits = bits | 8 end
    return bits
end


-- look completo do ped local: 12 componentes (roupa) + 8 props + modelo
local function capture_look()
    local ped = PlayerPedId()
    local look = { model = GetEntityModel(ped), components = {}, props = {} }
    for i = 0, 11 do
        look.components[i] = {
            GetPedDrawableVariation(ped, i),
            GetPedTextureVariation(ped, i),
            GetPedPaletteVariation(ped, i),
        }
    end
    for i = 0, 7 do
        local d = GetPedPropIndex(ped, i)
        look.props[i] = { d, (d ~= -1) and GetPedPropTextureIndex(ped, i) or -1 }
    end
    return look
end


-- 1 frame do carro local (nil se nao estiver dirigindo neste instante)
local function sample()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return nil end

    local c   = GetEntityCoords(veh)
    local rot = GetEntityRotation(veh, 2)        -- (pitch, roll, yaw)
    local vv  = GetEntitySpeedVector(veh, true)  -- vetor relativo ao chassi (LOCAL — flat abaixo, L-19)

    return {
        t   = r3((GetGameTimer() - R.start_ms) / 1000.0),   -- segundos (precisao ms)
        x   = r2(c.x), y = r2(c.y), z = r2(c.z),
        rx  = r1(rot.x), ry = r1(rot.y), rz = r1(rot.z),
        s   = math.floor(GetEntitySpeed(veh) * 3.6 + 0.5),  -- km/h
        rpm = r2(GetVehicleCurrentRpm(veh)),                -- 0..1 (audio)
        g   = GetVehicleCurrentGear(veh),                   -- marcha
        st  = r1(GetVehicleSteeringAngle(veh)),             -- volante REAL (rodas viram)
        hb  = GetVehicleHandbrake(veh) and 1 or 0,

        -- ── v2 — cosmetico/best-effort (Schema.TRUST.cosmetic) ──────────────
        vv  = { x = r2(vv.x), y = r2(vv.y), z = r2(vv.z) },
        cl  = r2(GetVehicleClutch(veh)),
        th  = r2(GetVehicleThrottleOffset(veh)),
        eh  = math.floor(GetVehicleEngineHealth(veh) + 0.5),
        tp  = wheel4(veh, GetVehicleWheelTractionVectorLength, r2),
        bp  = wheel4(veh, GetVehicleWheelBrakePressure, r2),
        ws  = wheel4(veh, GetVehicleWheelSpeed, r1),
        wc  = wheel4(veh, GetVehicleWheelSuspensionCompression, r2),
        bf  = input_bits(veh),
        lf  = light_bits(veh),
    }
end


-- ============================================================
-- UPLOAD POS-CORRIDA — sequencial, fatiado, com ACK (so apos recStop)
-- ============================================================

local _pending_ack = nil  -- {rid=, seq=} do bloco aguardando confirmacao

-- envia 1 bloco e aguarda ACK do servidor; retorna true/false (sucesso)
local function send_block_awaiting_ack(rid, seq, frames, final, look)
    local payload = { seq = seq, frames = frames, final = final == true }
    if look then payload.look = look end

    for attempt = 1, (Cfg.SEND_MAX_RETRY or 5) do
        _pending_ack = { rid = rid, seq = seq, ok = false, done = false }
        TriggerServerEvent('vhub_vrcs:recData', rid, payload)

        local waited = 0
        local step   = 100
        while waited < (Cfg.SEND_TIMEOUT_MS or 5000) do
            if _pending_ack and _pending_ack.done and _pending_ack.seq == seq then
                local ok = _pending_ack.ok
                _pending_ack = nil
                if ok then return true end
                break
            end
            Citizen.Wait(step)
            waited = waited + step
        end
        -- timeout ou nack deste attempt → tenta de novo (ou desiste no ultimo)
    end

    _pending_ack = nil
    return false
end

-- envia todo R.buf em blocos sequenciais; chamado 1x, apos recStop
local function upload_all(rid)
    local frames   = R.buf
    R.buf          = {}
    local chunk    = Cfg.SEND_CHUNK_FRAMES or 400
    local total    = #frames
    local seq      = 0

    local i = 1
    while i <= total do
        seq = seq + 1
        local slice = {}
        for k = i, math.min(i + chunk - 1, total) do slice[#slice + 1] = frames[k] end

        local is_last = (i + chunk - 1) >= total
        local look    = (not R.look_sent) and (R.look or capture_look()) or nil

        local ok = send_block_awaiting_ack(rid, seq, slice, is_last, look)
        if ok then
            R.look_sent = true
        else
            -- bloco perdido apos todas as tentativas: replay deste jogador fica
            -- truncado aqui, mas NAO trava o fechamento dos outros participantes.
            return
        end

        i = i + chunk
    end

    -- corrida sem nenhum frame (jogador nunca dirigiu): ainda envia o final=true
    -- vazio para o servidor nao ficar esperando os 60s do SEND_TIMEOUT_TOTAL_MS.
    if total == 0 then
        seq = seq + 1
        send_block_awaiting_ack(rid, seq, {}, true, (not R.look_sent) and (R.look or capture_look()) or nil)
    end
end


-- ============================================================
-- THREADS — amostragem 20Hz (gateada por R.active, L-06)
-- ============================================================

local function start_threads()
    if not R.sampling then
        R.sampling = true
        Citizen.CreateThread(function()
            while R.active do
                local f = sample()
                if f then R.buf[#R.buf + 1] = f end
                Citizen.Wait(Cfg.SAMPLE_MS or 100)
            end
            R.sampling = false
        end)
    end
end


local function stop_rec(do_upload)
    if not R.active then return end
    R.active = false
    local rid = R.rid
    R.rid     = nil

    if do_upload and rid then
        if R.sending then return end
        R.sending = true
        Citizen.CreateThread(function()
            upload_all(rid)
            R.sending = false
        end)
    else
        R.buf = {}
    end
end


-- ============================================================
-- EVENTOS DO SERVIDOR
-- ============================================================

RegisterNetEvent('vhub_vrcs:recStart')
AddEventHandler('vhub_vrcs:recStart', function(rid)
    if type(rid) ~= 'string' then return end
    if R.active then stop_rec(false) end
    R.rid       = rid
    R.active    = true
    R.start_ms  = GetGameTimer()
    R.buf       = {}
    R.look_sent = false
    R.look      = capture_look()
    start_threads()
end)


RegisterNetEvent('vhub_vrcs:recStop')
AddEventHandler('vhub_vrcs:recStop', function(rid)
    if not R.active or rid ~= R.rid then return end
    stop_rec(true)
end)


-- ACK do bloco enviado em upload_all (ver send_block_awaiting_ack)
RegisterNetEvent('vhub_vrcs:recAck')
AddEventHandler('vhub_vrcs:recAck', function(rid, seq, ok)
    if not _pending_ack or _pending_ack.rid ~= rid or _pending_ack.seq ~= seq then return end
    _pending_ack.ok   = ok == true
    _pending_ack.done = true
end)


AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    R.active = false
end)
