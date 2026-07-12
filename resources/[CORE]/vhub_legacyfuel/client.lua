-- client.lua — interação e efeitos locais do abastecimento

local C = VHubFuel.Config
local E = VHubFuel.E

local carryVisual
local remoteVisuals = {}
local remoteTokens = {}
local remotePending = {}
local remoteEnded = {}
local blips = {}
local localActive = false
local localGeneration
local localVehicle
local localProgress
local pendingFuel
local fuelWorker = false

local REFUEL_ANIM_DICT = 'weapons@misc@jerrycan@'
local REFUEL_ANIM_CLIP = 'fire'


-- ============================================================
-- ASSET / VISUAL LIFECYCLE
-- ============================================================

local function requestModel(model, timeoutMs)
  RequestModel(model)
  local deadline = GetGameTimer() + timeoutMs
  while not HasModelLoaded(model) and GetGameTimer() < deadline do Citizen.Wait(25) end
  return HasModelLoaded(model)
end

local function requestAnimDict(dict, timeoutMs)
  RequestAnimDict(dict)
  local deadline = GetGameTimer() + timeoutMs
  while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Citizen.Wait(25) end
  return HasAnimDictLoaded(dict)
end

local function deleteVisual(visual)
  if not visual then return end
  if visual.rope and DoesRopeExist(visual.rope) then DeleteRope(visual.rope) end
  if visual.prop and DoesEntityExist(visual.prop) then
    DetachEntity(visual.prop, true, true)
    DeleteEntity(visual.prop)
  end
  if visual.anchor and DoesEntityExist(visual.anchor) then DeleteEntity(visual.anchor) end
end

local function loadRopeTextures(timeoutMs)
  RopeLoadTextures()
  local deadline = GetGameTimer() + timeoutMs
  while not RopeAreTexturesLoaded() and GetGameTimer() < deadline do Citizen.Wait(25) end
  return RopeAreTexturesLoaded()
end

local function findPump(payload)
  if type(payload) ~= 'table' then return nil end
  local model = tonumber(payload.model)
  local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
  if not C.PumpModels[model] or not x or not y or not z then return nil end
  local pump = GetClosestObjectOfType(x, y, z, 2.0, model, false, false, false)
  return pump ~= 0 and pump or nil
end

local function capWorldCoords(vehicle)
  local names = { 'petrolcap', 'petroltank', 'petroltank_l', 'wheel_lr', 'engine', 'engine_l' }
  local offset = C.FuelCaps[GetEntityModel(vehicle)] or vec3(0.0, 0.0, 0.65)
  for index = 1, #names do
    local bone = GetEntityBoneIndexByName(vehicle, names[index])
    if bone ~= -1 then
      local world = GetWorldPositionOfEntityBone(vehicle, bone)
      local localOffset = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
      return GetOffsetFromEntityInWorldCoords(vehicle,
        localOffset.x + offset.x, localOffset.y + offset.y, localOffset.z + offset.z)
    end
  end
  return GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
end

local function attachNozzleToHand(prop, ped)
  local hand = C.NozzleHand
  AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, hand.bone),
    hand.offset.x, hand.offset.y, hand.offset.z,
    hand.rotation.x, hand.rotation.y, hand.rotation.z,
    true, true, false, false, 0, true)
end

local function attachNozzleToCap(prop, vehicle)
  local cap = capWorldCoords(vehicle)
  local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, cap.x, cap.y, cap.z)
  local rotation = C.NozzleCapRotation
  DetachEntity(prop, true, true)
  AttachEntityToEntity(prop, vehicle, 0, offset.x, offset.y, offset.z,
    rotation.x, rotation.y, rotation.z, true, true, false, false, 0, true)
end

local function createHose(prop, pump)
  local cfg = C.PumpModels[GetEntityModel(pump)] or { z = 1.8 }
  local pumpCoords = GetEntityCoords(pump)
  local pumpAnchor = vec3(pumpCoords.x, pumpCoords.y, pumpCoords.z + cfg.z)
  local anchor = CreateObjectNoOffset(C.NozzleModel,
    pumpAnchor.x, pumpAnchor.y, pumpAnchor.z, false, false, false)
  if not anchor or anchor == 0 then return nil end
  SetEntityVisible(anchor, false, false)
  SetEntityCollision(anchor, false, false)
  FreezeEntityPosition(anchor, true)

  local rope = AddRope(pumpAnchor.x, pumpAnchor.y, pumpAnchor.z,
    0.0, 0.0, 0.0, C.RopeMaxLength, C.RopeType, C.RopeLength, 0.5, 1.0,
    false, false, false, 1.0, false, 0)
  if not rope or rope == 0 or not DoesRopeExist(rope) then
    DeleteEntity(anchor)
    return nil
  end

  local tip = C.NozzleTipOffset
  local nozzleAnchor = GetOffsetFromEntityInWorldCoords(prop, tip.x, tip.y, tip.z)
  local hoseLength = math.min(C.RopeMaxLength,
    math.max(C.RopeLength, #(pumpAnchor - nozzleAnchor) + 0.5))
  AttachEntitiesToRope(rope, prop, anchor,
    nozzleAnchor.x, nozzleAnchor.y, nozzleAnchor.z,
    pumpAnchor.x, pumpAnchor.y, pumpAnchor.z,
    hoseLength, false, false, 0, 0)
  RopeForceLength(rope, hoseLength)
  return rope, anchor
end

local function createPumpVisual(vehicle, pump)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
  if not pump or pump == 0 or not DoesEntityExist(pump) then return nil end
  if not requestModel(C.NozzleModel, 3000) or not loadRopeTextures(3000) then return nil end

  local prop = CreateObjectNoOffset(C.NozzleModel, 0.0, 0.0, 0.0, false, false, false)
  if not prop or prop == 0 then return nil end
  attachNozzleToCap(prop, vehicle)
  local rope, anchor = createHose(prop, pump)
  if not rope then DeleteEntity(prop); return nil end
  SetModelAsNoLongerNeeded(C.NozzleModel)
  return { prop = prop, rope = rope, anchor = anchor, pump = pump }
end

local function createCanVisual(serverId)
  local player = GetPlayerFromServerId(serverId)
  if player == -1 or not requestModel(C.JerryCanModel, 3000) then return nil end
  local ped = GetPlayerPed(player)
  if not ped or ped == 0 then return nil end
  local prop = CreateObjectNoOffset(C.JerryCanModel, 0.0, 0.0, 0.0, false, false, false)
  if not prop or prop == 0 then return nil end
  AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005), 0.12, 0.0, -0.12,
    -80.0, 0.0, -20.0, false, false, false, false, 0, true)
  SetModelAsNoLongerNeeded(C.JerryCanModel)
  return { prop = prop }
end

local function promoteLocalCarry(serverId, payload)
  if serverId ~= GetPlayerServerId(PlayerId()) or payload.mode ~= 'pump' then return false end
  if not carryVisual or not DoesEntityExist(carryVisual.prop) then return false end
  local pump = carryVisual.pump
  local expected = payload.pump
  if not pump or type(expected) ~= 'table' then return false end
  if GetEntityModel(pump) ~= tonumber(expected.model) then return false end
  local coords = GetEntityCoords(pump)
  local expectedCoords = vec3(
    tonumber(expected.x) or 0.0, tonumber(expected.y) or 0.0, tonumber(expected.z) or 0.0)
  if #(coords - expectedCoords) > 2.0 then return false end

  local vehicle = NetToVeh(tonumber(payload.vehicle_net_id) or 0)
  if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
  attachNozzleToCap(carryVisual.prop, vehicle)
  carryVisual.generation = payload.generation
  remoteVisuals[serverId] = carryVisual
  carryVisual = nil
  return true
end

local function createRemoteVisual(serverId, payload)
  local generation = tonumber(payload.generation)
  if not generation or generation <= (remoteEnded[serverId] or 0) then return end
  if remoteTokens[serverId] and generation < remoteTokens[serverId] then return end
  remoteTokens[serverId] = generation
  local existing = remoteVisuals[serverId]
  if existing and existing.generation == payload.generation then return end
  if remotePending[serverId] == payload.generation then return end
  if existing then deleteVisual(existing); remoteVisuals[serverId] = nil end
  if promoteLocalCarry(serverId, payload) then return end
  if serverId == GetPlayerServerId(PlayerId()) and carryVisual then
    deleteVisual(carryVisual)
    carryVisual = nil
  end
  remotePending[serverId] = payload.generation

  Citizen.CreateThread(function()
    local deadline = GetGameTimer() + 5000
    local visual
    while GetGameTimer() < deadline and not visual do
      if remoteTokens[serverId] ~= payload.generation then
        if remotePending[serverId] == payload.generation then remotePending[serverId] = nil end
        return
      end
      if payload.mode == 'can' then
        visual = createCanVisual(serverId)
      else
        local vehicle = NetToVeh(tonumber(payload.vehicle_net_id) or 0)
        local pump = findPump(payload.pump)
        if vehicle ~= 0 and DoesEntityExist(vehicle) then
          visual = createPumpVisual(vehicle, pump)
        end
      end
      if not visual then Citizen.Wait(250) end
    end
    if visual then
      if remoteTokens[serverId] ~= payload.generation then
        deleteVisual(visual)
        if remotePending[serverId] == payload.generation then remotePending[serverId] = nil end
        return
      end
      visual.generation = payload.generation
      remoteVisuals[serverId] = visual
    end
    if remotePending[serverId] == payload.generation then remotePending[serverId] = nil end
  end)
end


-- ============================================================
-- LOCAL CARRY / INTERACTION
-- ============================================================

local function clearCarry()
  deleteVisual(carryVisual)
  carryVisual = nil
end

local function createCarry(pump)
  clearCarry()
  if not pump or pump == 0 or not DoesEntityExist(pump) then return end
  if not requestModel(C.NozzleModel, 3000) or not loadRopeTextures(3000) then return end

  local ped = PlayerPedId()
  local prop = CreateObjectNoOffset(C.NozzleModel, 0.0, 0.0, 0.0, false, false, false)
  if not prop or prop == 0 then return end
  attachNozzleToHand(prop, ped)
  local rope, anchor = createHose(prop, pump)
  if not rope then DeleteEntity(prop); return end
  carryVisual = { prop = prop, rope = rope, anchor = anchor, pump = pump }
  SetModelAsNoLongerNeeded(C.NozzleModel)

  Citizen.CreateThread(function()
    while carryVisual and carryVisual.pump == pump do
      Citizen.Wait(250)
      if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(pump)) > C.RopeMaxLength then
        clearCarry()
        TriggerEvent('vHub:notify', 'negado', 'Mangueira devolvida: distância excedida.')
      end
    end
  end)
end

local function startFuel(vehicle, mode)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
  if not NetworkGetEntityIsNetworked(vehicle) then return end
  local pumpPayload
  if mode == 'pump' then
    local pump = carryVisual and carryVisual.pump
    if not pump or not DoesEntityExist(pump) then return end
    local coords = GetEntityCoords(pump)
    pumpPayload = {
      model = GetEntityModel(pump),
      x = coords.x,
      y = coords.y,
      z = coords.z,
    }
  end
  TriggerServerEvent(E.START, VehToNet(vehicle), mode, pumpPayload)
end

local function playRefuelAnimation(vehicle, generation)
  local ped = PlayerPedId()
  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    local coords = capWorldCoords(vehicle)
    TaskTurnPedToFaceCoord(ped, coords.x, coords.y, coords.z, 450)
    Citizen.Wait(450)
  end

  if not localActive or localGeneration ~= generation then return end
  if requestAnimDict(REFUEL_ANIM_DICT, 3000)
      and localActive and localGeneration == generation then
    TaskPlayAnim(ped, REFUEL_ANIM_DICT, REFUEL_ANIM_CLIP, 2.0, 8.0,
      -1, 50, 0.0, false, false, false)
  end
end

local function stopRefuelAnimation()
  StopAnimTask(PlayerPedId(), REFUEL_ANIM_DICT, REFUEL_ANIM_CLIP, 2.0)
  RemoveAnimDict(REFUEL_ANIM_DICT)
end

local function setFuelIfControlled(vehicle, fuel)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
  if not NetworkHasControlOfEntity(vehicle) then return false end
  SetVehicleFuelLevel(vehicle, fuel + 0.0)
  SetVehicleUndriveable(vehicle, fuel <= 0.01)
  return true
end

local function reflectFuel(vehicle, fuel, generation)
  fuel = tonumber(fuel)
  if not fuel or fuel ~= fuel or math.abs(fuel) == math.huge then return end
  fuel = math.max(0.0, math.min(100.0, fuel))
  if setFuelIfControlled(vehicle, fuel) then return end

  pendingFuel = { vehicle = vehicle, fuel = fuel, generation = generation }
  if fuelWorker then return end
  fuelWorker = true
  Citizen.CreateThread(function()
    local deadline = GetGameTimer() + 1500
    while pendingFuel and GetGameTimer() < deadline do
      local item = pendingFuel
      if not localActive or item.generation ~= localGeneration then break end
      if DoesEntityExist(item.vehicle) then NetworkRequestControlOfEntity(item.vehicle) end
      if setFuelIfControlled(item.vehicle, item.fuel) then
        if pendingFuel == item then
          pendingFuel = nil
          break
        end
      end
      Citizen.Wait(50)
    end
    fuelWorker = false
  end)
end

local function drawText(text, x, y, scale, centered)
  SetTextFont(4)
  SetTextScale(scale, scale)
  SetTextColour(235, 222, 196, 255)
  SetTextCentre(centered == true)
  SetTextOutline()
  BeginTextCommandDisplayText('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(x, y)
end

local function drawProgress(progress)
  local fuel = math.max(0.0, math.min(100.0, tonumber(progress.fuel) or 0.0))
  local ratio = fuel / 100.0
  local width, left = 0.28, 0.36
  DrawRect(0.50, 0.885, width, 0.070, 12, 10, 7, 220)
  DrawRect(left + width * ratio * 0.5, 0.907, width * ratio, 0.010, 243, 181, 58, 235)

  local title = progress.electric and 'RECARGA' or 'ABASTECIMENTO'
  local detail = ('%s  %.1f%%  |  +%.1f%%'):format(
    title, fuel, tonumber(progress.dispensed) or 0.0)
  if progress.mode == 'pump' then
    detail = detail .. ('  |  $%d'):format(math.floor(tonumber(progress.cost) or 0))
  elseif progress.remaining then
    detail = detail .. ('  |  GALÃO %.1f%%'):format(
      math.max(0.0, tonumber(progress.remaining) or 0.0))
  end
  drawText(detail, 0.50, 0.855, 0.34, true)
  drawText('~INPUT_CONTEXT~ Encerrar', 0.50, 0.914, 0.28, true)
end

local function registerTargets()
  local models = {}
  for model in pairs(C.PumpModels) do models[#models + 1] = model end

  exports.vhub_target:addModel(models, {
    {
      name = 'vhub_fuel:nozzle', label = 'Retirar/devolver bico', icon = 'car', distance = 2.0,
      onSelect = function(data)
        if carryVisual then clearCarry() else createCarry(data.entity) end
      end,
    },
    {
      name = 'vhub_fuel:buy_can', label = 'Comprar galão', icon = 'cash', distance = 2.0,
      onSelect = function() TriggerServerEvent(E.BUY_CAN) end,
    },
  })

  exports.vhub_target:addGlobalVehicle({
    {
      name = 'vhub_fuel:mount', label = 'Conectar mangueira', icon = 'car', distance = 2.5,
      canInteract = function(entity)
        return carryVisual ~= nil and GetPedInVehicleSeat(entity, -1) == 0
      end,
      onSelect = function(data) startFuel(data.entity, 'pump') end,
    },
    {
      name = 'vhub_fuel:use_can', label = 'Usar galão', icon = 'cash', distance = 2.5,
      canInteract = function(entity)
        return not carryVisual and not localActive and GetPedInVehicleSeat(entity, -1) == 0
      end,
      onSelect = function(data) startFuel(data.entity, 'can') end,
    },
  })
end


-- ============================================================
-- STATE BAG / SESSION EVENTS
-- ============================================================

AddStateBagChangeHandler('vh_fuel_hose', nil, function(bagName, _, payload)
  local serverId = tonumber(bagName:match('^player:(%d+)$'))
  if not serverId then return end
  if type(payload) ~= 'table' then
    remoteEnded[serverId] = math.max(
      remoteEnded[serverId] or 0, tonumber(remoteTokens[serverId]) or 0)
    remoteTokens[serverId] = remoteEnded[serverId]
    remotePending[serverId] = nil
    deleteVisual(remoteVisuals[serverId])
    remoteVisuals[serverId] = nil
    return
  end
  if type(payload.generation) ~= 'number' or type(payload.vehicle_net_id) ~= 'number' then return end
  createRemoteVisual(serverId, payload)
end)

RegisterNetEvent(E.STARTED)
AddEventHandler(E.STARTED, function(payload)
  if type(payload) ~= 'table' then return end
  local netId = tonumber(payload.vehicle_net_id)
  local generation = tonumber(payload.generation)
  local fuel = tonumber(payload.fuel)
  if not netId or netId <= 0 or not generation or not fuel then return end
  localActive = true
  localGeneration = generation
  localVehicle = NetToVeh(netId)
  localProgress = {
    generation = generation,
    fuel = fuel,
    dispensed = tonumber(payload.dispensed) or 0.0,
    cost = tonumber(payload.cost) or 0,
    remaining = tonumber(payload.remaining),
    mode = payload.mode,
    electric = payload.electric == true,
  }
  createRemoteVisual(GetPlayerServerId(PlayerId()), payload)
  reflectFuel(localVehicle, fuel, generation)
  playRefuelAnimation(localVehicle, generation)

  Citizen.CreateThread(function()
    while localActive and localGeneration == generation do
      Citizen.Wait(0)
      if localProgress and localProgress.generation == generation then drawProgress(localProgress) end
      if IsControlJustReleased(0, C.ActionKey) then
        localActive = false
        TriggerServerEvent(E.STOP)
      end
    end
  end)
end)

RegisterNetEvent(E.PROGRESS)
AddEventHandler(E.PROGRESS, function(payload)
  if type(payload) ~= 'table' then return end
  local generation = tonumber(payload.generation)
  local fuel = tonumber(payload.fuel)
  if not localActive or generation ~= localGeneration or not fuel then return end
  if fuel ~= fuel or math.abs(fuel) == math.huge then return end

  localProgress = {
    generation = generation,
    fuel = math.max(0.0, math.min(100.0, fuel)),
    dispensed = math.max(0.0, tonumber(payload.dispensed) or 0.0),
    cost = math.max(0, tonumber(payload.cost) or 0),
    remaining = tonumber(payload.remaining),
    mode = payload.mode,
    electric = payload.electric == true,
  }
  reflectFuel(localVehicle, localProgress.fuel, generation)
end)

RegisterNetEvent(E.ENDED)
AddEventHandler(E.ENDED, function(reason, generation)
  if generation and tonumber(generation) ~= localGeneration then return end
  localActive = false
  localGeneration = nil
  localVehicle = nil
  localProgress = nil
  pendingFuel = nil
  local serverId = GetPlayerServerId(PlayerId())
  remoteEnded[serverId] = math.max(remoteEnded[serverId] or 0, tonumber(generation) or 0)
  remoteTokens[serverId] = remoteEnded[serverId]
  remotePending[serverId] = nil
  deleteVisual(remoteVisuals[serverId])
  remoteVisuals[serverId] = nil
  clearCarry()
  stopRefuelAnimation()
  local messages = {
    full = 'Tanque cheio.', no_money = 'Dinheiro insuficiente.', timeout = 'Sessão expirada.',
    no_can = 'Galão indisponível.', commit_error = 'Falha ao persistir combustível.',
    state_error = 'Estado de combustível indisponível.', invalid = 'Abastecimento interrompido.',
    empty_can = 'Galão vazio.', hose_distance = 'Mangueira desconectada: distância excedida.',
  }
  if messages[reason] then TriggerEvent('vHub:notify', 'info', messages[reason]) end
end)


-- ============================================================
-- BLIPS / COMMAND / LIFECYCLE
-- ============================================================

local function addBlips(stations, sprite, label)
  for index = 1, #stations do
    local coords = stations[index]
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite); SetBlipScale(blip, 0.65); SetBlipColour(blip, 4)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(label); EndTextCommandSetBlipName(blip)
    blips[#blips + 1] = blip
  end
end

Citizen.CreateThread(function()
  registerTargets()
  addBlips(C.GasStations, 361, 'Posto de combustível')
  addBlips(C.ElectricStations, 354, 'Estação de recarga')
end)

RegisterCommand('fuel', function(_, args)
  local amount = tonumber(args[1])
  local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  if not amount or vehicle == 0 or not NetworkGetEntityIsNetworked(vehicle) then return end
  TriggerServerEvent(E.ADMIN_SET, VehToNet(vehicle), amount)
end, false)

-- Retorna o fuel autoritativo replicado; fallback nativo somente sem registro CORE.
exports('GetFuel', function(vehicle)
  vehicle = tonumber(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0.0 end
  local value = Entity(vehicle).state.vh_fuel
  if type(value) ~= 'number' then value = GetVehicleFuelLevel(vehicle) end
  value = tonumber(value) or 0.0
  return math.max(0.0, math.min(100.0, value))
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  localActive = false
  localGeneration = nil
  localVehicle = nil
  localProgress = nil
  pendingFuel = nil
  stopRefuelAnimation()
  clearCarry()
  for serverId, visual in pairs(remoteVisuals) do
    deleteVisual(visual); remoteVisuals[serverId] = nil
  end
  for index = 1, #blips do RemoveBlip(blips[index]) end
end)
