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
local SetVehicleHandlingFloat         = SetVehicleHandlingFloat
local GetVehicleHandlingFloat         = GetVehicleHandlingFloat
local SetVehicleEnginePowerMultiplier = SetVehicleEnginePowerMultiplier
local DoesEntityExist                 = DoesEntityExist
local IsVehicleOnAllWheels            = IsVehicleOnAllWheels
local GetEntityVelocity               = GetEntityVelocity
local GetEntityForwardVector          = GetEntityForwardVector
local GetVehicleBodyHealth            = GetVehicleBodyHealth
local GetGameTimer                    = GetGameTimer
local CreateThread                    = CreateThread
local Wait                            = Wait
local math_sqrt, math_acos, math_deg  = math.sqrt, math.acos, math.deg
local math_min, math_max              = math.min, math.max


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
local BOOST_COOLDOWN  = 4000   -- ms entre boosts
local BOOST_DURATION  = 1200   -- ms maximo por boost
local MIN_BOOST_ANGLE = 20.0   -- graus minimos para o boost ativar

-- Fabricacao de pontuacao. MANTER alinhado com vhub_racha Cfg.DRIFT — o SERVER
-- e a autoridade final (faz o cap por segundo). Aqui so geramos a pontuacao bruta.
local SCORE_MIN_ANGLE   = 15.0          -- graus minimos para pontuar
local SCORE_MIN_SPEED   = 30.0          -- km/h minimos para pontuar
local SCORE_DIVISOR     = 40.0          -- divisor base (angulo*velocidade/divisor)
local SCORE_CAP_PER_SEC = 150.0         -- teto bruto por segundo (antes do combo)
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
    driftActive = false
    boostActive = false   -- cancela boost sem resetar cooldown (lastBoostEnd preservado)
end

local function activateDrift(veh)
    driftActive = true
    setHandling(veh, true)
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
                if speedKMH > 20.0 and isAccelerating and isHandbraking and IsVehicleOnAllWheels(veh) then
                    DisableControlAction(0, 76, true)
                    if not driftActive then activateDrift(veh) end

                    -- Boost: angulo obrigatorio + cooldown + duracao limitada.
                    if not boostActive
                        and (timeNow - lastBoostEnd) > BOOST_COOLDOWN
                        and currentAngle >= MIN_BOOST_ANGLE then
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
                    -- Espaco solto: aborta boost e forca cooldown imediato (anti-spam).
                    if boostActive then
                        boostActive  = false
                        lastBoostEnd = timeNow
                    end

                    if driftActive then
                        if isAccelerating and currentAngle > 5.0 then
                            -- Potencia proporcional ao angulo: elimina drop abrupto
                            -- ao entrar em curvas <100km/h. t=0 → piso 12% ; t=1 → 100%.
                            local t = math_min(currentAngle / 30.0, 1.0)
                            SetVehicleEnginePowerMultiplier(veh, 1.0 + (powerMult-1.0) * math_max(t, 0.12))
                        else
                            revertDrift(veh)
                        end
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
