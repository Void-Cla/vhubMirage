-- client/vehicle.lua  spawn/del/fix/tuning/carcolor
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

local function isAdm() return S.is_admin end

local function nearestVehicle(radius)
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return GetVehiclePedIsIn(ped, false) end
  local c = GetEntityCoords(ped)
  return GetClosestVehicle(c.x, c.y, c.z, radius or 8.0, 0, 71)
end

local function loadModel(name)
  local hash = GetHashKey(name)
  if not IsModelInCdimage(hash) then return nil end
  RequestModel(hash)
  local t = 0
  while not HasModelLoaded(hash) and t < 5000 do Citizen.Wait(50); t = t + 50 end
  return HasModelLoaded(hash) and hash or nil
end

RegisterNetEvent(E.DO_SPAWNCAR)
AddEventHandler(E.DO_SPAWNCAR, function(model)
  Citizen.CreateThread(function()
    local hash = loadModel(model)
    if not hash then VHubAdmin.notify('Modelo inv lido.'); return end
    local ped = PlayerPedId()
    -- spawna à frente do ped (forward vector), não em offset fixo de mundo
    local spawn = GetEntityCoords(ped) + GetEntityForwardVector(ped) * 3.0
    local veh = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, GetEntityHeading(ped), true, false)
    SetVehicleOnGroundProperly(veh)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetPedIntoVehicle(ped, veh, -1)
    SetModelAsNoLongerNeeded(hash)
    VHubAdmin.notify('Veículo ' .. model .. ' spawnado.')
  end)
end)

RegisterNetEvent(E.DO_DELVEH)
AddEventHandler(E.DO_DELVEH, function()
  local veh = nearestVehicle(8.0)
  if veh and veh ~= 0 then
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == veh then
      TaskLeaveVehicle(ped, veh, 4096); Citizen.Wait(700)
    end
    SetEntityAsMissionEntity(veh, false, true)
    DeleteVehicle(veh)
    VHubAdmin.notify('Veículo deletado.')
  else VHubAdmin.notify('Nenhum veículo próximo.') end
end)

RegisterNetEvent(E.DO_FIX)
AddEventHandler(E.DO_FIX, function()
  local veh = nearestVehicle(8.0)
  if not veh or veh == 0 then VHubAdmin.notify('Sem veículo.'); return end
  SetVehicleFixed(veh)
  SetVehicleDeformationFixed(veh)
  SetVehicleUndriveable(veh, false)
  SetVehicleEngineHealth(veh, 1000.0)
  SetVehicleBodyHealth(veh, 1000.0)
  SetVehiclePetrolTankHealth(veh, 1000.0)
  SetVehicleDirtLevel(veh, 0.0)
  if GetVehiclePedIsIn(PlayerPedId(), false) == veh then
    SetVehicleEngineOn(veh, true, true, false)
  end
  VHubAdmin.notify('Veículo reparado.')
end)

-- ----------------------------------------------------------------------------
-- BOOST tempor rio (par metros v m do server; auto-restaura ao expirar)
-- ----------------------------------------------------------------------------
local _boost_active = false

RegisterNetEvent(E.DO_BOOST)
AddEventHandler(E.DO_BOOST, function(mult, duration_ms)
  local ped = PlayerPedId()
  local veh = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
  if veh == 0 then VHubAdmin.notify('Você não está em um veículo.'); return end
  if _boost_active then VHubAdmin.notify('Boost j  ativo.'); return end

  _boost_active = true
  ModifyVehicleTopSpeed(veh, mult)
  SetVehicleEnginePowerMultiplier(veh, mult * 15.0)
  SetVehicleEngineTorqueMultiplier(veh, mult)
  VHubAdmin.notify(('Boost %.1fx por %ds.'):format(mult, math.floor(duration_ms / 1000)))

  SetTimeout(duration_ms, function()
    if DoesEntityExist(veh) then
      ModifyVehicleTopSpeed(veh, 1.0)
      SetVehicleEnginePowerMultiplier(veh, 1.0)
      SetVehicleEngineTorqueMultiplier(veh, 1.0)
    end
    _boost_active = false
    VHubAdmin.notify('Boost encerrado.')
  end)
end)

-- ----------------------------------------------------------------------------
-- FLIP  desvira o veículo mais próximo (ou o atual)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.DO_FLIP)
AddEventHandler(E.DO_FLIP, function()
  local veh = nearestVehicle(8.0)
  if not veh or veh == 0 then VHubAdmin.notify('Sem veículo.'); return end
  local c = GetEntityCoords(veh)
  SetEntityRotation(veh, 0.0, 0.0, GetEntityHeading(veh), 2, true)
  SetEntityCoords(veh, c.x, c.y, c.z + 0.6, false, false, false, false)
  SetVehicleOnGroundProperly(veh)
  VHubAdmin.notify('Veículo desvirado.')
end)

RegisterNetEvent(E.DO_TUNING)
AddEventHandler(E.DO_TUNING, function()
  local veh = nearestVehicle(8.0)
  if not veh or veh == 0 then VHubAdmin.notify('Sem veículo.'); return end
  SetVehicleModKit(veh, 0)
  for i = 0, 49 do
    local n = GetNumVehicleMods(veh, i)
    if n > 0 then SetVehicleMod(veh, i, n - 1, false) end
  end
  ToggleVehicleMod(veh, 18, true)
  SetVehicleWheelType(veh, 7)
  VHubAdmin.notify('Tuning aplicado.')
end)

RegisterNetEvent(E.DO_CARCOLOR)
AddEventHandler(E.DO_CARCOLOR, function(r, g, b)
  local veh = nearestVehicle(8.0)
  if not veh or veh == 0 then VHubAdmin.notify('Sem veículo.'); return end
  SetVehicleCustomPrimaryColour(veh, r, g, b)
  SetVehicleCustomSecondaryColour(veh, r, g, b)
  VHubAdmin.notify(('Cor RGB %d,%d,%d.'):format(r, g, b))
end)

-- comandos
RegisterCommand('car', function(_, args)
  if not isAdm() then return end
  TriggerServerEvent(E.ACT_SPAWNCAR, (args[1] or 'adder'):lower())
end, false)

RegisterCommand('dv', function() if isAdm() then TriggerServerEvent(E.ACT_DELVEH) end  end, false)
RegisterCommand('fix', function() if isAdm() then TriggerServerEvent(E.ACT_FIX) end end, false)
RegisterCommand('tuning', function() if isAdm() then TriggerServerEvent(E.ACT_TUNING) end end, false)
RegisterCommand('boost', function() if isAdm() then TriggerServerEvent(E.ACT_BOOST) end end, false)
RegisterCommand('flip', function() if isAdm() then TriggerServerEvent(E.ACT_FLIP) end end, false)

RegisterCommand('carcolor', function(_, args)
  if not isAdm() then return end
  local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  if r and g and b then TriggerServerEvent(E.ACT_CARCOLOR, r, g, b)
  else VHubAdmin.notify('Uso: /carcolor <r> <g> <b>') end
end, false)
