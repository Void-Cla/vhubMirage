-- client/world.lua  weather/time/blackout/clearzone/announce/staff
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

local _weather = nil       -- override global
local _time    = nil       -- { h, m }
local _blackout = false

-- aplica snapshot de mundo quando o servidor atualiza o GlobalState (inclui late-joiners)
AddStateBagChangeHandler('vhub_admin_world', nil, function(bagName, _, data)
  if bagName ~= 'global' or type(data) ~= 'table' then return end
  if data.weather then
    _weather = data.weather
    ClearOverrideWeather()
    SetOverrideWeather(data.weather)
    SetWeatherTypeNow(data.weather)
    SetWeatherTypeNowPersist(data.weather)
  end
  if data.hour ~= nil and data.minute ~= nil then
    _time = { h = data.hour, m = data.minute }
    NetworkOverrideClockTime(data.hour, data.minute, 0)
  end
  if data.blackout ~= nil then
    _blackout = data.blackout == true
    SetArtificialLightsState(_blackout)
  end
end)

-- thread leve para reaplicar (alguns scripts resetam time/weather)
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(60 * 1000)
    if _weather then SetWeatherTypeNowPersist(_weather) end
    if _time    then NetworkOverrideClockTime(_time.h, _time.m, 0) end
    if _blackout then SetArtificialLightsState(true) end
  end
end)

RegisterNetEvent(E.DO_CLEARZONE)
AddEventHandler(E.DO_CLEARZONE, function(data)
  local x, y, z, r = data.x, data.y, data.z, data.radius
  ClearAreaOfVehicles(x, y, z, r, false, false, false, false, false)
  ClearAreaOfPeds(x, y, z, r, 1)
  ClearAreaOfObjects(x, y, z, r, 0)
  ClearAreaOfProjectiles(x, y, z, r, 0)
end)

-- ----------------------------------------------------------------------------
-- Announce: banner full-screen (toast NUI se aberto, fallback DrawText)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ANNOUNCE)
AddEventHandler(E.ANNOUNCE, function(msg)
  if S.panel_open then
    SendNUIMessage({ action = VHubAdmin.UI.ANNOUNCE, data = { text = msg } })
  end
  -- HUD persistente 10s
  Citizen.CreateThread(function()
    local until_t = GetGameTimer() + 10000
    while GetGameTimer() < until_t do
      Citizen.Wait(0)
      SetTextScale(0.55, 0.55); SetTextFont(4); SetTextProportional(true)
      SetTextColour(255, 220, 80, 235); SetTextOutline()
      SetTextEntry('STRING'); AddTextComponentString('  ' .. msg)
      DrawText(0.5, 0.06)
    end
  end)
  -- feed também
  VHubAdmin.notify('[ADV] ' .. msg)
end)

-- ----------------------------------------------------------------------------
-- Staff chat
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.STAFF_MSG)
AddEventHandler(E.STAFF_MSG, function(who, msg)
  TriggerEvent('chat:addMessage', {
    color = { 180, 80, 220 },
    multiline = true,
    args = { '[STAFF] ' .. who, msg },
  })
end)

-- ----------------------------------------------------------------------------
-- Comandos slash
-- ----------------------------------------------------------------------------
RegisterCommand('weather', function(_, args)
  if not S.is_admin then return end
  if args[1] then TriggerServerEvent(E.ACT_WEATHER, args[1]:upper()) end
end, false)

RegisterCommand('time', function(_, args)
  if not S.is_admin then return end
  local h, m = tonumber(args[1]), tonumber(args[2]) or 0
  if h then TriggerServerEvent(E.ACT_TIME, h, m) end
end, false)

RegisterCommand('blackout', function(_, args)
  if not S.is_admin then return end
  local on = args[1] == '1' or args[1] == 'on' or args[1] == 'true'
  TriggerServerEvent(E.ACT_BLACKOUT, on)
end, false)

RegisterCommand('clearzone', function(_, args)
  if not S.is_admin then return end
  TriggerServerEvent(E.ACT_CLEARZONE, tonumber(args[1]) or 200)
end, false)

RegisterCommand('adv', function(_, args)
  if not S.is_admin then return end
  local msg = table.concat(args, ' ')
  if msg ~= '' then TriggerServerEvent(E.ACT_ANNOUNCE, msg) end
end, false)

RegisterCommand('announce', function(_, args)
  if not S.is_admin then return end
  local msg = table.concat(args, ' ')
  if msg ~= '' then TriggerServerEvent(E.ACT_ANNOUNCE, msg) end
end, false)

RegisterCommand('staff', function(_, args)
  if not S.is_admin then return end
  local msg = table.concat(args, ' ')
  if msg ~= '' then TriggerServerEvent(E.ACT_STAFFCHAT, msg) end
end, false)

RegisterCommand('s', function(_, args)
  if not S.is_admin then return end
  local msg = table.concat(args, ' ')
  if msg ~= '' then TriggerServerEvent(E.ACT_STAFFCHAT, msg) end
end, false)
