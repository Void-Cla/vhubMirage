-- client/defaults.lua — opções built-in: portas/capô/porta-malas de veículo
-- Gated por cfg.defaults. Abrir porta de veículo do qual NÃO se é network owner
-- passa pelo servidor (validado lá: tipo, porta, proximidade, rate).
---@diagnostic disable: undefined-global, lowercase-global

if not VHubTarget.cfg.defaults then return end

local api = VHubTarget.api
local lang = VHubTarget.lang
local cache = VHubTarget.cache
local E = VHubTarget.E

local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetEntityBonePosition_2 = GetEntityBonePosition_2
local GetVehicleDoorLockStatus = GetVehicleDoorLockStatus

local bones = {
  [0] = 'dside_f',
  [1] = 'pside_f',
  [2] = 'dside_r',
  [3] = 'pside_r'
}

-- abre/fecha a porta localmente (só quando destrancada)
local function toggleDoor(vehicle, door)
  if GetVehicleDoorLockStatus(vehicle) ~= 2 then
    if GetVehicleDoorAngleRatio(vehicle, door) > 0.0 then
      SetVehicleDoorShut(vehicle, door, false)
    else
      SetVehicleDoorOpen(vehicle, door, false, false)
    end
  end
end

-- decide se a opção de porta aparece (porta válida, destrancada, íntegra, player a pé)
local function canInteractWithDoor(entity, coords, door, useOffset)
  if not GetIsDoorValid(entity, door) or GetVehicleDoorLockStatus(entity) > 1
    or IsVehicleDoorDamaged(entity, door) or cache.vehicle then return end

  if useOffset then return true end

  local boneName = bones[door]

  if not boneName then return false end

  local boneId = GetEntityBoneIndexByName(entity, 'door_' .. boneName)

  if boneId ~= -1 then
    return #(coords - GetEntityBonePosition_2(entity, boneId)) < 0.5 or
      #(coords - GetEntityBonePosition_2(entity, GetEntityBoneIndexByName(entity, 'seat_' .. boneName))) < 0.72
  end
end

-- executa a abertura: local se somos net owner; senão pede ao servidor
local function onSelectDoor(data, door)
  local entity = data.entity

  if NetworkGetEntityOwner(entity) == cache.playerId then
    return toggleDoor(entity, door)
  end

  TriggerServerEvent(E.TOGGLE_ENTITY_DOOR, VehToNet(entity), door)
end

RegisterNetEvent(E.TOGGLE_ENTITY_DOOR, function(netId, door)
  local entity = NetToVeh(netId)
  toggleDoor(entity, door)
end)

api.addGlobalVehicle({
  {
    name = 'vhub_target:driverF',
    icon = 'car',
    label = lang.toggle_front_driver_door,
    bones = { 'door_dside_f', 'seat_dside_f' },
    distance = 2,
    canInteract = function(entity, distance, coords)
      return canInteractWithDoor(entity, coords, 0)
    end,
    onSelect = function(data)
      onSelectDoor(data, 0)
    end
  },
  {
    name = 'vhub_target:passengerF',
    icon = 'car',
    label = lang.toggle_front_passenger_door,
    bones = { 'door_pside_f', 'seat_pside_f' },
    distance = 2,
    canInteract = function(entity, distance, coords)
      return canInteractWithDoor(entity, coords, 1)
    end,
    onSelect = function(data)
      onSelectDoor(data, 1)
    end
  },
  {
    name = 'vhub_target:driverR',
    icon = 'car',
    label = lang.toggle_rear_driver_door,
    bones = { 'door_dside_r', 'seat_dside_r' },
    distance = 2,
    canInteract = function(entity, distance, coords)
      return canInteractWithDoor(entity, coords, 2)
    end,
    onSelect = function(data)
      onSelectDoor(data, 2)
    end
  },
  {
    name = 'vhub_target:passengerR',
    icon = 'car',
    label = lang.toggle_rear_passenger_door,
    bones = { 'door_pside_r', 'seat_pside_r' },
    distance = 2,
    canInteract = function(entity, distance, coords)
      return canInteractWithDoor(entity, coords, 3)
    end,
    onSelect = function(data)
      onSelectDoor(data, 3)
    end
  },
  {
    name = 'vhub_target:bonnet',
    icon = 'car',
    label = lang.toggle_hood,
    offset = vec3(0.5, 1, 0.5),
    distance = 2,
    canInteract = function(entity, distance, coords)
      return canInteractWithDoor(entity, coords, 4, true)
    end,
    onSelect = function(data)
      onSelectDoor(data, 4)
    end
  },
  {
    name = 'vhub_target:trunk',
    icon = 'car',
    label = lang.toggle_trunk,
    offset = vec3(0.5, 0, 0.5),
    distance = 2,
    canInteract = function(entity, distance, coords)
      return canInteractWithDoor(entity, coords, 5, true)
    end,
    onSelect = function(data)
      onSelectDoor(data, 5)
    end
  }
})
