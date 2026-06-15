---@diagnostic disable: undefined-global, lowercase-global

-- radar.lua — radar NATIVO do LSPD Tool (camada L2/HAL). Substitui o escrow sd-policeradar.
--
-- Detecta veículos à frente/atrás por raycast (capsule), lê velocidade + placa LOCALMENTE
-- (apenas para a UI) e encaminha a placa NOVA ao servidor pelo pipeline seguro
-- (PLATE_SCANNED → canScan/coords/BOLO/auditoria). A NUI é um overlay PASSIVO (sem NuiFocus).
-- O servidor é a ÚNICA autoridade de "quem é policial" e de onde o scan ocorreu (L-01).

local cfg = VHubLspd.cfg.radar
local E   = VHubLspd.E
local UI  = VHubLspd.UI


-- ============================================================
-- ESTADO (efêmero — UI/HAL; nada crítico mora aqui)
-- ============================================================

local running = true     -- saída determinística da thread (L-06)
local enabled = false    -- radar ligado (autorizado pelo servidor)
local shown   = false    -- overlay visível na NUI
local locked  = false    -- leituras congeladas (trava)
local armed   = true     -- auto-open re-armado (reopenAfterLeave)
local reqAt   = 0        -- último REQ_RADAR (anti-spam local)

local snap    = { patrol = -1, f = '', r = '' }   -- dedup do SendNUIMessage
local frozen  = { front = nil, rear = nil }        -- alvo capturado no instante da trava
local lastFwd = { front = nil, rear = nil }        -- última placa encaminhada por câmera


-- ============================================================
-- LEITURA (natives — confiáveis client-side; só para a UI)
-- ============================================================

-- placa limpa do veículo (string vazia se sem placa)
local function plateOf(veh)
    local p = GetVehicleNumberPlateText(veh)
    return p and (p:gsub('%s+$', '')) or ''
end

-- velocidade em km/h inteira
local function speedKmh(veh)
    return math.floor(GetEntitySpeed(veh) * 3.6 + 0.5)
end

-- true se o veículo é heli/avião (o radar é p/ SOLO; aeronave é território do helicam, mesma tecla X)
local function isAircraft(veh)
    if not veh or veh == 0 then return false end
    local m = GetEntityModel(veh)
    return IsThisModelAHeli(m) or IsThisModelAPlane(m)
end

-- raycast à frente (dir=1) ou atrás (dir=-1); retorna a entidade veículo alvo (ou 0).
-- Pontos via GetOffsetFromEntityInWorldCoords (z-aware: acompanham o pitch em ladeira; eixo Y =
-- frente do veículo). Probe SÍNCRONO → resultado válido no mesmo frame (o capsule é assíncrono e
-- retornaria pendente). flags=2 = só veículos (um ped não "consome" o feixe e mascara o carro atrás).
local function rayTarget(ownVeh, range, dir)
    local from = GetOffsetFromEntityInWorldCoords(ownVeh, 0.0, cfg.skipAhead * dir, 0.3)
    local to   = GetOffsetFromEntityInWorldCoords(ownVeh, 0.0, range * dir,         0.3)

    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        from.x, from.y, from.z, to.x, to.y, to.z, 2, ownVeh, 7)
    local _, hit, _, _, ent = GetShapeTestResult(ray)

    if hit == 1 and ent and ent ~= 0 and ent ~= ownVeh and IsEntityAVehicle(ent) then
        return ent
    end
    return 0
end

-- monta { speed, plate } do alvo, ou nil quando não há veículo no feixe
local function readTarget(ownVeh, range, dir)
    local ent = rayTarget(ownVeh, range, dir)
    if ent == 0 then return nil end
    return { speed = speedKmh(ent), plate = plateOf(ent) }
end


-- ============================================================
-- NUI (overlay passivo — SendNUIMessage, sem foco; A-06/A-08)
-- ============================================================

-- mostra/esconde o overlay (idempotente)
local function showRadar(state)
    if state == shown then return end
    shown = state
    SendNUIMessage({ type = state and UI.OPEN or UI.CLOSE })
end

-- envia o delta de estado à NUI só quando algo muda (sem spam de 200ms)
local function pushUpdate(patrol, front, rear)
    local f = front and (front.plate .. '|' .. front.speed) or ''
    local r = rear  and (rear.plate  .. '|' .. rear.speed)  or ''
    if patrol == snap.patrol and f == snap.f and r == snap.r then return end

    snap.patrol, snap.f, snap.r = patrol, f, r
    SendNUIMessage({
        type   = UI.UPDATE,
        patrol = patrol,
        unit   = cfg.unit,
        locked = locked,
        front  = front,   -- { speed, plate } | nil
        rear   = rear,    -- { speed, plate } | nil
    })
end


-- ============================================================
-- ENCAMINHAMENTO AO PIPELINE SEGURO (BOLO/auditoria server-side)
-- ============================================================

-- encaminha uma placa NOVA ao servidor. O pipeline valida policial, deriva coords reais,
-- aplica rate/dedup e checa BOLO — a placa lida aqui é só intenção (nunca verdade, L-02).
local function forwardPlate(cam, t)
    if not (cfg.autoBoloScan and t and t.plate ~= '') then return end
    if lastFwd[cam] == t.plate then return end
    lastFwd[cam] = t.plate
    TriggerServerEvent(E.PLATE_SCANNED, { plate = t.plate, kind = 'ground' })
end


-- ============================================================
-- AUTORIZAÇÃO (servidor decide; cliente só pede)
-- ============================================================

-- pede autorização de radar ao servidor (anti-spam local de 1s)
local function requestRadar()
    local now = GetGameTimer()
    if now - reqAt < 1000 then return end
    reqAt = now
    TriggerServerEvent(E.REQ_RADAR)
end

-- servidor confirmou que o player é policial → liga o radar
RegisterNetEvent(E.ENABLE_RADAR, function()
    enabled = true
end)


-- ============================================================
-- TECLAS
-- ============================================================

-- 'X': liga/desliga. Ligar PEDE ao servidor (autoridade); desligar é local.
RegisterCommand('vhub_lspd_radar', function()
    -- em heli/avião o X pertence ao helicam (ambos os comandos disparam; cada um se guarda por contexto)
    if isAircraft(GetVehiclePedIsIn(PlayerPedId(), false)) then return end
    if enabled then
        enabled, locked = false, false
        frozen.front, frozen.rear = nil, nil
        armed = false                  -- desligou de propósito: não auto-reabre parado no veículo
        showRadar(false)
    else
        requestRadar()
    end
end, false)
RegisterKeyMapping('vhub_lspd_radar', 'LSPD: ligar/desligar radar', 'keyboard', cfg.toggleKey or 'X')

-- 'K': trava/destrava as leituras (congela o alvo atual de frente e trás)
RegisterCommand('vhub_lspd_lock', function()
    if not enabled then return end
    locked = not locked
    if not locked then frozen.front, frozen.rear = nil, nil end
end, false)
RegisterKeyMapping('vhub_lspd_lock', 'LSPD: travar leitura do radar', 'keyboard', cfg.lockKey or 'K')


-- ============================================================
-- LOOP PRINCIPAL (adaptativo, gated — só custa com radar ON dirigindo)
-- ============================================================

CreateThread(function()
    while running do
        local interval = cfg.idleMs

        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local driving = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and not isAircraft(veh)

        if driving then
            -- auto-open: ao entrar como motorista, pede o radar (servidor valida policial/classe)
            if cfg.autoOpen and armed and not enabled then
                local classOk = cfg.anyVehicle or (GetVehicleClass(veh) == cfg.policeClass)
                if classOk then armed = false; requestRadar() end
            end

            if enabled then
                interval = cfg.updateMs
                local patrol = speedKmh(veh)

                -- leitura ao vivo, ou congelada quando travado
                local front = locked and frozen.front or readTarget(veh, cfg.frontRange, 1)
                local rear  = locked and frozen.rear  or readTarget(veh, cfg.rearRange, -1)
                if locked and frozen.front == nil and frozen.rear == nil then
                    frozen.front, frozen.rear = front, rear   -- captura no instante da trava
                end

                -- encaminha placas novas ao pipeline seguro (só quando NÃO travado)
                if not locked then
                    forwardPlate('front', front)
                    forwardPlate('rear',  rear)
                end

                showRadar(true)
                pushUpdate(patrol, front, rear)
            else
                showRadar(false)
            end
        else
            -- fora do banco do motorista: fecha o overlay e re-arma o auto-open
            if shown then showRadar(false) end
            if enabled and cfg.reopenAfterLeave then enabled = false end
            armed = true
            lastFwd.front, lastFwd.rear = nil, nil
        end

        Wait(interval)
    end
end)


-- ============================================================
-- CLEANUP (A-07 — fecha overlay e encerra a thread)
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    running = false
    SendNUIMessage({ type = UI.CLOSE })
end)
