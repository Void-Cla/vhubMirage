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
    local c = GetEntityCoords(ped)
    local veh = CreateVehicle(hash, c.x, c.y + 4.0, c.z, GetEntityHeading(ped), true, false)
    SetVehicleOnGroundProperly(veh)
    SetPedIntoVehicle(ped, veh, -1)
    SetModelAsNoLongerNeeded(hash)
    VHubAdmin.notify('Ve culo ' .. model .. ' spawnado.')
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
    VHubAdmin.notify('Ve culo deletado.')
  else VHubAdmin.notify('Nenhum ve culo pr ximo.') end
end)

RegisterNetEvent(E.DO_FIX)
AddEventHandler(E.DO_FIX, function()
  local veh = nearestVehicle(8.0)
  if not veh or veh == 0 then VHubAdmin.notify('Sem ve culo.'); return end
  SetVehicleFixed(veh)
  SetVehicleDeformationFixed(veh)
  SetVehicleEngineHealth(veh, 1000.0)
  SetVehicleBodyHealth(veh, 1000.0)
  SetVehiclePetrolTankHealth(veh, 1000.0)
  SetVehicleDirtLevel(veh, 0.0)
  VHubAdmin.notify('Ve culo reparado.')
end)

RegisterNetEvent(E.DO_TUNING)
AddEventHandler(E.DO_TUNING, function()
  local veh = nearestVehicle(8.0)
  if not veh or veh == 0 then VHubAdmin.notify('Sem ve culo.'); return end
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
  if not veh or veh == 0 then VHubAdmin.notify('Sem ve culo.'); return end
  SetVehicleCustomPrimaryColour(veh, r, g, b)
  SetVehicleCustomSecondaryColour(veh, r, g, b)
  VHubAdmin.notify(('Cor RGB %d,%d,%d.'):format(r, g, b))
end)

-- comandos
RegisterCommand('car', function(_, args)
  if not isAdm() then return end
  TriggerServerEvent(E.ACT_SPAWNCAR, (args[1] or 'adder'):lower())
end, false)

RegisterCommand('dv', function() if isAdm() then TriggerServerEvent(E.ACT_DELVEH) end end, false)
RegisterCommand('fix', function() if isAdm() then TriggerServerEvent(E.ACT_FIX) end end, false)
RegisterCommand('tuning', function() if isAdm() then TriggerServerEvent(E.ACT_TUNING) end end, false)

RegisterCommand('carcolor', function(_, args)
  if not isAdm() then return end
  local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  if r and g and b then TriggerServerEvent(E.ACT_CARCOLOR, r, g, b)
  else VHubAdmin.notify('Uso: /carcolor <r> <g> <b>') end
end, false)
