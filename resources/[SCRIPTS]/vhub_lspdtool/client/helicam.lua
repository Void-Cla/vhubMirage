---@diagnostic disable: undefined-global, lowercase-global

-- helicam.lua — câmera de helicóptero NATIVA do LSPD Tool (camada L2/HAL). FASE B.
--
-- Câmera scriptada presa ao heli (FLIR): zoom, rotação (slew), visão normal/nightvision/thermal,
-- holofote e lock por raycast. Ao travar um veículo, lê a placa e ENCAMINHA ao pipeline seguro
-- (PLATE_SCANNED kind='air') — a NUI/HUD é overlay PASSIVO. O servidor decide a verdade (canScan,
-- coords). A câmera é efêmera client-side (L-02): nenhuma verdade crítica mora aqui.

local cfg = VHubLspd.cfg.helicam
local E   = VHubLspd.E
local UI  = VHubLspd.UI


-- ============================================================
-- ESTADO (efêmero)
-- ============================================================

local running  = true         -- saída determinística da thread (L-06)
local active   = false        -- câmera ligada
local cam      = nil          -- handle da cam scriptada
local heli     = 0            -- helicóptero atual
local fov      = cfg.fov.default
local yaw      = 0.0          -- rotação horizontal (mundo)
local pitch    = -45.0        -- rotação vertical (olhando p/ baixo-frente)
local vision   = 0            -- 0 = normal (HDEO), 1 = nightvision (HDNV), 2 = thermal (HDIR)
local spotOn   = false        -- holofote ligado
local lockEnt  = 0            -- entidade travada (0 = nenhuma)
local hudSnap  = ''           -- dedup do helicam:update
local hudAt    = 0            -- último envio de HUD

local VISION_LABEL = { [0] = 'HDEO', [1] = 'HDNV', [2] = 'HDIR' }

-- IDs de controle:
--   1 = LOOK_LR · 2 = LOOK_UD · 14/15 = WEAPON_WHEEL_NEXT/PREV = scroll do mouse in-game.
--   NOTA: 241/242 (CURSOR_SCROLL) só funcionam com NuiFocus — a câmera é PASSIVA, então usamos 14/15.
local CTRL_LR, CTRL_UD, CTRL_ZIN, CTRL_ZOUT = 1, 2, 14, 15


-- ============================================================
-- HELI / OCUPAÇÃO
-- ============================================================

-- veículo atual do jogador, ou 0
local function currentVeh()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return 0 end
    return GetVehiclePedIsIn(ped, false)
end

-- true se o jogador pode operar a câmera deste veículo (é heli + regra passenger opcional)
local function canOperate(veh)
    if veh == 0 or not IsThisModelAHeli(GetEntityModel(veh)) then return false end
    if cfg.passengerOnly then
        local ped = PlayerPedId()
        if GetPedInVehicleSeat(veh, -1) == ped then return false end   -- piloto não opera
    end
    return true
end


-- ============================================================
-- CÂMERA (criar / destruir / orientar)
-- ============================================================

-- vetor direção do mundo a partir de pitch/yaw (ordem GTA ZYX)
local function dirFromRot(p, y)
    local rp, ry = math.rad(p), math.rad(y)
    local cosP = math.cos(rp)
    return vector3(-math.sin(ry) * cosP, math.cos(ry) * cosP, math.sin(rp))
end

-- cria a cam presa ao heli e começa a renderizar
local function createCam()
    local off = cfg.defaultOffset
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    AttachCamToEntity(cam, heli, off.x, off.y, off.z, true)
    yaw   = GetEntityHeading(heli)
    pitch = -45.0
    fov   = cfg.fov.default
    SetCamRot(cam, pitch, 0.0, yaw, 2)
    SetCamFov(cam, fov)
    RenderScriptCams(true, true, 500, true, true)
end

-- restaura a câmera de jogo e libera recursos
local function destroyCam()
    RenderScriptCams(false, true, 500, true, true)
    if cam then DestroyCam(cam, true); cam = nil end
end


-- ============================================================
-- VISÃO (normal / nightvision / thermal)
-- ============================================================

-- aplica o modo de visão atual aos natives
local function applyVision()
    SetNightvision(vision == 1)
    SetSeethrough(vision == 2)
end

-- cicla normal → NV → thermal → normal
local function cycleVision()
    vision = (vision + 1) % 3
    applyVision()
end


-- ============================================================
-- HOLOFOTE (local — sem sync multiplayer, decisão do arquiteto)
-- ============================================================

-- desenha o cone do holofote a partir do heli na direção da câmera (chamado por frame)
local function drawSpot()
    local sc = cfg.spotlight
    local from = GetCamCoord(cam)
    local dir  = dirFromRot(pitch, yaw)
    DrawSpotLightWithShadow(
        from.x, from.y, from.z, dir.x, dir.y, dir.z,
        sc.color[1], sc.color[2], sc.color[3],
        sc.distance, sc.brightness, 0.0, sc.radius, sc.falloff, 0)
end


-- ============================================================
-- LOCK + LEITURA DE PLACA (raycast próprio, z-aware p/ ângulo íngreme)
-- ============================================================

-- placa limpa (string vazia se sem placa)
local function plateOf(veh)
    local p = GetVehicleNumberPlateText(veh)
    return p and (p:gsub('%s+$', '')) or ''
end

-- tenta travar no que estiver no centro da mira; se for veículo, encaminha a placa (kind='air')
local function attemptLock()
    if lockEnt ~= 0 then lockEnt = 0; return end          -- segundo toque = solta o lock

    local from = GetCamCoord(cam)
    local to   = from + dirFromRot(pitch, yaw) * cfg.targetMaxReach
    -- síncrono + flags=-1 (tudo): o feixe da heli aponta p/ baixo em ângulo, então a direção real
    -- da câmera é a fonte (z-aware por construção). Ignora o próprio jogador.
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        from.x, from.y, from.z, to.x, to.y, to.z, -1, PlayerPedId(), 7)
    local _, hit, _, _, ent = GetShapeTestResult(ray)

    if hit ~= 1 or not ent or ent == 0 then return end

    lockEnt = ent
    if IsEntityAVehicle(ent) and cfg.autoAirScan then
        local plate = plateOf(ent)
        if plate ~= '' then
            TriggerServerEvent(E.PLATE_SCANNED, { plate = plate, kind = 'air' })   -- só "placa lida"
        end
    end
end


-- ============================================================
-- HUD (overlay passivo — delta, sem payload por frame)
-- ============================================================

-- monta os dados do alvo travado (placa/velocidade/distância) ou nil
local function targetData()
    if lockEnt == 0 or not DoesEntityExist(lockEnt) then return nil end
    local d = #(GetCamCoord(cam) - GetEntityCoords(lockEnt))
    local isVeh = IsEntityAVehicle(lockEnt)
    return {
        plate = isVeh and plateOf(lockEnt) or '',
        speed = isVeh and math.floor(GetEntitySpeed(lockEnt) * 3.6 + 0.5) or 0,
        dist  = math.floor(d + 0.5),
    }
end

-- envia o estado ao HUD só quando muda (dedup) e no máximo a cada updateHudMs
local function pushHud()
    local now = GetGameTimer()
    if now - hudAt < cfg.updateHudMs then return end
    hudAt = now

    local zoom = math.floor((1.0 - (fov - cfg.fov.min) / (cfg.fov.max - cfg.fov.min)) * 100 + 0.5)
    local alt  = math.floor(GetEntityCoords(heli).z + 0.5)
    local hdg  = math.floor(yaw % 360 + 0.5)
    local tgt  = targetData()

    local sig = table.concat({
        zoom, alt, hdg, vision, spotOn and 1 or 0,
        lockEnt ~= 0 and 1 or 0,
        tgt and (tgt.plate .. tgt.speed .. tgt.dist) or '-',
    }, '|')
    if sig == hudSnap then return end
    hudSnap = sig

    SendNUIMessage({
        type = UI.HELI_UPDATE,
        zoom = zoom, altitude = alt, heading = hdg,
        vision = VISION_LABEL[vision], spotlight = spotOn,
        locked = lockEnt ~= 0,
        target = tgt,
    })
end


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- abre a câmera (sem foco NUI; o HUD é overlay passivo)
local function openCam()
    heli = currentVeh()
    if not canOperate(heli) then return end
    active = true
    lockEnt, spotOn, vision = 0, false, 0
    createCam()
    DisplayRadar(false)
    SendNUIMessage({ type = UI.HELI_OPEN })
end

-- fecha a câmera e limpa TUDO (A-07 / cleanup natives)
local function closeCam()
    if not active then return end
    active = false
    spotOn, lockEnt = false, 0
    SetNightvision(false)
    SetSeethrough(false)
    destroyCam()
    DisplayRadar(true)
    hudSnap = ''
    SendNUIMessage({ type = UI.HELI_CLOSE })
end


-- ============================================================
-- LOOP DA CÂMERA (só roda com a câmera ATIVA — idle zero)
-- ============================================================

CreateThread(function()
    while running do
        if active then
            Wait(0)

            -- saiu do heli / heli sumiu → fecha
            if not canOperate(currentVeh()) then closeCam() end

            if active then
                -- bloqueia controles que atrapalham (lemos look/zoom como "disabled")
                DisableControlAction(0, CTRL_LR, true)
                DisableControlAction(0, CTRL_UD, true)
                DisableControlAction(0, CTRL_ZIN, true)    -- 14 (scroll up / wheel next)
                DisableControlAction(0, CTRL_ZOUT, true)   -- 15 (scroll down / wheel prev)
                DisableControlAction(0, 24, true)   -- attack
                DisableControlAction(0, 25, true)   -- aim

                -- LOOK → slew yaw/pitch (sensibilidade escala com o zoom: mais zoom, mais fino)
                local fovScale = fov / cfg.fov.max
                local lr = GetDisabledControlNormal(0, CTRL_LR)
                local ud = GetDisabledControlNormal(0, CTRL_UD)
                yaw   = yaw - lr * cfg.lookSpeed * fovScale * 3.0
                pitch = math.max(cfg.pitchLimit.down,
                          math.min(cfg.pitchLimit.up, pitch - ud * cfg.lookSpeed * fovScale * 3.0))

                -- ZOOM → FOV (scroll)
                if IsDisabledControlPressed(0, CTRL_ZIN)  then fov = math.max(cfg.fov.min, fov - cfg.fov.step) end
                if IsDisabledControlPressed(0, CTRL_ZOUT) then fov = math.min(cfg.fov.max, fov + cfg.fov.step) end
                SetCamFov(cam, fov)

                -- LOCK ativo segue o alvo; senão a câmera aponta pela rotação manual
                if lockEnt ~= 0 and DoesEntityExist(lockEnt) then
                    PointCamAtEntity(cam, lockEnt, 0.0, 0.0, 0.0, true)
                else
                    lockEnt = 0
                    SetCamRot(cam, pitch, 0.0, yaw, 2)
                end

                if spotOn then drawSpot() end
                pushHud()
            end
        else
            Wait(250)   -- ocioso: custo desprezível quando a câmera está desligada
        end
    end
end)


-- ============================================================
-- TECLAS (X compartilhada com o radar via guarda de contexto)
-- ============================================================

-- 'X': liga/desliga a heli-câmera. Só age dentro de um heli (fora dele, o comando do radar age).
RegisterCommand('vhub_lspd_helicam', function()
    if active then closeCam()
    elseif canOperate(currentVeh()) then openCam() end
end, false)
RegisterKeyMapping('vhub_lspd_helicam', 'LSPD: heli-câmera (ligar/desligar)', 'keyboard', cfg.toggleKey or 'X')

-- ações que SÓ valem com a câmera ativa (guardadas por `active`)
RegisterCommand('vhub_lspd_helicam_vision', function() if active then cycleVision() end end, false)
RegisterKeyMapping('vhub_lspd_helicam_vision', 'LSPD: heli-câmera ciclar visão', 'keyboard', cfg.visionKey or 'TAB')

RegisterCommand('vhub_lspd_helicam_spot', function() if active then spotOn = not spotOn end end, false)
RegisterKeyMapping('vhub_lspd_helicam_spot', 'LSPD: heli-câmera holofote', 'keyboard', cfg.spotKey or 'G')

RegisterCommand('vhub_lspd_helicam_lock', function() if active then attemptLock() end end, false)
RegisterKeyMapping('vhub_lspd_helicam_lock', 'LSPD: heli-câmera travar alvo', 'keyboard', cfg.lockKey or 'SPACE')


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    running = false
    if active then closeCam() end
end)
