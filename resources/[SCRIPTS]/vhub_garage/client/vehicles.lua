-- client/vehicles.lua  spawn/despawn de ve culos + estado visual
-- Mant m mapa local plate   entity, registra decorator e cuida do surface (ground/water/air).
---@diagnostic disable: undefined-global

local E = VHubGarage.E
local state = VHubGarage.state

state.veiculos = state.veiculos or {}

Citizen.CreateThread(function() DecorRegister('vhub.plate', 7) end)  -- 7 = string

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
local function loadModel(name)
  local hash = type(name) == 'number' and name or GetHashKey(name)
  if not IsModelInCdimage(hash) then return nil end
  RequestModel(hash)
  local t = 0
  while not HasModelLoaded(hash) and t < 5000 do Citizen.Wait(50); t = t + 50 end
  return HasModelLoaded(hash) and hash or nil
end

local function placeOnSurface(veh, surface)
  if surface == 'water' then
    SetEntityCoordsNoOffset(veh, GetEntityCoords(veh), false, false, false)
  elseif surface == 'pad' or surface == 'runway' then
    -- aeronaves: deixa na altura recebida do servidor
  else
    SetVehicleOnGroundProperly(veh)
  end
end

local function applyCustomization(veh, c)
  if type(c) ~= 'table' then return end
  SetVehicleModKit(veh, 0)
  if c.colours        then SetVehicleColours(veh, table.unpack(c.colours)) end
  if c.extra_colours  then SetVehicleExtraColours(veh, table.unpack(c.extra_colours)) end
  if c.plate_index    then SetVehicleNumberPlateTextIndex(veh, c.plate_index) end
  if c.wheel_type     then SetVehicleWheelType(veh, c.wheel_type) end
  if c.window_tint    then SetVehicleWindowTint(veh, c.window_tint) end
  if c.livery         then SetVehicleLivery(veh, c.livery) end
  if type(c.mods) == 'table' then
    for i, m in pairs(c.mods) do SetVehicleMod(veh, tonumber(i), m, false) end
  end
  if c.turbo  ~= nil then ToggleVehicleMod(veh, 18, c.turbo) end
  if c.smoke  ~= nil then ToggleVehicleMod(veh, 20, c.smoke) end
  if c.xenon  ~= nil then ToggleVehicleMod(veh, 22, c.xenon) end
  if type(c.neons) == 'table' then
    for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, c.neons[i] == true) end
  end
  if c.neon_colour then SetVehicleNeonLightsColour(veh, table.unpack(c.neon_colour)) end
end

local function collectCustomization(veh)
  local c = {
    colours       = { GetVehicleColours(veh) },
    extra_colours = { GetVehicleExtraColours(veh) },
    plate_index   = GetVehicleNumberPlateTextIndex(veh),
    wheel_type    = GetVehicleWheelType(veh),
    window_tint   = GetVehicleWindowTint(veh),
    livery        = GetVehicleLivery(veh),
    turbo         = IsToggleModOn(veh, 18),
    smoke         = IsToggleModOn(veh, 20),
    xenon         = IsToggleModOn(veh, 22),
    mods          = {},
    neons         = {},
    neon_colour   = { GetVehicleNeonLightsColour(veh) },
    model         = GetEntityModel(veh),
  }
  for i = 0, 49 do c.mods[i] = GetVehicleMod(veh, i) end
  for i = 0, 3  do c.neons[i] = IsVehicleNeonLightEnabled(veh, i) end
  return c
end

-- ----------------------------------------------------------------------------
-- SPAWN
-- ----------------------------------------------------------------------------
local function spawnVehicle(snap, pos, entrar)
  local hash = loadModel(snap.model)
  if not hash then return false end
  local x, y, z = pos.x, pos.y, pos.z + 0.5
  local h = pos.h or 0.0
  local veh = CreateVehicle(hash, x, y, z, h, true, false)
  SetModelAsNoLongerNeeded(hash)
  if not DoesEntityExist(veh) then return false end
  SetVehicleNumberPlateText(veh, snap.plate)
  placeOnSurface(veh, snap.surface)
  SetEntityAsMissionEntity(veh, true, true)
  SetVehicleHasBeenOwnedByPlayer(veh, true)
  DecorSetString(veh, 'vhub.plate', snap.plate)
  applyCustomization(veh, snap.customization)
  if snap.locked then
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDoorsLockedForAllPlayers(veh, true)
  end
  if entrar then SetPedIntoVehicle(PlayerPedId(), veh, -1) end
  state.veiculos[snap.plate] = veh
  return true, veh
end

RegisterNetEvent(E.DO_SPAWN)
AddEventHandler(E.DO_SPAWN, function(snap, pos)
  Citizen.CreateThread(function() spawnVehicle(snap, pos, true) end)
end)

RegisterNetEvent(E.SPAWN_OUT)
AddEventHandler(E.SPAWN_OUT, function(list)
  if type(list) ~= 'table' then return end
  Citizen.CreateThread(function()
    for _, snap in ipairs(list) do
      spawnVehicle(snap, snap.position or { x = 0, y = 0, z = 0, h = 0 }, false)
    end
  end)
end)

-- ----------------------------------------------------------------------------
-- DESPAWN
-- ----------------------------------------------------------------------------
local function despawnLocal(plate)
  local veh = state.veiculos[plate]
  if not veh or not DoesEntityExist(veh) then state.veiculos[plate] = nil; return end
  if GetVehiclePedIsIn(PlayerPedId(), false) == veh then
    TaskLeaveVehicle(PlayerPedId(), veh, 4160); Citizen.Wait(500)
  end
  SetEntityAsMissionEntity(veh, false, true)
  local ref = veh
  SetVehicleAsNoLongerNeeded(ref)
  state.veiculos[plate] = nil
end

RegisterNetEvent(E.DO_DESPAWN)
AddEventHandler(E.DO_DESPAWN, function(plate)
  despawnLocal(plate)
end)

-- ----------------------------------------------------------------------------
-- Test drive (cliente cria, removido ao fim ou ao se afastar)
-- ----------------------------------------------------------------------------
local _td = nil
local function endTestDrive(msg)
  if _td and DoesEntityExist(_td.veh) then
    if GetVehiclePedIsIn(PlayerPedId(), false) == _td.veh then
      TaskLeaveVehicle(PlayerPedId(), _td.veh, 4160); Citizen.Wait(500)
    end
    SetEntityAsMissionEntity(_td.veh, false, true)
    SetVehicleAsNoLongerNeeded(_td.veh)
  end
  _td = nil
  if msg then
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
  end
end

RegisterNetEvent(E.DO_TESTDRIVE)
AddEventHandler(E.DO_TESTDRIVE, function(data)
  Citizen.CreateThread(function()
    endTestDrive(nil)
    local hash = loadModel(data.model); if not hash then return end
    local sp = data.spawn or { x = 0, y = 0, z = 0, h = 0 }
    local veh = CreateVehicle(hash, sp.x, sp.y, sp.z + 0.5, sp.h or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(veh) then return end
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetPedIntoVehicle(PlayerPedId(), veh, -1)
    _td = { veh = veh, expires = GetGameTimer() + data.seg * 1000, raio = data.raio, origin = vector3(sp.x, sp.y, sp.z) }
    -- watchdog
    Citizen.CreateThread(function()
      while _td and _td.veh == veh do
        Citizen.Wait(1000)
        if GetGameTimer() > _td.expires then endTestDrive('Test drive encerrado.'); break end
        local d = #(GetEntityCoords(PlayerPedId()) - _td.origin)
        if d > _td.raio then endTestDrive('Voc  se afastou demais. Test drive cancelado.'); break end
      end
    end)
  end)
end)

-- ----------------------------------------------------------------------------
-- Coleta de estado (para `store` no servidor)
-- Event handlers em FXServer N O retornam valores; chamamos via callback param.
-- Uso: TriggerEvent('vhub_garage:collectClientState', plate, function(s) ... end)
-- ----------------------------------------------------------------------------
AddEventHandler('vhub_garage:collectClientState', function(plate, cb)
  if type(cb) ~= 'function' then return end
  local veh = state.veiculos[plate]
  if not veh or not DoesEntityExist(veh) then cb(nil); return end
  local c = GetEntityCoords(veh, true)
  cb({
    customization = collectCustomization(veh),
    locked        = GetVehicleDoorLockStatus(veh) >= 2,
    position      = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(veh) },
  })
end)

-- ----------------------------------------------------------------------------
-- Reporte peri dico ao servidor (n o-cr tico: posi  o + customization)
-- ----------------------------------------------------------------------------
Citizen.CreateThread(function()
  local cfg = VHubGarage.cfg
  while true do
    Citizen.Wait((cfg.report_intervalo_s or 30) * 1000)
    for plate, veh in pairs(state.veiculos) do
      if DoesEntityExist(veh) and IsEntityAVehicle(veh) then
        local c = GetEntityCoords(veh, true)
        TriggerServerEvent(E.REPORT_STATE, plate, {
          position = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(veh) },
          locked   = GetVehicleDoorLockStatus(veh) >= 2,
        })
      else
        state.veiculos[plate] = nil
      end
    end
  end
end)

-- ----------------------------------------------------------------------------
-- Helpers expostos a outros m dulos do client
-- ----------------------------------------------------------------------------
function VHubGarage.veiculoMaisProximo(raio)
  raio = raio or 18.0
  local ped = PlayerPedId()
  local origin = GetEntityCoords(ped)
  local best, best_d = nil, raio
  for plate, veh in pairs(state.veiculos) do
    if DoesEntityExist(veh) then
      local d = #(origin - GetEntityCoords(veh))
      if d < best_d then best, best_d = plate, d end
    end
  end
  return best
end
