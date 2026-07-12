-- cl.lua — mecanica de drift (handling + boost) + fabricacao de pontuacao bruta.
-- A pontuacao (angulo x velocidade x combo) e fabricada AQUI e exposta via export
-- getTelemetry(); quem BANCA a pontuacao valida e o vhub_racha (modo drift).
-- Esta camada NAO desenha UI — o HUD e responsabilidade do vhub_racha.


-- ============================================================
-- NATIVES (cache local)
-- ============================================================

local PlayerPedId                     = PlayerPedId
local GetVehiclePedIsIn               = GetVehiclePedIsIn
local GetPedInVehicleSeat             = GetPedInVehicleSeat
local GetVehicleClass                 = GetVehicleClass
local GetEntitySpeed                  = GetEntitySpeed
local IsControlPressed                = IsControlPressed
local DisableControlAction            = DisableControlAction
local SetVehicleModKit                = SetVehicleModKit
local ToggleVehicleMod                = ToggleVehicleMod
local IsToggleModOn                   = IsToggleModOn
local SetVehicleHandlingFloat         = SetVehicleHandlingFloat
local GetVehicleHandlingFloat         = GetVehicleHandlingFloat
local SetVehicleEnginePowerMultiplier = SetVehicleEnginePowerMultiplier
local DoesEntityExist                 = DoesEntityExist
local IsVehicleOnAllWheels            = IsVehicleOnAllWheels
local GetEntityVelocity               = GetEntityVelocity
local GetEntityForwardVector          = GetEntityForwardVector
local GetVehicleBodyHealth            = GetVehicleBodyHealth
local GetGameTimer                    = GetGameTimer
local RequestNamedPtfxAsset           = RequestNamedPtfxAsset
local HasNamedPtfxAssetLoaded         = HasNamedPtfxAssetLoaded
local UseParticleFxAssetNextCall      = UseParticleFxAssetNextCall
local StartParticleFxLoopedOnEntityBone = StartParticleFxLoopedOnEntityBone
local StopParticleFxLooped            = StopParticleFxLooped
local GetEntityBoneIndexByName        = GetEntityBoneIndexByName
local SetParticleFxLoopedAlpha        = SetParticleFxLoopedAlpha
local CreateThread                    = CreateThread
local Wait                            = Wait
local math_sqrt, math_acos, math_deg  = math.sqrt, math.acos, math.deg
local math_min                        = math.min


-- ============================================================
-- CONFIG
-- ============================================================

-- Veiculos elegiveis (classes GTA: rua/esporte/super/muscle/SUV/etc).
local CLASS_WHITELIST = {
    [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,
    [5]=true,[6]=true,[7]=true,[9]=true
}

-- Handling aplicado ao entrar em drift (revertido ao sair).
local DRIFT_MODS = {
    {"fSteeringLock",              15.0},
    {"fTractionCurveMax",         -0.65},
    {"fTractionCurveMin",         -0.20},
    {"fTractionCurveLateral",      1.00},
    {"fLowSpeedTractionLossMult", -0.70},
    {"fDriveInertia",              0.20},
    {"fInitialDragCoeff",         -20.0},
}

-- Boost controlado (anti-exploit): exige angulo real, cooldown e duracao limitada.
local DRIFT_MIN_SPEED = 30.0   -- km/h minimos para interceptar o freio de mao
local DRIFT_MIN_ANGLE = 5.0    -- graus minimos para ativar assistencia de drift
local BOOST_COOLDOWN  = 4000   -- ms entre boosts
local BOOST_DURATION  = 1200   -- ms maximo por boost
local MIN_BOOST_ANGLE = DRIFT_MIN_ANGLE   -- graus minimos para o boost ativar

-- Fumaca visual: mod 20 nativo + camada extra local nos pneus traseiros.
local SMOKE_PTFX_ASSET = 'core'
local SMOKE_PTFX_NAME  = 'wheel_fric_hard'
local SMOKE_PTFX_SCALE = 1.15
local SMOKE_PTFX_ALPHA = 0.85
local SMOKE_BONES      = { 'wheel_lr', 'wheel_rr' }

-- Fabricacao de pontuacao. MANTER alinhado com vhub_racha Cfg.DRIFT — o SERVER
-- e a autoridade final (faz o cap por segundo). Aqui so geramos a pontuacao bruta.
local SCORE_MIN_ANGLE   = DRIFT_MIN_ANGLE -- graus minimos para pontuar
local SCORE_MIN_SPEED   = DRIFT_MIN_SPEED -- km/h minimos para pontuar
local SCORE_DIVISOR     = 65.0          -- divisor base (angulo*velocidade/divisor)
local SCORE_CAP_PER_SEC = 100.0         -- teto bruto por segundo (antes do combo)
local CRASH_HEALTH_DROP = 8.0           -- queda de body health que conta como "bateu"
local COMBO_BREAK_MS    = 700           -- graca antes do combo cair (oscilacao normal)
local COMBO_THRESHOLDS  = { 5.0, 12.0, 25.0 }   -- segundos de drift continuo
local COMBO_MULT        = { 1.5, 2.0, 3.0 }


-- ============================================================
-- STATE
-- ============================================================

-- Mecanica
local driftActive    = false
local lastVehicle    = 0
local powerMult      = 1.2
local boostActive    = false
local boostStartTime = 0
local lastBoostEnd   = 0
local lastHealth     = 0
local lastTick       = 0
local smokeVehicle   = 0
local smokeWasOn     = nil
local smokeHandles   = {}
local smokePtfxReady = false
local smokePtfxRequested = false
local smokeFxAttempted = false

-- Pontuacao (consumida pelo vhub_racha via getTelemetry)
local totalEarned    = 0.0     -- monotonico: total bruto fabricado (NUNCA zera)
local crashCount     = 0       -- monotonico: incrementa a cada "batida"
local driftTimeMs    = 0       -- tempo de drift continuo (alimenta o combo)
local breakMs        = 0       -- tempo fora do drift (graca antes do combo cair)
local combo          = 1.0
local currentAngle   = 0.0
local currentSpeed   = 0.0
local isScoring      = false


-- ============================================================
-- TELEMETRY (export read-only)
-- ============================================================

-- snapshot da mecanica/pontuacao; quem banca a pontuacao valida e o vhub_racha.
local function telemetry()
    return {
        total    = totalEarned,
        crashes  = crashCount,
        combo    = combo,
        angle    = currentAngle,
        speed    = currentSpeed,
        drifting = isScoring,
        active   = driftActive,
    }
end

exports('getTelemetry', telemetry)


-- ============================================================
-- HELPERS
-- ============================================================

-- combo em funcao do tempo de drift continuo (segundos).
local function comboFor(ms)
    local secs = ms / 1000.0
    local mult = 1.0
    for i = 1, #COMBO_THRESHOLDS do
        if secs >= COMBO_THRESHOLDS[i] then mult = COMBO_MULT[i] end
    end
    return mult
end

-- angulo entre a velocidade e a frente do veiculo (graus) — 0 em linha reta.
local function getDriftAngle(veh)
    local vel = GetEntityVelocity(veh)
    local speed = math_sqrt(vel.x^2 + vel.y^2 + vel.z^2)
    if speed < 5.0 then return 0.0 end
    local fwd = GetEntityForwardVector(veh)
    local dot = (vel.x*fwd.x + vel.y*fwd.y + vel.z*fwd.z) / speed
    if dot > 1.0 then dot = 1.0 elseif dot < -1.0 then dot = -1.0 end
    return math_deg(math_acos(dot))
end

local function ensureSmokePtfx()
    if smokePtfxReady then return true end

    if not smokePtfxRequested then
        RequestNamedPtfxAsset(SMOKE_PTFX_ASSET)
        smokePtfxRequested = true
    end

    smokePtfxReady = HasNamedPtfxAssetLoaded(SMOKE_PTFX_ASSET)
    return smokePtfxReady
end

local function stopDriftSmoke()
    for i = 1, #smokeHandles do
        StopParticleFxLooped(smokeHandles[i], false)
    end
    smokeHandles = {}
    smokeFxAttempted = false

    if smokeVehicle ~= 0 and DoesEntityExist(smokeVehicle) and smokeWasOn == false then
        SetVehicleModKit(smokeVehicle, 0)
        ToggleVehicleMod(smokeVehicle, 20, false)
    end

    smokeVehicle = 0
    smokeWasOn   = nil
end

local function startDriftSmoke(veh)
    if smokeVehicle ~= veh then
        stopDriftSmoke()
        smokeVehicle = veh
        smokeWasOn   = IsToggleModOn(veh, 20)

        if not smokeWasOn then
            SetVehicleModKit(veh, 0)
            ToggleVehicleMod(veh, 20, true)
        end
    end

    if smokeFxAttempted or #smokeHandles > 0 or not ensureSmokePtfx() then return end
    smokeFxAttempted = true

    for i = 1, #SMOKE_BONES do
        local bone = GetEntityBoneIndexByName(veh, SMOKE_BONES[i])
        if bone ~= -1 then
            UseParticleFxAssetNextCall(SMOKE_PTFX_ASSET)
            local handle = StartParticleFxLoopedOnEntityBone(
                SMOKE_PTFX_NAME, veh, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                bone, SMOKE_PTFX_SCALE, false, false, false
            )
            if handle and handle ~= 0 then
                SetParticleFxLoopedAlpha(handle, SMOKE_PTFX_ALPHA)
                smokeHandles[#smokeHandles + 1] = handle
            end
        end
    end
end

local function setHandling(veh, enable)
    if not DoesEntityExist(veh) then return end
    local m = enable and 1 or -1
    for _, v in ipairs(DRIFT_MODS) do
        local cur = GetVehicleHandlingFloat(veh, "CHandlingData", v[1])
        SetVehicleHandlingFloat(veh, "CHandlingData", v[1], cur + (v[2]*m))
    end
end

local function revertDrift(veh)
    if driftActive and veh ~= 0 and DoesEntityExist(veh) then
        setHandling(veh, false)
        SetVehicleEnginePowerMultiplier(veh, 1.0)
    end
    stopDriftSmoke()
    driftActive = false
    boostActive = false   -- cancela boost sem resetar cooldown (lastBoostEnd preservado)
end

-- F-058 (ADR #48): restart do resource restaura o handling do carro em drift —
-- sem isto o veículo ficava com os deltas de drift "viciados" para sempre.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    revertDrift(lastVehicle)
end)

local function activateDrift(veh)
    driftActive = true
    setHandling(veh, true)
    startDriftSmoke(veh)
    local bias = GetVehicleHandlingFloat(veh, "CHandlingData", "fDriveBiasFront")
    powerMult = (bias == 0.0) and 150.0 or 120.0
end

-- zera combo/tempo de drift (NAO mexe em totalEarned/crashCount — sao monotonicos).
local function resetCombo()
    driftTimeMs = 0
    breakMs     = 0
    combo       = 1.0
    isScoring   = false
end


-- ============================================================
-- MAIN LOOP — mecanica + fabricacao de pontuacao
-- ============================================================

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= 0 and GetPedInVehicleSeat(veh,-1) == ped and CLASS_WHITELIST[GetVehicleClass(veh)] then

            if veh ~= lastVehicle then
                revertDrift(lastVehicle)
                lastVehicle  = veh
                lastHealth   = GetVehicleBodyHealth(veh)
                lastTick     = GetGameTimer()
                boostActive  = false
                lastBoostEnd = 0
                resetCombo()
            end

            local speedKMH  = GetEntitySpeed(veh) * 3.6
            local timeNow   = GetGameTimer()
            local dt        = timeNow - lastTick
            if dt < 0 then dt = 0 end
            lastTick        = timeNow
            currentSpeed    = speedKMH

            -- Batida: queda brusca de body health.
            local healthNow = GetVehicleBodyHealth(veh)
            local crashed   = healthNow < (lastHealth - CRASH_HEALTH_DROP)
            lastHealth = healthNow
            if crashed then
                crashCount = crashCount + 1
                resetCombo()
            end

            if speedKMH < 20.0 and not driftActive then
                Wait(250)
                lastTick = GetGameTimer()
            else
                local isAccelerating = IsControlPressed(0, 71)
                local isHandbraking  = IsControlPressed(0, 76)
                currentAngle = getDriftAngle(veh)

                -- ── Mecanica: handling + boost ──────────────────────────────
                local driftReady = speedKMH > DRIFT_MIN_SPEED and currentAngle > DRIFT_MIN_ANGLE
                local driftInput = isAccelerating and isHandbraking and IsVehicleOnAllWheels(veh)

                if driftInput and driftReady then
                    DisableControlAction(0, 76, true)
                    if not driftActive then
                        activateDrift(veh)
                    else
                        startDriftSmoke(veh)
                    end

                    -- Boost: velocidade + angulo obrigatorios, cooldown e duracao limitada.
                    if not boostActive
                        and (timeNow - lastBoostEnd) > BOOST_COOLDOWN
                        and speedKMH > DRIFT_MIN_SPEED
                        and currentAngle > MIN_BOOST_ANGLE then
                        boostActive    = true
                        boostStartTime = timeNow
                    end

                    if boostActive then
                        if (timeNow - boostStartTime) >= BOOST_DURATION then
                            -- Duracao esgotada: encerra boost e inicia cooldown.
                            boostActive  = false
                            lastBoostEnd = timeNow
                            SetVehicleEnginePowerMultiplier(veh, powerMult)
                        else
                            SetVehicleEnginePowerMultiplier(veh, powerMult * 2.0)
                        end
                    else
                        SetVehicleEnginePowerMultiplier(veh, powerMult)
                    end

                else
                    -- Fora do gate: freio de mao volta ao GTA e o torque zera no mesmo tick.
                    if boostActive then
                        boostActive  = false
                        lastBoostEnd = timeNow
                    end

                    if driftActive then
                        revertDrift(veh)
                    end
                end

                -- ── Fabricacao de pontuacao bruta ───────────────────────────
                if not crashed and currentAngle > SCORE_MIN_ANGLE and speedKMH > SCORE_MIN_SPEED then
                    isScoring   = true
                    breakMs     = 0
                    driftTimeMs = driftTimeMs + dt
                    combo       = comboFor(driftTimeMs)
                    local pps = math_min((currentAngle * speedKMH) / SCORE_DIVISOR, SCORE_CAP_PER_SEC)
                    totalEarned = totalEarned + (pps * combo) * (dt / 1000.0)
                elseif not crashed then
                    isScoring = false
                    breakMs   = breakMs + dt
                    if breakMs >= COMBO_BREAK_MS then
                        driftTimeMs = 0
                        combo       = 1.0
                    end
                end

                Wait(0)
            end
        else
            if driftActive or lastVehicle ~= 0 then
                revertDrift(lastVehicle ~= 0 and lastVehicle or veh)
                lastVehicle = 0
                boostActive = false
                resetCombo()
            end
            Wait(1000)
            lastTick = GetGameTimer()
        end
    end
end)
