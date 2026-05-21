-- server/info.lua  /rg /cds /pon /id /pcoords  e listagem de jogadores p/ NUI
---@diagnostic disable: undefined-global

local SQL  = VHubAdmin.SQL
local Core = VHubAdmin.Core
local E    = VHubAdmin.E
local U    = VHubAdmin.U

local function reqPerm(src, k)
  if not Core.hasPerm(src, k) then Core.notify(src, 'Sem permiss o.'); return false end
  return true
end

-- ----------------------------------------------------------------------------
-- /rg ou ACT_REQ_RG  ficha completa do alvo
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REQ_RG)
AddEventHandler(E.REQ_RG, function(target)
  local src = source; if not reqPerm(src, 'rg') then return end
  local t = U.toSrc(target); if not t then return end
  Citizen.CreateThread(function()
    local u = Core:getSession(t)
    local id = Core.getIdentity(t)
    local wallet = Core.getWallet(t)
    local bank   = Core.getBank(t)
    local groups = Core.getGroups(t) or {}
    local glist  = {}
    if type(groups) == 'table' then
      for k, v in pairs(groups) do glist[#glist+1] = type(v) == 'string' and v or k end
    end
    -- ve culos via vhub_garage admin export
    local vehs = {}
    local ok, list = pcall(function()
      return exports.vhub_garage:adminListByOwner(u and u.char_id or 0)
    end)
    if ok and type(list) == 'table' then
      for _, v in ipairs(list) do
        vehs[#vehs+1] = { plate = v.plate, model = v.model, status = v.status }
      end
    end
    local jail = (u and u.char_id) and SQL:jailGet(u.char_id) or nil
    local mute = (u and u.char_id) and SQL:muteGet(u.char_id) or nil
    TriggerClientEvent(E.RG_INFO, src, {
      src         = t,
      uid         = u and u.id or 0,
      char_id     = u and u.char_id or 0,
      name        = GetPlayerName(t) or '?',
      identity    = id,
      wallet      = wallet,
      bank        = bank,
      groups      = glist,
      vehicles    = vehs,
      jail_until  = jail and tonumber(jail.expires_at),
      mute_until  = mute and tonumber(mute.expires_at),
      ping        = GetPlayerPing(t) or 0,
      identifiers = GetPlayerIdentifiers(t),
    })
  end)
end)

-- ----------------------------------------------------------------------------
-- REQ_PLAYERS  lista p/ painel
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REQ_PLAYERS)
AddEventHandler(E.REQ_PLAYERS, function()
  local src = source
  if not Core.hasPerm(src, 'panel') then return end
  local list = Core:listPlayers()
  TriggerClientEvent(E.PLAYER_LIST, src, list)
end)

-- ----------------------------------------------------------------------------
-- REQ_LOGS  auditoria
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REQ_LOGS)
AddEventHandler(E.REQ_LOGS, function(filter, limit)
  local src = source; if not Core.hasPerm(src, 'panel') then return end
  Citizen.CreateThread(function()
    local rows = SQL:listLogs(type(filter) == 'table' and filter or {}, limit)
    TriggerClientEvent(E.LOG_LIST, src, rows)
  end)
end)
