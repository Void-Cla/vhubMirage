-- client/init.lua - NUI, comandos e callbacks do vhub_racha.

local Cfg, E = VHubRachaCfg, VHubRachaE
local open = false

local function notify(msg, kind)
  SendNUIMessage({ action = 'toast', data = { msg = tostring(msg or ''), kind = kind or 'info' } })
  if open then return end
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg or ''))
  EndTextCommandThefeedPostTicker(false, false)
end

local function vehicle_meta()
  local ped, veh = PlayerPedId(), GetVehiclePedIsIn(PlayerPedId(), false)
  if veh == 0 then return {} end
  local model = GetEntityModel(veh)
  return { plate = GetVehicleNumberPlateText(veh) or '', model = GetDisplayNameFromVehicleModel(model) or tostring(model), class = GetVehicleClass(veh) }
end

local function open_panel(track_id) TriggerServerEvent(E.NUI_OPEN, { track_id = track_id }) end

local function close_panel()
  if not open then return end
  open = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
end

RegisterNetEvent(E.NUI_OPENED, function(data)
  open = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', data = data or {} })
end)

RegisterNetEvent(E.NUI_REFRESH, function(data) SendNUIMessage({ action = 'refresh', data = data or {} }) end)
RegisterNetEvent(E.NUI_RESULT, function(payload)
  SendNUIMessage({ action = 'result', data = payload or {} })
  if payload and payload.ok == false then notify(payload.err or 'acao_negada', 'error') end
end)
RegisterNetEvent(E.NOTIFY, function(payload)
  payload = type(payload) == 'table' and payload or { msg = tostring(payload or '') }
  notify(payload.msg, payload.kind)
end)

RegisterNUICallback('close', function(_, cb) close_panel(); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(data, cb) TriggerServerEvent(E.NUI_OPEN, { track_id = data and data.track_id or nil }); cb({ ok = true }) end)
RegisterNUICallback('setNick', function(data, cb) TriggerServerEvent('vhub_racha:profile:nick', { nickname = data and data.nickname or '', track_id = data and data.track_id or nil }); cb({ ok = true }) end)
RegisterNUICallback('create', function(data, cb) data = type(data) == 'table' and data or {}; data.vehicle = vehicle_meta(); TriggerServerEvent(E.CREATE_LOBBY, data); cb({ ok = true }) end)
RegisterNUICallback('join', function(data, cb) data = type(data) == 'table' and data or {}; data.vehicle = vehicle_meta(); TriggerServerEvent(E.JOIN_LOBBY, data); cb({ ok = true }) end)
RegisterNUICallback('start', function(data, cb) TriggerServerEvent(E.START_LOBBY, data or {}); cb({ ok = true }) end)
RegisterNUICallback('leave', function(data, cb) TriggerServerEvent(E.LEAVE_LOBBY, data or {}); cb({ ok = true }) end)
RegisterNUICallback('cancel', function(data, cb) TriggerServerEvent(E.CANCEL_LOBBY, data or {}); cb({ ok = true }) end)
RegisterNUICallback('route', function(data, cb)
  local track = VHubRachaUtils.track_by_id(data and data.track_id or '')
  if track and track.start then SetNewWaypoint(track.start.x + 0.0, track.start.y + 0.0) end
  cb({ ok = true })
end)

RegisterCommand(Cfg.CMD_OPEN, function() open_panel(nil) end, false)
RegisterKeyMapping('+vhub_racha_panel', 'vHub Racha - abrir painel', 'keyboard', Cfg.KEY_OPEN)
RegisterCommand('+vhub_racha_panel', function() open_panel(nil) end, false)
RegisterCommand('-vhub_racha_panel', function() end, false)
exports('openRacePanel', open_panel)
