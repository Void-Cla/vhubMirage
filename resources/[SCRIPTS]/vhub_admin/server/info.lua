-- server/info.lua - leituras administrativas agregadas, sem verdade paralela
---@diagnostic disable: undefined-global

local SQL = VHubAdmin.SQL
local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E
local U = VHubAdmin.U

local dashboardCache = { at = 0, data = nil }
local wallEnabled = {}
local wallRevision = {}

local function groupsFor(src)
  local out = {}
  for groupId, data in pairs(Core:getGroups(src)) do
    local id = U.identifier(groupId, 48)
    if id then
      out[#out + 1] = {
        id = id,
        level = type(data) == 'table' and math.floor(tonumber(data.level) or 1) or 1,
      }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

local function identityFor(src)
  local raw = Core:getIdentity(src)
  if type(raw) ~= 'table' then return {} end
  return {
    firstname    = U.safeText(raw.firstname, 48),
    lastname     = U.safeText(raw.lastname, 48),
    age          = math.floor(U.number(raw.age, 0, 150) or 0),
    registration = U.safeText(raw.registration, 32),
    phone        = U.safeText(raw.phone, 24),
  }
end

local function vehiclesFor(charId)
  local out = {}
  local ok, rows = pcall(function() return exports.vhub_garage:adminListByOwner(charId) end)
  if not ok or type(rows) ~= 'table' then return out end
  for _, row in ipairs(rows) do
    if #out >= CFG.limits.fleet_page then break end
    out[#out + 1] = {
      plate = U.plate(row.plate) or '?',
      model = U.identifier(row.model, 64) or '?',
      status = U.identifier(row.status, 24) or '?',
    }
  end
  return out
end

local function transactionsFor(charId)
  local out = {}
  local ok, rows = pcall(function() return exports.vhub_money:getTransactions(charId, 20) end)
  if not ok or type(rows) ~= 'table' then return out end
  for _, row in ipairs(rows) do
    if #out >= 20 then break end
    out[#out + 1] = {
      kind = U.safeText(row.kind or row.tipo or row.action or '?', 32),
      amount = U.number(row.amount or row.valor, -CFG.limits.money_max, CFG.limits.money_max) or 0,
      reason = U.safeText(row.reason or row.motivo or '', 120),
      created_at = U.safeText(tostring(row.created_at or row.ts or ''), 32),
    }
  end
  return out
end

local function wallSnapshot(viewer)
  local origin = Core:coordsOf(viewer)
  if not origin then return {} end

  local out = {}
  local maxDistance = CFG.wall.server_distance
  local maxDistanceSquared = maxDistance * maxDistance
  local viewerBucket = GetPlayerRoutingBucket(viewer)
  local scanned = 0

  for _, raw in ipairs(GetPlayers()) do
    scanned = scanned + 1
    local target = tonumber(raw)
    if GetPlayerRoutingBucket(target) == viewerBucket then
      local charId = Core:getCharId(target)
      local coords = charId and Core:coordsOf(target) or nil
      if coords then
        local dx, dy, dz = coords.x - origin.x, coords.y - origin.y, coords.z - origin.z
        if dx * dx + dy * dy + dz * dz <= maxDistanceSquared then
          local identity = identityFor(target)
          local wallet, bank = Core:getBalances(target)
          out[#out + 1] = {
            src = target,
            uid = Core:getUid(target) or 0,
            char_id = charId,
            player_name = U.safeText(GetPlayerName(target) or '?', 64),
            char_name = U.safeText(('%s %s'):format(
              identity.firstname or '', identity.lastname or ''):gsub('^%s*(.-)%s*$', '%1'), 100),
            registration = identity.registration or '',
            wallet = wallet,
            bank = bank,
            groups = groupsFor(target),
          }
          if #out >= CFG.wall.max_players then break end
        end
      end
    end

    if scanned % 32 == 0 then Citizen.Wait(0) end
  end

  table.sort(out, function(a, b) return a.src < b.src end)
  return out
end

local function sendWallSnapshot(src, revision, includeState)
  if wallEnabled[src] ~= revision or not Core.hasPerm(src, 'rg') then return end
  local rows = wallSnapshot(src)
  if wallEnabled[src] ~= revision or not Core.hasPerm(src, 'rg') then return end
  if includeState then
    TriggerClientEvent(E.WALL_STATE, src, true, rows)
  else
    TriggerClientEvent(E.WALL_SNAPSHOT, src, rows)
  end
end


-- ============================================================
-- PERFIL E LISTAS
-- ============================================================

RegisterNetEvent(E.REQ_PROFILE)
AddEventHandler(E.REQ_PROFILE, function(rawTarget)
  local src = source
  if not Core:guard(src, 'rg', 'profile') then return end

  local target = Core:onlineTarget(rawTarget)
  if not target then return Core:notify(src, 'Alvo indisponivel.', 'erro') end

  Citizen.CreateThread(function()
    local session = Core:getSession(target)
    local charId = session and tonumber(session.char_id) or nil
    if not charId then return end

    local wallet, bank = Core:getBalances(target)
    local jail = SQL:jailGet(charId)
    local mute = SQL:muteGet(charId)
    TriggerClientEvent(E.PROFILE, src, {
      src = target,
      uid = tonumber(session.id) or 0,
      char_id = charId,
      name = U.safeText(GetPlayerName(target) or '?', 64),
      identity = identityFor(target),
      coords = Core:coordsOf(target),
      wallet = wallet,
      bank = bank,
      groups = groupsFor(target),
      vehicles = vehiclesFor(charId),
      transactions = transactionsFor(charId),
      jail_until = jail and tonumber(jail.expires_at) or nil,
      mute_until = mute and tonumber(mute.expires_at) or nil,
      ping = math.max(0, tonumber(GetPlayerPing(target)) or 0),
    })
  end)
end)

RegisterNetEvent(E.REQ_PLAYERS)
AddEventHandler(E.REQ_PLAYERS, function()
  local src = source
  if not Core:guard(src, 'panel', 'players') then return end
  TriggerClientEvent(E.PLAYER_LIST, src, Core:listPlayers())
end)

RegisterNetEvent(E.REQ_WALL_TOGGLE)
AddEventHandler(E.REQ_WALL_TOGGLE, function()
  local src = source
  if not Core:guard(src, 'rg', 'wall_toggle') then return end

  wallRevision[src] = (wallRevision[src] or 0) + 1
  local revision = wallRevision[src]
  if wallEnabled[src] then
    wallEnabled[src] = nil
    TriggerClientEvent(E.WALL_STATE, src, false, {})
    return
  end
  wallEnabled[src] = revision

  Citizen.CreateThread(function()
    sendWallSnapshot(src, revision, true)
  end)
end)

RegisterNetEvent(E.REQ_WALL_SNAPSHOT)
AddEventHandler(E.REQ_WALL_SNAPSHOT, function()
  local src = source
  if not wallEnabled[src] then return end
  if not Core.hasPerm(src, 'rg') then
    wallEnabled[src] = nil
    TriggerClientEvent(E.WALL_STATE, src, false, {})
    return
  end
  if not Core:rate(src, 'wall_snapshot') then return end
  local revision = wallEnabled[src]

  Citizen.CreateThread(function()
    sendWallSnapshot(src, revision, false)
  end)
end)

AddEventHandler('playerDropped', function()
  wallEnabled[source] = nil
  wallRevision[source] = nil
end)


-- ============================================================
-- DASHBOARD E AUDITORIA
-- ============================================================

local function dashboard()
  local now = GetGameTimer()
  if dashboardCache.data and now - dashboardCache.at < 1000 then return dashboardCache.data end
  dashboardCache = { at = now, data = Core:dashboard() }
  return dashboardCache.data
end

RegisterNetEvent(E.REQ_DASHBOARD)
AddEventHandler(E.REQ_DASHBOARD, function()
  local src = source
  if not Core:guard(src, 'panel', 'dashboard') then return end
  Citizen.CreateThread(function()
    TriggerClientEvent(E.DASHBOARD, src, dashboard())
  end)
end)

RegisterNetEvent(E.REQ_LOGS)
AddEventHandler(E.REQ_LOGS, function(rawFilter, rawLimit)
  local src = source
  if not Core:guard(src, 'logs', 'logs') then return end

  local input = type(rawFilter) == 'table' and rawFilter or {}
  local filter = {}
  local actorId = U.number(input.actor_id, 1, 2147483647)
  local targetId = U.number(input.target_id, 1, 2147483647)
  local action = U.identifier(input.action, 48)
  if actorId and actorId % 1 == 0 then filter.actor_id = math.floor(actorId) end
  if targetId and targetId % 1 == 0 then filter.target_id = math.floor(targetId) end
  if action then filter.action = action end
  local limit = U.number(rawLimit, 1, CFG.limits.logs) or 100

  Citizen.CreateThread(function()
    TriggerClientEvent(E.LOG_LIST, src, SQL:listLogs(filter, math.floor(limit)) or {})
  end)
end)
