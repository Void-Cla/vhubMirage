-- client/vehicle.lua — leitura de State Bags e report de intenção do veículo (PT-BR)
-- Responsabilidade: reportar estado do veículo (fuel, rpm, health) ao servidor (adaptive 0.5–4Hz)

local REPORT_MS = 250 -- valor inicial; o loop adapta por velocidade/rpm

-- Cadência adaptativa: parado=2000ms (0.5Hz), idle=1000ms (1Hz), dirigindo=250ms (4Hz)
local function adaptiveDelay(speed_kmh, rpm)
  if speed_kmh < 1 then return 2000 end
  if rpm < 0.2 then return 1000 end
  return 250
end

RegisterNetEvent("vHub:vehicleStateLoad")
AddEventHandler("vHub:vehicleStateLoad", function(plate, state)
  -- Aplica estado recebido do servidor ao veículo local se o jogador estiver no mesmo veículo
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if veh and veh ~= 0 then
    local myplate = GetVehicleNumberPlateText(veh) or ""
    if myplate == plate then
      if state.fuel and SetVehicleFuelLevel then pcall(SetVehicleFuelLevel, veh, state.fuel) end
      if state.engine_health then pcall(SetVehicleEngineHealth, veh, state.engine_health) end
      if state.body_health and SetVehicleBodyHealth then pcall(SetVehicleBodyHealth, veh, state.body_health) end
    end
  end
end)

Citizen.CreateThread(function()
  local period_ms = REPORT_MS
  while true do
    Citizen.Wait(period_ms)
    local ped = PlayerPedId()
    if not ped then goto continue end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then
      local driver = GetPedInVehicleSeat(veh, -1)
      local seat = -2
      if driver == ped then seat = -1 else
        -- descobrir índice do assento aproximado (não crítico para reporte)
        seat = -2
      end

      local plate = GetVehicleNumberPlateText(veh) or ""
      local rpm = (GetVehicleCurrentRpm and GetVehicleCurrentRpm(veh)) or 0
      local engine_health = (GetVehicleEngineHealth and GetVehicleEngineHealth(veh)) or 0
      local body_health = (GetVehicleBodyHealth and GetVehicleBodyHealth(veh)) or 0
      local engine_on = (GetIsVehicleEngineRunning and GetIsVehicleEngineRunning(veh)) or false

      -- Calcular delta de odômetro (km) baseado na velocidade e período atual
      local speed_ms = (GetEntitySpeed and GetEntitySpeed(veh)) or 0
      local speed_kmh = speed_ms * 3.6
      local delta_km = speed_kmh * (period_ms / 1000) / 3600

      local payload = {
        rpm = rpm,
        engine_health = engine_health,
        body_health = body_health,
        engine_on = engine_on,
        odometer_delta = delta_km,
      }

      -- Enviar apenas se for driver: somente o motorista tem autoridade para reportar intent
      if seat == -1 then
        TriggerServerEvent("vHub:vState", plate, payload)
      end

      -- Cadência adaptativa: parado=2s, idle=1s, dirigindo=250ms
      period_ms = adaptiveDelay(speed_kmh, rpm)
    else
      -- Fora de veículo: cadência mínima 1s (não há nada para reportar)
      period_ms = 1000
    end
    ::continue::
  end
end)
