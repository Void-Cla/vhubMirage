-- client/ui.lua — NUI callbacks (roteamento de eventos do painel para o server)
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state


-- ============================================================
-- LISTAS (servidor → NUI)
-- ============================================================

RegisterNetEvent(E.LOG_LIST)
AddEventHandler(E.LOG_LIST, function(rows)
  if not S.panel_open then return end
  SendNUIMessage({ action = VHubAdmin.UI.LOG_LIST, data = rows })
end)

RegisterNetEvent(E.REPORT_LIST)
AddEventHandler(E.REPORT_LIST, function(rows)
  if not S.panel_open then return end
  SendNUIMessage({ action = VHubAdmin.UI.REPORT_LIST, data = rows })
end)

RegisterNetEvent(E.DASHBOARD)
AddEventHandler(E.DASHBOARD, function(data)
  if not S.panel_open then return end
  SendNUIMessage({ action = VHubAdmin.UI.DASHBOARD, data = data })
end)

RegisterNetEvent(E.FLEET_LIST)
AddEventHandler(E.FLEET_LIST, function(data)
  if not S.panel_open then return end
  SendNUIMessage({ action = VHubAdmin.UI.FLEET_LIST, data = data })
end)

RegisterNetEvent(E.FLEET_DETAIL)
AddEventHandler(E.FLEET_DETAIL, function(data)
  if not S.panel_open then return end
  SendNUIMessage({ action = VHubAdmin.UI.FLEET_DETAIL, data = data })
end)


-- ============================================================
-- PEDIDOS NUI → server
-- ============================================================

RegisterNUICallback('reqPlayers', function(_, cb)
  TriggerServerEvent(E.REQ_PLAYERS); cb({ ok = true })
end)

-- pedido de ficha: target = src do player
RegisterNUICallback('reqRG', function(d, cb)
  TriggerServerEvent(E.REQ_PROFILE, tonumber(d.target)); cb({ ok = true })
end)

RegisterNUICallback('reqLogs', function(d, cb)
  TriggerServerEvent(E.REQ_LOGS, d.filter or {}, tonumber(d.limit) or 100); cb({ ok = true })
end)

RegisterNUICallback('reqReports', function(_, cb)
  TriggerServerEvent(E.REQ_REPORTS); cb({ ok = true })
end)

RegisterNUICallback('reqDash', function(_, cb)
  TriggerServerEvent(E.REQ_DASHBOARD); cb({ ok = true })
end)

RegisterNUICallback('reqFleet', function(d, cb)
  TriggerServerEvent(E.REQ_FLEET, d and d.filter or {}, d and d.offset or 0); cb({ ok = true })
end)

RegisterNUICallback('reqFleetDetail', function(d, cb)
  if not d or not d.plate then return cb({ ok = false }) end
  TriggerServerEvent(E.REQ_FLEET_DETAIL, d.plate); cb({ ok = true })
end)

RegisterNUICallback('reqPickers', function(_, cb)
  -- pickers: players + catálogos (sem evento dedicado, server inclui no dashboard)
  TriggerServerEvent(E.REQ_DASHBOARD); cb({ ok = true })
end)

-- noclip é toggle 100% client-side (client/noclip.lua)
RegisterNUICallback('noclip', function(_, cb)
  ExecuteCommand('noclip'); cb({ ok = true })
end)

-- ============================================================
-- AÇÕES (mapa data.action → server event)
-- ============================================================

local MAP = {
  -- moderação
  kick      = E.ACT_KICK,      ban       = E.ACT_BAN,        unban    = E.ACT_UNBAN,
  warn      = E.ACT_WARN,      jail      = E.ACT_JAIL,       unjail   = E.ACT_UNJAIL,
  mute      = E.ACT_MUTE,      unmute    = E.ACT_UNMUTE,
  -- deslocamento
  tp        = E.ACT_TP,        tptome    = E.ACT_TPTOME,     tpgo     = E.ACT_TPGO,
  tpcds     = E.ACT_TPCDS,     tpall     = E.ACT_TPALL,      tplast   = E.ACT_TPLAST,
  tpz       = E.ACT_TPZ,
  -- jogador
  heal      = E.ACT_HEAL,      healall   = E.ACT_HEALALL,    god      = E.ACT_GOD,
  noclip    = E.ACT_NOCLIP,
  freeze    = E.ACT_FREEZE,    revive    = E.ACT_REVIVE,     reviveall= E.ACT_REVIVEALL,
  invis     = E.ACT_INVIS,     kill      = E.ACT_KILL,
  stamina   = E.ACT_STAMINA,   jump      = E.ACT_JUMP,       cleanped = E.ACT_CLEANPED,
  spec      = E.ACT_SPEC,      skin      = E.ACT_SKIN,
  -- veículo/mundo
  spawncar  = E.ACT_SPAWNCAR,  delveh    = E.ACT_DELVEH,     fix      = E.ACT_FIX,
  boost     = E.ACT_BOOST,     flip      = E.ACT_FLIP,       tuning   = E.ACT_TUNING,
  carcolor  = E.ACT_CARCOLOR,
  wipeveh   = E.ACT_WIPE,      wipeped   = E.ACT_WIPE,       wipeobj  = E.ACT_WIPE,
  weather   = E.ACT_WEATHER,   time      = E.ACT_TIME,       blackout = E.ACT_BLACKOUT,
  clearzone = E.ACT_CLEARZONE,
  -- comunicação
  announce  = E.ACT_ANNOUNCE,  staffchat = E.ACT_STAFFCHAT,
  -- economia
  givemoney   = E.ACT_GIVEMONEY, setmoney    = E.ACT_SETMONEY,
  removemoney = E.ACT_REMOVEMONEY,            giveitem = E.ACT_GIVEITEM,
  addgroup  = E.ACT_ADDGROUP,  delgroup  = E.ACT_DELGROUP,
  -- frota persistente
  fleetGive        = E.ACT_FLEET_GIVE,
  fleetTransfer    = E.ACT_FLEET_TRANSFER,
  fleetDelete      = E.ACT_FLEET_DELETE,
  fleetStatus      = E.ACT_FLEET_STATUS,
  fleetIpva        = E.ACT_FLEET_IPVA,
  fleetRelease     = E.ACT_FLEET_RELEASE,
  fleetGrantKey    = E.ACT_FLEET_GRANT_KEY,
  fleetRevokeKey   = E.ACT_FLEET_REVOKE_KEY,
  fleetDespawn     = E.ACT_FLEET_DESPAWN,
  fleetPurgeKeys   = E.ACT_FLEET_PURGE_KEYS,
  fleetPurgeLogs   = E.ACT_FLEET_PURGE_LOGS,
  fleetFinalizeAuctions = E.ACT_FLEET_FINALIZE,
  -- denúncias
  report      = E.ACT_REPORT,
  reportClaim = E.ACT_REPORT_CLAIM,
  reportClose = E.ACT_REPORT_CLOSE,
}

-- '#rrggbb' → r, g, b (0-255)
local function hexToRGB(hex)
  if type(hex) ~= 'string' then return nil end
  local r, g, b = hex:match('^#?(%x%x)(%x%x)(%x%x)$')
  if not r then return nil end
  return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

RegisterNUICallback('act', function(d, cb)
  local key = d and d.action; if not key then return cb({ ok = false }) end
  local ev = MAP[key]; if not ev then return cb({ ok = false }) end
  local f = d.fields or {}
  local target = tonumber(f.target)
  if key == 'kick' or key == 'ban' then
    TriggerServerEvent(ev, target, f.reason)
  elseif key == 'unban' then TriggerServerEvent(ev, tonumber(f.uid))
  elseif key == 'tp'    or key == 'tptome' or key == 'heal'
      or key == 'freeze' or key == 'revive' or key == 'invis'
      or key == 'unjail' or key == 'unmute' or key == 'kill'
      or key == 'spec' then
    TriggerServerEvent(ev, target)
  elseif key == 'warn' then TriggerServerEvent(ev, target, f.message)
  elseif key == 'jail' or key == 'mute' then
    TriggerServerEvent(ev, target, tonumber(f.minutes), f.reason)
  elseif key == 'tpcds' then
    TriggerServerEvent(ev, tonumber(f.x), tonumber(f.y), tonumber(f.z), tonumber(f.h))
  elseif key == 'tpz'      then TriggerServerEvent(ev, tostring(f.zone or ''):lower())
  elseif key == 'spawncar' then TriggerServerEvent(ev, tostring(f.model or ''):lower())
  elseif key == 'carcolor' then
    local r, g, b = hexToRGB(f.color)
    if r then TriggerServerEvent(ev, r, g, b) end
  elseif key == 'wipeveh' then TriggerServerEvent(ev, 'vehicles')
  elseif key == 'wipeped' then TriggerServerEvent(ev, 'peds')
  elseif key == 'wipeobj' then TriggerServerEvent(ev, 'objects')
  elseif key == 'weather' then TriggerServerEvent(ev, f.weather)
  elseif key == 'time'    then TriggerServerEvent(ev, tonumber(f.hour), tonumber(f.minute))
  elseif key == 'blackout' then
    if f.on == nil then TriggerServerEvent(ev) else TriggerServerEvent(ev, f.on == true) end
  elseif key == 'clearzone' then TriggerServerEvent(ev, tonumber(f.radius))
  elseif key == 'announce' or key == 'staffchat' or key == 'report' then
    TriggerServerEvent(ev, f.message)
  elseif key == 'skin' then
    TriggerServerEvent(ev, target, f.model)
  elseif key == 'givemoney' or key == 'setmoney' or key == 'removemoney' then
    TriggerServerEvent(ev, target, tonumber(f.amount), f.rota, f.reason)
  elseif key == 'giveitem' then
    TriggerServerEvent(ev, target, f.item, tonumber(f.qty), f.reason)
  elseif key == 'addgroup' then
    TriggerServerEvent(ev, target, f.group, tonumber(f.level), tonumber(f.days), f.reason)
  elseif key == 'delgroup' then
    TriggerServerEvent(ev, target, f.group, f.reason)
  elseif key == 'reportClaim' or key == 'reportClose' then
    TriggerServerEvent(ev, tonumber(f.id), f.notes)
  elseif key == 'fleetGive' then
    TriggerServerEvent(ev, target, f.model, f.plate)
  elseif key == 'fleetTransfer' then
    TriggerServerEvent(ev, f.plate, target)
  elseif key == 'fleetDelete' or key == 'fleetRelease' or key == 'fleetDespawn'
      or key == 'fleetPurgeKeys' or key == 'fleetFinalizeAuctions' then
    TriggerServerEvent(ev, f.plate)
  elseif key == 'fleetStatus' then
    TriggerServerEvent(ev, f.plate, f.status)
  elseif key == 'fleetIpva' or key == 'fleetPurgeLogs' then
    TriggerServerEvent(ev, f.plate, tonumber(f.days))
  elseif key == 'fleetGrantKey' then
    TriggerServerEvent(ev, f.plate, target, tonumber(f.days))
  elseif key == 'fleetRevokeKey' then
    TriggerServerEvent(ev, f.plate, target)
  else
    TriggerServerEvent(ev)
  end
  cb({ ok = true })
end)
