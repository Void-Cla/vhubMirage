-- client/vehicle.lua — emissor de intenção de veículo (enter/leave/state) + State Bags
-- Responsabilidade: reportar ao servidor a relação FÍSICA do ped com o veículo
-- (assento e telemetria). O servidor valida tudo contra a réplica (ADR #37).
-- Gate global: só emite quando GlobalState.vh_core_active == true (kill-switch, F-019).

local REPORT_MS   = 250    -- valor inicial; o loop adapta por velocidade/rpm
local REAFFIRM_MS = 30000  -- reafirma vEnter (idempotente) para curar desync de réplica


-- ============================================================
-- HELPERS
-- ============================================================

-- Cadência adaptativa: parado=2000ms (0.5Hz), idle=1000ms (1Hz), dirigindo=250ms (4Hz)
local function adaptiveDelay(speed_kmh, rpm)
  if speed_kmh < 1 then return 2000 end
  if rpm < 0.2 then return 1000 end
  return 250
end

-- Normaliza placa para comparação — espelha a normalizePlate do servidor
-- (upper + colapsa espaços + trim). GetVehicleNumberPlateText devolve a placa
-- com PADDING de espaços (8 chars) e o servidor manda a placa normalizada.
local function plateKey(p)
  local s = tostring(p or ""):upper():gsub("%s+", " ")
  return s:match("^%s*(.-)%s*$") or ""
end

-- Descobre o assento real do ped no veículo (-1 = motorista; nil = não está)
local function assentoAtual(veh, ped)
  if GetPedInVehicleSeat(veh, -1) == ped then return -1 end
  local max = GetVehicleMaxNumberOfPassengers(veh)
  for i = 0, max - 1 do
    if GetPedInVehicleSeat(veh, i) == ped then return i end
  end
  return nil
end

-- true quando o CORE está com o pipeline de veículo armado (server escreve o gate)
local function coreAtivo()
  return GlobalState.vh_core_active == true
end

-- Aplica a réplica autoritativa de fuel somente no controlador da entidade.
local function applyFuelBag(vehicle, value)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
  if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return end
  if not NetworkHasControlOfEntity(vehicle) then return end

  local fuel = math.max(0.0, math.min(100.0, value)) + 0.0
  if math.abs(GetVehicleFuelLevel(vehicle) - fuel) >= 0.05 then
    SetVehicleFuelLevel(vehicle, fuel)
  end
  local empty = fuel <= 0.01
  SetVehicleUndriveable(vehicle, empty)
  if empty and GetIsVehicleEngineRunning(vehicle) then
    SetVehicleEngineOn(vehicle, false, true, true)
  end
end


-- ============================================================
-- HANDLERS (servidor → cliente)
-- ============================================================

RegisterNetEvent("vHub:vehicleStateLoad")
AddEventHandler("vHub:vehicleStateLoad", function(plate, state)
  -- Aplica estado recebido do servidor ao veículo local se o jogador estiver no mesmo veículo
  -- HOTFIX 2026-06-11: sem normalizar os dois lados a comparação NUNCA casava e o
  -- fuel/engine/body salvos jamais eram aplicados (fuel "preso" no default nativo 65).
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if veh and veh ~= 0 and DoesEntityExist(veh) and type(state) == "table" then
    local myplate = GetVehicleNumberPlateText(veh) or ""
    if plateKey(myplate) == plateKey(plate) then
      if state.fuel and SetVehicleFuelLevel then pcall(SetVehicleFuelLevel, veh, state.fuel) end
      if state.engine_health then pcall(SetVehicleEngineHealth, veh, state.engine_health) end
      if state.body_health and SetVehicleBodyHealth then pcall(SetVehicleBodyHealth, veh, state.body_health) end
    end
  end
end)

-- F-007 (ADR #37): modo passageiro agora tem handler — reencaminha como evento local
-- para consumidores (HUD/UX) sem acoplar o CORE a nenhuma UI.
RegisterNetEvent("vHub:passengerMode")
AddEventHandler("vHub:passengerMode", function(plate, isPassenger)
  TriggerEvent("vHub:localPassengerMode", plate, isPassenger == true)
end)

AddStateBagChangeHandler("vh_fuel", nil, function(bagName, _, value)
  applyFuelBag(GetEntityFromStateBagName(bagName), value)
end)


-- ============================================================
-- LOOP ÚNICO — transição de assento + telemetria (budget: 0.5–4Hz)
-- ============================================================

Citizen.CreateThread(function()
  local period_ms = REPORT_MS
  -- relação corrente validada localmente; espelho do que foi anunciado ao servidor
  local atual = { veh = 0, placa = nil, netid = nil, assento = nil, anunciado_ms = 0 }
  -- candidato de assento aguardando estabilidade (2 passadas ≈ réplica propagada)
  local candidato = { veh = 0, assento = nil }

  local function anunciarSaida()
    if atual.veh ~= 0 and atual.placa then
      TriggerServerEvent("vHub:vLeave", atual.placa, atual.assento)
    end
    atual.veh, atual.placa, atual.netid, atual.assento = 0, nil, nil, nil
    atual.anunciado_ms = 0
  end

  while true do
    Citizen.Wait(period_ms)
    local ped = PlayerPedId()
    if not ped then goto continue end

    -- Kill-switch do CORE: sem pipeline armado, nada é emitido (F-019)
    if not coreAtivo() then
      atual.veh, atual.placa, atual.netid, atual.assento = 0, nil, nil, nil
      candidato.veh, candidato.assento = 0, nil
      period_ms = 2000
      goto continue
    end

    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
      local assento = assentoAtual(veh, ped)
      local agora   = GetGameTimer()

      -- ── Transição de assento/veículo (estável por 2 passadas antes de anunciar —
      --    dá tempo da réplica server-side refletir o ped no assento) ──
      if veh ~= atual.veh or assento ~= atual.assento then
        if candidato.veh == veh and candidato.assento == assento and assento ~= nil then
          if NetworkGetEntityIsNetworked(veh) then
            if atual.veh ~= 0 then anunciarSaida() end
            atual.veh     = veh
            atual.placa   = plateKey(GetVehicleNumberPlateText(veh) or "")
            atual.netid   = NetworkGetNetworkIdFromEntity(veh)
            atual.assento = assento
            atual.anunciado_ms = agora
            TriggerServerEvent("vHub:vEnter", atual.placa, atual.netid, atual.assento)
          end
          candidato.veh, candidato.assento = 0, nil
        else
          candidato.veh, candidato.assento = veh, assento
        end
      elseif atual.veh ~= 0 and (agora - atual.anunciado_ms) >= REAFFIRM_MS then
        -- Reafirmação idempotente (R14): cura vEnter perdido por lag de réplica
        atual.anunciado_ms = agora
        TriggerServerEvent("vHub:vEnter", atual.placa, atual.netid, atual.assento)
      end

      -- ── Telemetria — somente o motorista tem autoridade de report ──
      local rpm       = (GetVehicleCurrentRpm and GetVehicleCurrentRpm(veh)) or 0
      local speed_ms  = (GetEntitySpeed and GetEntitySpeed(veh)) or 0
      local speed_kmh = speed_ms * 3.6

      if atual.veh == veh and atual.assento == -1 then
        applyFuelBag(veh, Entity(veh).state.vh_fuel)
        TriggerServerEvent("vHub:vState", atual.placa, {
          rpm            = rpm,
          engine_health  = (GetVehicleEngineHealth and GetVehicleEngineHealth(veh)) or 0,
          body_health    = (GetVehicleBodyHealth and GetVehicleBodyHealth(veh)) or 0,
          engine_on      = (GetIsVehicleEngineRunning and GetIsVehicleEngineRunning(veh)) or false,
          odometer_delta = speed_kmh * (period_ms / 1000) / 3600,
        })
      end

      period_ms = adaptiveDelay(speed_kmh, rpm)
    else
      -- Fora de veículo: anuncia saída pendente e reduz cadência
      if atual.veh ~= 0 then anunciarSaida() end
      candidato.veh, candidato.assento = 0, nil
      period_ms = 1000
    end
    ::continue::
  end
end)
