-- server/world.lua - estado mundial e manutencao administrativa server-side
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E
local U = VHubAdmin.U

local weatherAllowed = {}
for weather in pairs(CFG.world.weathers) do weatherAllowed[weather] = true end

local world = {
  weather = 'CLEAR',
  hour = 12,
  minute = 0,
  blackout = false,
  revision = 0,
}

local wiping = false


-- ============================================================
-- ESTADO CONTINUO
-- ============================================================

-- Replica o snapshot mundial pelo State Bag global.
local function syncWorld()
  world.revision = world.revision + 1
  GlobalState.vhub_admin_world = {
    weather = world.weather,
    hour = world.hour,
    minute = world.minute,
    blackout = world.blackout,
    revision = world.revision,
  }
end

RegisterNetEvent(E.ACT_WEATHER)
AddEventHandler(E.ACT_WEATHER, function(rawWeather)
  local src = source
  if not Core:guard(src, 'weather', 'world') then return end

  local weather = U.safeText(rawWeather, 24):upper()
  if not weatherAllowed[weather] then return Core:notify(src, 'Clima invalido.', 'erro') end

  world.weather = weather
  syncWorld()
  Core:audit(src, 'weather', nil, { weather = weather })
end)

RegisterNetEvent(E.ACT_TIME)
AddEventHandler(E.ACT_TIME, function(rawHour, rawMinute)
  local src = source
  if not Core:guard(src, 'time', 'world') then return end

  local hour = U.number(rawHour, 0, 23)
  local minute = U.number(rawMinute, 0, 59)
  if not hour or not minute or hour % 1 ~= 0 or minute % 1 ~= 0 then
    return Core:notify(src, 'Horario invalido.', 'erro')
  end

  world.hour = math.floor(hour)
  world.minute = math.floor(minute)
  syncWorld()
  Core:audit(src, 'time', nil, { hour = world.hour, minute = world.minute })
end)

RegisterNetEvent(E.ACT_BLACKOUT)
AddEventHandler(E.ACT_BLACKOUT, function(value)
  local src = source
  if not Core:guard(src, 'blackout', 'world') then return end
  if value ~= nil and type(value) ~= 'boolean' then
    return Core:notify(src, 'Estado de apagao invalido.', 'erro')
  end

  if value == nil then world.blackout = not world.blackout
  else world.blackout = value end
  syncWorld()
  Core:notify(src, world.blackout and 'Apagao ativado.' or 'Apagao desativado.', 'sucesso')
  Core:audit(src, 'blackout', nil, { on = world.blackout })
end)

AddEventHandler('onResourceStart', function(resource)
  if resource == GetCurrentResourceName() then syncWorld() end
end)


-- ============================================================
-- LIMPEZA E COMUNICACAO
-- ============================================================

-- Limpa somente efeitos locais nao persistentes no cliente do administrador.
RegisterNetEvent(E.ACT_CLEARZONE)
AddEventHandler(E.ACT_CLEARZONE, function(rawRadius)
  local src = source
  if not Core:guard(src, 'clearzone', 'world') then return end

  local radius = U.number(rawRadius, 25, 500)
  local pos = Core:coordsOf(src)
  if not radius or not pos then return Core:notify(src, 'Area invalida.', 'erro') end

  TriggerClientEvent(E.DO_CLEARZONE, src, { x = pos.x, y = pos.y, z = pos.z, radius = radius })
  Core:audit(src, 'clearzone', nil, { radius = radius })
end)

local function playerPeds()
  local out = {}
  for _, raw in ipairs(GetPlayers()) do
    local ped = GetPlayerPed(raw)
    if ped and ped ~= 0 then out[ped] = true end
  end
  return out
end

local function occupiedVehicles()
  local out = {}
  for _, raw in ipairs(GetPlayers()) do
    local ped = GetPlayerPed(raw)
    if ped and ped ~= 0 then
      local vehicle = GetVehiclePedIsIn(ped, false)
      if vehicle and vehicle ~= 0 then out[vehicle] = true end
    end
  end
  return out
end

-- Remove entidades sem jogador, limitada para manter o tick previsivel.
local function wipe(kind)
  local entities
  local protected = nil
  if kind == 'vehicles' then
    entities = GetAllVehicles()
    protected = occupiedVehicles()
  elseif kind == 'peds' then
    entities = GetAllPeds()
    protected = playerPeds()
  elseif kind == 'objects' then
    entities = GetAllObjects()
  else
    return nil
  end

  local removed = 0
  local inspected = 0
  for _, entity in ipairs(entities) do
    inspected = inspected + 1
    if removed >= CFG.limits.wipe_cap then break end
    if DoesEntityExist(entity) and (not protected or not protected[entity]) then
      DeleteEntity(entity)
      removed = removed + 1
    end
    if inspected % 50 == 0 then Citizen.Wait(0) end
  end
  return removed
end

local wipeKinds = { vehicles = true, peds = true, objects = true }

RegisterNetEvent(E.ACT_WIPE)
AddEventHandler(E.ACT_WIPE, function(kind)
  local src = source
  if not Core:guard(src, 'wipe', 'wipe') then return end
  if type(kind) ~= 'string' or not wipeKinds[kind] then
    return Core:notify(src, 'Tipo de limpeza invalido.', 'erro')
  end
  if wiping then return Core:notify(src, 'Limpeza global em andamento.', 'info') end

  wiping = true
  Citizen.CreateThread(function()
    local removed = wipe(kind) or 0
    wiping = false
    Core:notify(src, ('Limpeza de %s: %d removidos.'):format(kind, removed), 'sucesso')
    Core:audit(src, 'wipe', nil, { kind = kind, removed = removed })
  end)
end)

RegisterNetEvent(E.ACT_ANNOUNCE)
AddEventHandler(E.ACT_ANNOUNCE, function(message)
  local src = source
  if not Core:guard(src, 'announce', 'world') then return end

  local text = U.safeText(message, CFG.limits.announce_chars)
  if text == '' then return Core:notify(src, 'Mensagem vazia.', 'erro') end

  TriggerClientEvent(E.ANNOUNCE, -1, text)
  Core:audit(src, 'announce', nil, { message = text })
end)

RegisterNetEvent(E.ACT_STAFFCHAT)
AddEventHandler(E.ACT_STAFFCHAT, function(message)
  local src = source
  if not Core:guard(src, 'staffchat', 'world') then return end

  local text = U.safeText(message, 220)
  if text == '' then return Core:notify(src, 'Mensagem vazia.', 'erro') end

  local session = Core:getSession(src)
  local name = U.safeText((session and session.name) or GetPlayerName(src) or '?', 64)
  Core:eachAdmin(function(adminSrc)
    TriggerClientEvent(E.STAFF_MSG, adminSrc, name, text)
  end)
  Core:audit(src, 'staffchat', nil, { message = text })
end)
