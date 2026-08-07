-- client/drift.lua — mecanica de drift + fabricacao de pontuacao bruta (FASE 1 ADR #81)
--
-- Versão absorvida de Drift/cl.lua. Ativado por gate: só corre se o veiculo tiver
-- customization.drift_capable=true (State Bag vhub_custom:drift) — lido UMA vez por veiculo
-- (cached por handle), antes de qualquer native — gate gate gate (desempenho e segurança).
-- A pontuação bruta é exposta por exports.vhub_custom:driftTelemetry(); o vhub_racha
-- é quem VALIDA e BANCA. Esta camada não desenha UI.
--
-- F-058 (ADR #48): onResourceStop reverte handling do carro em drift ativo.
---@diagnostic disable: undefined-global


-- ============================================================
-- NATIVES (cache local)
-- ============================================================

local PlayerPedId                       = PlayerPedId
local GetVehiclePedIsIn                 = GetVehiclePedIsIn
local GetPedInVehicleSeat               = GetPedInVehicleSeat
local GetVehicleClass                   = GetVehicleClass
local GetEntitySpeed                    = GetEntitySpeed
local IsControlPressed                  = IsControlPressed
local DisableControlAction              = DisableControlAction
local SetVehicleModKit                  = SetVehicleModKit
local ToggleVehicleMod                  = ToggleVehicleMod
local IsToggleModOn                     = IsToggleModOn
local SetVehicleHandlingFloat           = SetVehicleHandlingFloat
local GetVehicleHandlingFloat           = GetVehicleHandlingFloat
local SetVehicleEnginePowerMultiplier   = SetVehicleEnginePowerMultiplier
local DoesEntityExist                   = DoesEntityExist
local IsVehicleOnAllWheels              = IsVehicleOnAllWheels
local GetEntityVelocity                 = GetEntityVelocity
local GetEntityForwardVector            = GetEntityForwardVector
local GetVehicleBodyHealth              = GetVehicleBodyHealth
local GetGameTimer                      = GetGameTimer
local RequestNamedPtfxAsset             = RequestNamedPtfxAsset
local HasNamedPtfxAssetLoaded           = HasNamedPtfxAssetLoaded
local UseParticleFxAssetNextCall        = UseParticleFxAssetNextCall
local StartParticleFxLoopedOnEntityBone = StartParticleFxLoopedOnEntityBone
local StopParticleFxLooped              = StopParticleFxLooped
local GetEntityBoneIndexByName          = GetEntityBoneIndexByName
local math_sqrt, math_acos, math_deg    = math.sqrt, math.acos, math.deg
local math_min                          = math.min


-- ============================================================
-- CONFIG
-- ============================================================

local CLASS_WHITELIST = {
  [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,
  [5]=true,[6]=true,[7]=true,[9]=true
}

local DRIFT_MODS = {
  {"fSteeringLock",              15.0},
  {"fTractionCurveMax",         -0.65},
  {"fTractionCurveMin",         -0.20},
  {"fTractionCurveLateral",      1.00},
  {"fLowSpeedTractionLossMult", -0.70},
  {"fDriveInertia",              0.20},
  {"fInitialDragCoeff",         -20.0},
}

local DRIFT_MIN_SPEED = 30.0
local DRIFT_MIN_ANGLE = 5.0
local BOOST_COOLDOWN  = 4000
local BOOST_DURATION  = 1200
local MIN_BOOST_ANGLE = DRIFT_MIN_ANGLE

local SMOKE_PTFX_ASSET = 'core'
local SMOKE_PTFX_NAME  = 'wheel_fric_hard'
local SMOKE_PTFX_SCALE = 1.15
local SMOKE_PTFX_ALPHA = 0.85
local SMOKE_BONES      = { 'wheel_lr', 'wheel_rr' }

local SCORE_MIN_ANGLE   = DRIFT_MIN_ANGLE
local SCORE_MIN_SPEED   = DRIFT_MIN_SPEED
local SCORE_DIVISOR     = 65.0
local SCORE_CAP_PER_SEC = 100.0
local CRASH_HEALTH_DROP = 8.0
local COMBO_BREAK_MS    = 700
local COMBO_THRESHOLDS  = { 5.0, 12.0, 25.0 }
local COMBO_MULT        = { 1.5, 2.0, 3.0 }


-- ============================================================
-- STATE
-- ============================================================

-- Mecânica
local driftActive        = false
local lastVehicle        = 0
local driftCap           = false   -- cache do State Bag drift; relido quando veh muda
local powerMult          = 1.2
local boostActive        = false
local boostStartTime     = 0
local lastBoostEnd       = 0
local lastHealth         = 0
local lastTick           = 0
local smokeVehicle       = 0
local smokeWasOn         = nil
local smokeHandles       = {}
local smokePtfxReady     = false
local smokePtfxRequested = false
local smokeFxAttempted   = false

-- Pontuação (consumida pelo vhub_racha via driftTelemetry)
local totalEarned  = 0.0
local crashCount   = 0
local driftTimeMs  = 0
local breakMs      = 0
local combo        = 1.0
local currentAngle = 0.0
local currentSpeed = 0.0
local isScoring    = false


-- ============================================================
-- EXPORTS — telemetria + triggers de install/remove
-- ============================================================

-- snapshot read-only; quem banca a pontuação valida é o vhub_racha
exports('driftTelemetry', function()
  return {
    total    = totalEarned,
    crashes  = crashCount,
    combo    = combo,
    angle    = currentAngle,
    speed    = currentSpeed,
    drifting = isScoring,
    active   = driftActive,
  }
end)

-- triggers server-side via oficina (leaseId+requestId fornecidos pelo client/oficina.lua)
exports('installDrift', function(leaseId, requestId)
  TriggerServerEvent(VHubCustom.E.DRIFT_INSTALL, leaseId, requestId)
end)

exports('removeDrift', function(leaseId, requestId)
  TriggerServerEvent(VHubCustom.E.DRIFT_REMOVE, leaseId, requestId)
end)


-- ============================================================
-- HELPERS
-- ============================================================

local function comboFor(ms)
  local secs = ms / 1000.0
  local mult = 1.0
  for i = 1, #COMBO_THRESHOLDS do
    if secs >= COMBO_THRESHOLDS[i] then mult = COMBO_MULT[i] end
  end
  return mult
end

local function getDriftAngle(veh)
  local vel   = GetEntityVelocity(veh)
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
  for i = 1, #smokeHandles do StopParticleFxLooped(smokeHandles[i], false) end
  smokeHandles   = {}
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
    SetVehicleHandlingFloat(veh, "CHandlingData", v[1], cur + (v[2] * m))
  end
end

local function revertDrift(veh)
  if driftActive and veh ~= 0 and DoesEntityExist(veh) then
    setHandling(veh, false)
    SetVehicleEnginePowerMultiplier(veh, 1.0)
  end
  stopDriftSmoke()
  driftActive = false
  boostActive = false
end

-- F-058 (ADR #48): restart do resource restaura o handling do carro em drift
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

local function resetCombo()
  driftTimeMs = 0
  breakMs     = 0
  combo       = 1.0
  isScoring   = false
end


-- ============================================================
-- MAIN LOOP — mecânica + fabricação de pontuação
-- ============================================================

CreateThread(function()
  while VHubCustom.running do
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and CLASS_WHITELIST[GetVehicleClass(veh)] then

      -- ── Gate de capability (cache por handle) ─────────────────────────────────
      -- lido ANTES de qualquer native de física (desempenho + segurança)
      if veh ~= lastVehicle then
        revertDrift(lastVehicle)
        lastVehicle  = veh
        driftCap     = Entity(veh).state[VHubCustom.BAG.DRIFT] == true
        lastHealth   = GetVehicleBodyHealth(veh)
        lastTick     = GetGameTimer()
        boostActive  = false
        lastBoostEnd = 0
        resetCombo()
      end

      if not driftCap then
        Wait(500)
        goto continue
      end

      -- ── A partir daqui: veículo tem Freio de Mão Hidráulico ───────────────────

      local speedKMH = GetEntitySpeed(veh) * 3.6
      local timeNow  = GetGameTimer()
      local dt       = timeNow - lastTick
      if dt < 0 then dt = 0 end
      lastTick     = timeNow
      currentSpeed = speedKMH

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

        -- ── Mecânica: handling + boost ───────────────────────────────────────────
        local driftReady = speedKMH > DRIFT_MIN_SPEED and currentAngle > DRIFT_MIN_ANGLE
        local driftInput = isAccelerating and isHandbraking and IsVehicleOnAllWheels(veh)

        if driftInput and driftReady then
          DisableControlAction(0, 76, true)
          if not driftActive then
            activateDrift(veh)
          else
            startDriftSmoke(veh)
          end

          if not boostActive
            and (timeNow - lastBoostEnd) > BOOST_COOLDOWN
            and speedKMH > DRIFT_MIN_SPEED
            and currentAngle > MIN_BOOST_ANGLE then
            boostActive    = true
            boostStartTime = timeNow
          end

          if boostActive then
            if (timeNow - boostStartTime) >= BOOST_DURATION then
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
          if boostActive then
            boostActive  = false
            lastBoostEnd = timeNow
          end
          if driftActive then revertDrift(veh) end
        end

        -- ── Fabricação de pontuação bruta ────────────────────────────────────────
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
        driftCap    = false
        boostActive = false
        resetCombo()
      end
      Wait(1000)
      lastTick = GetGameTimer()
    end

    ::continue::
  end
end)
