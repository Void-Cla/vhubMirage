-- server/world.lua  weather / time / blackout / clearzone / announce / staffchat
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local CFG  = VHubAdmin.cfg
local E    = VHubAdmin.E
local U    = VHubAdmin.U

local function reqPerm(src, k)
  if not Core.hasPerm(src, k) then Core.notify(src, 'Sem permiss o.'); return false end
  return true
end

local WEATHERS = {
  EXTRASUNNY=true, CLEAR=true, CLOUDS=true, OVERCAST=true,
  RAIN=true, CLEARING=true, THUNDER=true, SMOG=true,
  FOGGY=true, XMAS=true, SNOWLIGHT=true, BLIZZARD=true,
}

RegisterNetEvent(E.ACT_WEATHER)
AddEventHandler(E.ACT_WEATHER, function(wx)
  local src = source; if not reqPerm(src, 'weather') then return end
  wx = tostring(wx or ''):upper()
  if not WEATHERS[wx] then Core.notify(src, 'Clima inv lido.'); return end
  TriggerClientEvent(E.DO_WEATHER, -1, wx)
  Core:audit(src, 'weather', nil, { wx = wx })
end)

RegisterNetEvent(E.ACT_TIME)
AddEventHandler(E.ACT_TIME, function(hour, minute)
  local src = source; if not reqPerm(src, 'time') then return end
  local h = U.clamp(tonumber(hour) or 0, 0, 23)
  local m = U.clamp(tonumber(minute) or 0, 0, 59)
  TriggerClientEvent(E.DO_TIME, -1, h, m)
  Core:audit(src, 'time', nil, { h = h, m = m })
end)

RegisterNetEvent(E.ACT_BLACKOUT)
AddEventHandler(E.ACT_BLACKOUT, function(on)
  local src = source; if not reqPerm(src, 'blackout') then return end
  TriggerClientEvent(E.DO_BLACKOUT, -1, on == true)
  Core:audit(src, 'blackout', nil, { on = on })
end)

RegisterNetEvent(E.ACT_CLEARZONE)
AddEventHandler(E.ACT_CLEARZONE, function(radius)
  local src = source; if not reqPerm(src, 'clearzone') then return end
  local r = U.clamp(tonumber(radius) or 200, 50, 3000)
  local c = Core.coordsOf(src); if not c then return end
  TriggerClientEvent(E.DO_CLEARZONE, -1, c.x, c.y, c.z, r)
  Core:audit(src, 'clearzone', nil, { r = r })
end)

-- ----------------------------------------------------------------------------
-- WIPE global server-side (R1: zero broadcast; entidade some via replica  o)
-- Prote  es: ve culo com jogador dentro e ped de jogador NUNCA s o deletados.
-- Custo: O(entidades) one-shot, sem thread residente.
-- ----------------------------------------------------------------------------
local function playerVehicleSet()
  local set = {}
  for _, s in ipairs(GetPlayers()) do
    local ped = GetPlayerPed(s)
    if ped and ped ~= 0 then
      local veh = GetVehiclePedIsIn(ped, false)
      if veh and veh ~= 0 then set[veh] = true end
    end
  end
  return set
end

local function playerPedSet()
  local set = {}
  for _, s in ipairs(GetPlayers()) do
    local ped = GetPlayerPed(s)
    if ped and ped ~= 0 then set[ped] = true end
  end
  return set
end

local WIPE_KINDS = { vehicles = true, peds = true, objects = true }

RegisterNetEvent(E.ACT_WIPE)
AddEventHandler(E.ACT_WIPE, function(kind)
  local src = source; if not reqPerm(src, 'wipe') then return end
  kind = tostring(kind or '')
  if not WIPE_KINDS[kind] then return end

  local removed = 0
  if kind == 'vehicles' then
    local occupied = playerVehicleSet()
    for _, veh in ipairs(GetAllVehicles()) do
      if not occupied[veh] and DoesEntityExist(veh) then
        DeleteEntity(veh); removed = removed + 1
      end
    end
  elseif kind == 'peds' then
    local players = playerPedSet()
    for _, ped in ipairs(GetAllPeds()) do
      if not players[ped] and DoesEntityExist(ped) then
        DeleteEntity(ped); removed = removed + 1
      end
    end
  else
    for _, obj in ipairs(GetAllObjects()) do
      if DoesEntityExist(obj) then
        DeleteEntity(obj); removed = removed + 1
      end
    end
  end

  Core.notify(src, ('Wipe %s: %d removidos.'):format(kind, removed))
  Core:audit(src, 'wipe', nil, { kind = kind, removed = removed })
end)

RegisterNetEvent(E.ACT_ANNOUNCE)
AddEventHandler(E.ACT_ANNOUNCE, function(message)
  local src = source; if not reqPerm(src, 'announce') then return end
  local msg = U.safeText(message, CFG.limits.announce_chars)
  if msg == '' then Core.notify(src, 'Mensagem vazia.'); return end
  TriggerClientEvent(E.ANNOUNCE, -1, msg)
  Core:audit(src, 'announce', nil, { message = msg })
end)

RegisterNetEvent(E.ACT_STAFFCHAT)
AddEventHandler(E.ACT_STAFFCHAT, function(message)
  local src = source; if not reqPerm(src, 'staffchat') then return end
  local msg = U.safeText(message, 220)
  if msg == '' then return end
  local actor = Core:getSession(src)
  local who = actor and actor.name or '?'
  Core:eachAdmin(function(s)
    TriggerClientEvent(E.STAFF_MSG, s, who, msg)
  end)
  Core:audit(src, 'staffchat', nil, { message = msg })
end)
