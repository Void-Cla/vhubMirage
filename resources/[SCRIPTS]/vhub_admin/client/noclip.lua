-- client/noclip.lua — noclip administrativo com lifecycle finito
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

local SP_SLOW = 0.017
local SP_NORM = 0.083
local SP_FAST = 0.467

local DISABLED_CTRL = { 30, 31, 32, 33, 34, 35, 21, 22, 36, 24, 25 }
local CTRL_FWD = 32
local CTRL_BACK = 33
local CTRL_LEFT = 34
local CTRL_RIGHT = 35
local CTRL_SHIFT = 21
local CTRL_SPACE = 22
local CTRL_CTRL = 36

local _running = true
local _movement_generation = 0
local _noclip_entity = 0
local _noclip_ped = 0
local _noclip_vehicle = false
local _prior_god = false
local _prior_invis = false
local _lease_generation = 0


-- ============================================================
-- HELPERS
-- ============================================================

local function getNoclipEntity(ped)
  if IsPedInAnyVehicle(ped, false) then
    return GetVehiclePedIsIn(ped, false), true
  end
  return ped, false
end

local function hasControl(entity)
  if not NetworkGetEntityIsNetworked(entity) or NetworkHasControlOfEntity(entity) then return true end
  NetworkRequestControlOfEntity(entity)
  return NetworkHasControlOfEntity(entity)
end

local function awaitControl(entity, timeoutMs)
  if not NetworkGetEntityIsNetworked(entity) then return true end
  local deadline = GetGameTimer() + math.max(0, tonumber(timeoutMs) or 0)
  repeat
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    if NetworkHasControlOfEntity(entity) then return true end
    if GetGameTimer() >= deadline then return false end
    Citizen.Wait(25)
  until not DoesEntityExist(entity)
  return false
end

local function setPedProtection(ped, active)
  if not DoesEntityExist(ped) then return end
  SetPlayerInvincible(PlayerId(), active)
  SetEntityInvincible(ped, active)
  SetEntityProofs(ped, active, active, active, active, active, active, active, active)
  SetPedCanRagdoll(ped, not active)
end

local function clearVehicleProtection(entity)
  if not DoesEntityExist(entity) then return end
  SetEntityInvincible(entity, false)
  SetEntityProofs(entity, false, false, false, false, false, false, false, false)
end

local function rayGroundZ(x, y, fromZ)
  RequestCollisionAtCoord(x, y, fromZ)
  local deadline = GetGameTimer() + 1500
  while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < deadline do
    Citizen.Wait(50)
    RequestCollisionAtCoord(x, y, fromZ)
  end

  local handle = StartExpensiveSynchronousShapeTestLosProbe(
    x, y, fromZ, x, y, -500.0, 1, PlayerPedId(), 4)
  local _, hit, endCoords = GetShapeTestResult(handle)
  if (hit == 1 or hit == true) and endCoords then return endCoords.z end

  for z = fromZ, -100.0, -25.0 do
    local found, ground = GetGroundZFor_3dCoord(x, y, z, false)
    if found and ground then return ground end
  end
  return nil
end


-- ============================================================
-- MOVIMENTO — thread existe somente durante noclip
-- ============================================================

local disable

local function startMovement()
  _movement_generation = _movement_generation + 1
  local generation = _movement_generation

  Citizen.CreateThread(function()
    while _running and S.noclip and generation == _movement_generation do
      Citizen.Wait(0)
      local entity = _noclip_entity
      if entity == 0 or not DoesEntityExist(entity) then
        disable(PlayerPedId(), true, true)
        return
      end
      if not _noclip_vehicle or hasControl(entity) then
        SetEntityCollision(entity, false, false)
        SetEntityHasGravity(entity, false)
        for _, control in ipairs(DISABLED_CTRL) do DisableControlAction(0, control, true) end

        local holdCtrl = IsDisabledControlPressed(0, CTRL_CTRL)
        local holdShift = IsDisabledControlPressed(0, CTRL_SHIFT)
        local speed = holdCtrl and SP_SLOW or (holdShift and SP_FAST or SP_NORM)

        local camera = GetGameplayCamRot(2)
        local rx, rz = math.rad(camera.x), math.rad(camera.z)
        local fx = -math.sin(rz) * math.cos(rx)
        local fy = math.cos(rz) * math.cos(rx)
        local fz = math.sin(rx)
        local sx = math.cos(rz)
        local sy = math.sin(rz)
        local dx, dy, dz = 0.0, 0.0, 0.0

        if IsDisabledControlPressed(0, CTRL_FWD) then
          dx, dy, dz = dx + fx * speed, dy + fy * speed, dz + fz * speed
        end
        if IsDisabledControlPressed(0, CTRL_BACK) then
          dx, dy, dz = dx - fx * speed, dy - fy * speed, dz - fz * speed
        end
        if IsDisabledControlPressed(0, CTRL_LEFT) then
          dx, dy = dx - sx * speed, dy - sy * speed
        end
        if IsDisabledControlPressed(0, CTRL_RIGHT) then
          dx, dy = dx + sx * speed, dy + sy * speed
        end
        if IsDisabledControlPressed(0, CTRL_SPACE) then dz = dz + speed end
        if holdCtrl and not IsDisabledControlPressed(0, CTRL_FWD) then dz = dz - SP_SLOW end

        local pos = GetEntityCoords(entity)
        SetEntityCoordsNoOffset(entity, pos.x + dx, pos.y + dy, pos.z + dz, false, false, false)
        SetEntityHeading(entity, camera.z % 360.0)
      end
    end
  end)
end


-- ============================================================
-- LIFECYCLE
-- ============================================================

local function enable(ped)
  local entity, isVehicle = getNoclipEntity(ped)
  if entity == 0 or not DoesEntityExist(entity) then return false end
  if isVehicle and not awaitControl(entity, 500) then
    VHubAdmin.notify('Sem controle de rede do veiculo.')
    return false
  end

  _prior_god = S.god == true
  _prior_invis = S.invis == true
  _noclip_entity = entity
  _noclip_ped = ped
  _noclip_vehicle = isVehicle

  S.noclip, S.god, S.invis = true, true, true
  setPedProtection(ped, true)
  if isVehicle then
    SetEntityInvincible(entity, true)
    SetEntityProofs(entity, true, true, true, true, true, true, true, true)
  end

  SetEntityVisible(ped, false, false)
  SetEntityAlpha(ped, 0, false)
  NetworkSetEntityInvisibleToNetwork(ped, true)
  if isVehicle then
    SetEntityVisible(entity, false, false)
    SetEntityAlpha(entity, 0, false)
    NetworkSetEntityInvisibleToNetwork(entity, true)
    SetEntityCollision(ped, false, false)
  end

  SetEntityCollision(entity, false, false)
  SetEntityHasGravity(entity, false)
  SetEntityVelocity(entity, 0.0, 0.0, 0.0)
  FreezeEntityPosition(entity, false)
  startMovement()
  return true
end

disable = function(ped, skipGround, forceClear)
  local entity = _noclip_entity ~= 0 and _noclip_entity or ped
  local originalPed = _noclip_ped ~= 0 and _noclip_ped or ped
  local wasVehicle = _noclip_vehicle
  local restoreGod = not forceClear and _prior_god or false
  local restoreInvis = not forceClear and _prior_invis or false
  local controlled = not wasVehicle or awaitControl(entity, skipGround and 0 or 500)

  _movement_generation = _movement_generation + 1
  S.noclip, S.god, S.invis = false, restoreGod, restoreInvis

  setPedProtection(originalPed, false)
  if ped ~= originalPed then setPedProtection(ped, false) end
  setPedProtection(ped, restoreGod)

  if DoesEntityExist(originalPed) then
    SetEntityVisible(originalPed, true, false)
    ResetEntityAlpha(originalPed)
    NetworkSetEntityInvisibleToNetwork(originalPed, false)
    SetEntityCollision(originalPed, true, true)
  end
  if DoesEntityExist(ped) then
    SetEntityVisible(ped, not restoreInvis, false)
    SetEntityAlpha(ped, restoreInvis and 0 or 255, false)
    NetworkSetEntityInvisibleToNetwork(ped, restoreInvis)
  end
  if wasVehicle and controlled and DoesEntityExist(entity) then
    SetEntityVisible(entity, true, false)
    ResetEntityAlpha(entity)
    NetworkSetEntityInvisibleToNetwork(entity, false)
  end

  local function restorePhysics()
    if not DoesEntityExist(entity) then return end
    if wasVehicle and controlled then clearVehicleProtection(entity) end

    if not skipGround and controlled then
      local coords = GetEntityCoords(entity)
      local ground = rayGroundZ(coords.x, coords.y, coords.z + 30.0)
      if ground then
        SetEntityCoordsNoOffset(
          entity,
          coords.x,
          coords.y,
          ground + (wasVehicle and 1.0 or 0.05),
          false,
          false,
          false
        )
      end
    end

    ClearPedTasksImmediately(ped)
    SetEntityCollision(entity, true, true)
    SetEntityHasGravity(entity, true)
    if controlled then
      SetEntityVelocity(entity, 0.0, 0.0, skipGround and 0.0 or -1.0)
      FreezeEntityPosition(entity, false)
    end
  end

  if skipGround then restorePhysics()
  else Citizen.CreateThread(function() Citizen.Wait(50); restorePhysics() end) end

  _noclip_entity, _noclip_ped = 0, 0
  _noclip_vehicle = false
  _prior_god, _prior_invis = false, false
end

local function toggleNoclip()
  local ped = PlayerPedId()
  if S.noclip then
    disable(ped, false, false)
  elseif not enable(ped) then
    TriggerServerEvent(E.NOCLIP_LEASE, false)
    return
  end

  _lease_generation = _lease_generation + 1
  local lease_generation = _lease_generation
  TriggerServerEvent(E.NOCLIP_LEASE, S.noclip == true)
  if S.noclip then
    local function renewLease()
      if not _running or not S.noclip or lease_generation ~= _lease_generation then return end
      TriggerServerEvent(E.NOCLIP_LEASE, true)
      SetTimeout(2000, renewLease)
    end
    SetTimeout(2000, renewLease)
  end

  VHubAdmin.notify(S.noclip and 'Noclip ON — god+invis' or 'Noclip OFF')
  VHubAdmin.syncUi({ noclip = S.noclip, god = S.god, invis = S.invis })
end


-- ============================================================
-- EVENTOS / COMANDOS / CLEANUP
-- ============================================================

RegisterNetEvent(E.TOGGLE_NOCLIP)
AddEventHandler(E.TOGGLE_NOCLIP, toggleNoclip)

local function requestNoclip()
  TriggerServerEvent(E.ACT_NOCLIP)
end

RegisterCommand('nc', requestNoclip, false)
RegisterCommand('noclip', requestNoclip, false)
RegisterKeyMapping('noclip', 'Alternar noclip administrativo', 'keyboard', 'N')

AddEventHandler(E.CLEANUP_EFFECTS, function()
  if S.noclip or _noclip_entity ~= 0 then
    disable(PlayerPedId(), true, true)
    _lease_generation = _lease_generation + 1
    TriggerServerEvent(E.NOCLIP_LEASE, false)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  _running = false
  if S.noclip or _noclip_entity ~= 0 then disable(PlayerPedId(), true, true) end
end)
