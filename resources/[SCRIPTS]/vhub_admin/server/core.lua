-- server/core.lua  helpers compartilhados (perms, sessions, audit, exports proxy)
---@diagnostic disable: undefined-global

local SQL = VHubAdmin.SQL
local CFG = VHubAdmin.cfg
local U   = VHubAdmin.U

local M = {}; VHubAdmin.Core = M

-- ----------------------------------------------------------------------------
-- vHub core handle (lazy)
-- ----------------------------------------------------------------------------
M._vHub = nil
function M:vHub()
  if self._vHub then return self._vHub end
  local ok, vh = pcall(function() return exports.vhub:getVHub() end)
  if ok then self._vHub = vh end
  return self._vHub
end

-- ----------------------------------------------------------------------------
-- Permiss es: uid=1   ACE   vhub_groups
-- ----------------------------------------------------------------------------
function M.hasPerm(src, key)
  src = tonumber(src); if not src then return false end
  local perm = CFG.perms[key] or key
  -- uid=1 (owner principal) sempre passa
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  if ok and uid == 1 then return true end
  -- ACE
  if IsPlayerAceAllowed and IsPlayerAceAllowed(src, 'vhub.' .. perm) then return true end
  -- vhub_groups
  local ok2, r = pcall(function() return exports.vhub_groups:hasPermission(src, perm) end)
  return ok2 and r == true
end

-- exposi  o para client (atualiza state bag de admin)
function M:syncAdminBag(src)
  local is = self.hasPerm(src, 'panel')
  Player(src).state:set('vhub_is_admin', is, true)
end

-- ----------------------------------------------------------------------------
-- Sess es
-- ----------------------------------------------------------------------------
M.sessions = {}        -- [src] = user (vivo)
M.adminIds = {}        -- [src] = true (admins online   p/ staff chat)

function M:setSession(src, user)
  self.sessions[src] = user
  if user and self.hasPerm(src, 'panel') then self.adminIds[src] = true end
end

function M:dropSession(src)
  self.sessions[src] = nil
  self.adminIds[src] = nil
end

function M:getSession(src) return self.sessions[tonumber(src)] end
function M:getUid(src)   local u = self:getSession(src); return u and u.id end
function M:getCharId(src) local u = self:getSession(src); return u and u.char_id end

-- ----------------------------------------------------------------------------
-- Auditoria: console + SQL log + (opcional) webhook
-- ----------------------------------------------------------------------------
function M:audit(actor_src, action, target_src, payload)
  local actor_id   = self:getUid(actor_src)
  local actor_user = self:getSession(actor_src)
  local actor_name = actor_user and actor_user.name or 'console'
  local target_id  = target_src and self:getUid(target_src)

  print(('[ADMIN] %s uid=%s alvo=%s   %s')
    :format(action, tostring(actor_id or 'c'), tostring(target_id or '-'),
            U.jenc(payload) or ''))

  SQL:log{
    actor_id   = actor_id,
    actor_name = actor_name,
    action     = action,
    target_id  = target_id,
    target_src = target_src,
    payload    = U.jenc(payload),
  }

  if CFG.webhook.enabled and CFG.webhook.url and CFG.webhook.url ~= '' then
    self:sendWebhook(action, actor_name, target_id, payload)
  end
end

function M:sendWebhook(action, actor_name, target_id, payload)
  local body = {
    embeds = { {
      title       = ('[ADMIN] %s'):format(action),
      description = ('Por **%s**   Alvo: `%s`\n```%s```')
                      :format(actor_name or '?', tostring(target_id or '-'),
                              U.jenc(payload) or ''),
      color       = 0xB15BFF,
      timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    } },
  }
  PerformHttpRequest(CFG.webhook.url, function() end, 'POST',
    json.encode(body), { ['Content-Type'] = 'application/json' })
end

-- ----------------------------------------------------------------------------
-- Notifica  o
-- ----------------------------------------------------------------------------
function M.notify(src, msg)
  if src and tonumber(src) > 0 then
    TriggerClientEvent(VHubAdmin.E.NOTIFY, tonumber(src), tostring(msg or ''))
  end
end

-- ----------------------------------------------------------------------------
-- Helpers cross-resource (pcall safe)
-- ----------------------------------------------------------------------------
local function safe(fn) local ok, r = pcall(fn); return ok and r or nil end

function M.getIdentity(src)
  return safe(function() return exports.vhub_identity:getIdentity(src) end)
end

function M.getFullName(src)
  return safe(function() return exports.vhub_identity:getFullName(src) end)
end

function M.getWallet(src)
  return tonumber(safe(function() return exports.vhub_money:getWallet(src) end)) or 0
end

function M.getBank(src)
  return tonumber(safe(function() return exports.vhub_money:getBank(src) end)) or 0
end

function M.giveWallet(src, v) safe(function() exports.vhub_money:giveWallet(src, v) end) end
function M.giveBank(src, v)   safe(function() exports.vhub_money:giveBank(src, v) end) end
function M.setWallet(src, v)  safe(function() exports.vhub_money:setWallet(src, v) end) end
function M.setBank(src, v)    safe(function() exports.vhub_money:setBank(src, v) end) end

function M.giveItem(src, item, qty) return safe(function() return exports.vhub_inventory:giveItem(src, item, qty) end) end

function M.addGroup(src, g)    safe(function() exports.vhub_groups:addGroup(src, g) end) end
function M.removeGroup(src, g) safe(function() exports.vhub_groups:removeGroup(src, g) end) end
function M.getGroups(src)
  return safe(function() return exports.vhub_groups:getGroups(src) end) or {}
end

-- coords server-side do ped do src (sem roundtrip cliente)
function M.coordsOf(src)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  return GetEntityCoords(ped)
end

-- iter admins online
function M:eachAdmin(fn)
  for s, _ in pairs(self.adminIds) do fn(s) end
end

-- listagem de jogadores (cache 3s)
M._players_cache = { ts = 0, data = nil }
function M:listPlayers()
  local now = GetGameTimer()
  if self._players_cache.data and (now - self._players_cache.ts) < 3000 then
    return self._players_cache.data
  end
  local out = {}
  for _, s in ipairs(GetPlayers()) do
    s = tonumber(s)
    local u = self.sessions[s]
    local groups = self.getGroups(s) or {}
    local glist = {}
    if type(groups) == 'table' then
      for k, v in pairs(groups) do glist[#glist+1] = type(v) == 'string' and v or k end
    end
    out[#out+1] = {
      src    = s,
      uid    = u and u.id or 0,
      char   = u and u.char_id or 0,
      name   = GetPlayerName(s) or '?',
      ping   = GetPlayerPing(s) or 0,
      groups = glist,
    }
    if #out >= CFG.list_caps.players then break end
  end
  self._players_cache.ts = now
  self._players_cache.data = out
  return out
end
