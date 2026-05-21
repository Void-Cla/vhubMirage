-- client/ui.lua  NUI callbacks (roteamento de eventos do painel para o server)
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

-- ----------------------------------------------------------------------------
-- Listas (servidor   NUI)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- Pedidos NUI   server
-- ----------------------------------------------------------------------------
RegisterNUICallback('reqPlayers', function(_, cb)
  TriggerServerEvent(E.REQ_PLAYERS); cb({ ok = true })
end)

RegisterNUICallback('reqRG', function(d, cb)
  TriggerServerEvent(E.REQ_RG, tonumber(d.target)); cb({ ok = true })
end)

RegisterNUICallback('reqLogs', function(d, cb)
  TriggerServerEvent(E.REQ_LOGS, d.filter or {}, tonumber(d.limit) or 100); cb({ ok = true })
end)

RegisterNUICallback('reqReports', function(_, cb)
  TriggerServerEvent(E.REQ_REPORTS); cb({ ok = true })
end)

-- ----------------------------------------------------------------------------
-- A  es (mapa data.action   server event)
-- ----------------------------------------------------------------------------
local MAP = {
  kick      = E.ACT_KICK,      ban       = E.ACT_BAN,        unban    = E.ACT_UNBAN,
  whitelist = E.ACT_WL,        unwl      = E.ACT_UNWL,       warn     = E.ACT_WARN,
  jail      = E.ACT_JAIL,      unjail    = E.ACT_UNJAIL,     mute     = E.ACT_MUTE,
  unmute    = E.ACT_UNMUTE,
  tp        = E.ACT_TP,        tptome    = E.ACT_TPTOME,     tpgo     = E.ACT_TPGO,
  tpcds     = E.ACT_TPCDS,     tpall     = E.ACT_TPALL,      tplast   = E.ACT_TPLAST,
  heal      = E.ACT_HEAL,      healall   = E.ACT_HEALALL,    god      = E.ACT_GOD,
  freeze    = E.ACT_FREEZE,    revive    = E.ACT_REVIVE,     reviveall= E.ACT_REVIVEALL,
  invis     = E.ACT_INVIS,     skin      = E.ACT_SKIN,       kill     = E.ACT_KILL,
  spec      = E.ACT_SPEC,
  spawncar  = E.ACT_SPAWNCAR,  delveh    = E.ACT_DELVEH,     fix      = E.ACT_FIX,
  tuning    = E.ACT_TUNING,    carcolor  = E.ACT_CARCOLOR,
  weather   = E.ACT_WEATHER,   time      = E.ACT_TIME,       blackout = E.ACT_BLACKOUT,
  clearzone = E.ACT_CLEARZONE, announce  = E.ACT_ANNOUNCE,   staffchat= E.ACT_STAFFCHAT,
  givemoney = E.ACT_GIVEMONEY, setmoney  = E.ACT_SETMONEY,   giveitem = E.ACT_GIVEITEM,
  clearinv  = E.ACT_CLEARINV,  addgroup  = E.ACT_ADDGROUP,   delgroup = E.ACT_DELGROUP,
  reportClaim = E.ACT_REPORT_CLAIM, reportClose = E.ACT_REPORT_CLOSE,
  report    = E.ACT_REPORT,
}

RegisterNUICallback('act', function(d, cb)
  local key = d and d.action; if not key then return cb({ ok = false }) end
  local ev = MAP[key]; if not ev then return cb({ ok = false }) end
  -- normaliza payload  campos posicionais
  local f = d.fields or {}
  local target = tonumber(f.target)
  if key == 'kick' or key == 'ban' then
    TriggerServerEvent(ev, target, f.reason)
  elseif key == 'unban' then TriggerServerEvent(ev, tonumber(f.uid))
  elseif key == 'whitelist' or key == 'unwl' or key == 'tp' or key == 'tptome'
      or key == 'heal'      or key == 'freeze' or key == 'revive' or key == 'invis'
      or key == 'unjail'    or key == 'unmute' or key == 'kill'
      or key == 'spec'      or key == 'clearinv' then
    TriggerServerEvent(ev, target)
  elseif key == 'warn' then TriggerServerEvent(ev, target, f.message)
  elseif key == 'jail' or key == 'mute' then
    TriggerServerEvent(ev, target, tonumber(f.minutes), f.reason)
  elseif key == 'tpcds' then
    TriggerServerEvent(ev, tonumber(f.x), tonumber(f.y), tonumber(f.z), tonumber(f.h))
  elseif key == 'skin'    then TriggerServerEvent(ev, target, f.model)
  elseif key == 'spawncar' then TriggerServerEvent(ev, f.model)
  elseif key == 'carcolor' then TriggerServerEvent(ev, tonumber(f.r), tonumber(f.g), tonumber(f.b))
  elseif key == 'weather'  then TriggerServerEvent(ev, f.wx)
  elseif key == 'time'     then TriggerServerEvent(ev, tonumber(f.hour), tonumber(f.minute))
  elseif key == 'blackout' then TriggerServerEvent(ev, f.on == true)
  elseif key == 'clearzone' then TriggerServerEvent(ev, tonumber(f.radius))
  elseif key == 'announce' or key == 'staffchat' or key == 'report' then
    TriggerServerEvent(ev, f.message)
  elseif key == 'givemoney' or key == 'setmoney' then
    TriggerServerEvent(ev, target, tonumber(f.amount), f.rota)
  elseif key == 'giveitem' then TriggerServerEvent(ev, target, f.item, tonumber(f.qty))
  elseif key == 'addgroup' or key == 'delgroup' then TriggerServerEvent(ev, target, f.group)
  elseif key == 'reportClaim' or key == 'reportClose' then
    TriggerServerEvent(ev, tonumber(f.id), f.notes)
  else
    TriggerServerEvent(ev)   -- a  o sem campos
  end
  cb({ ok = true })
end)
