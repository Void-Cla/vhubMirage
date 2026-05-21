-- server/sql.lua  reposit rio centralizado (4 tabelas: log/jail/mute/reports)
---@diagnostic disable: undefined-global

local M = {}; VHubAdmin = VHubAdmin or {}; VHubAdmin.SQL = M
local ox = function() return exports['oxmysql'] end

local function pscalar(sql, args)
  local p = promise.new()
  ox():scalar(sql, args or {}, function(r) p:resolve(r) end)
  return Citizen.Await(p)
end
local function pexec(sql, args)
  local p = promise.new()
  ox():execute(sql, args or {}, function(r) p:resolve(r) end)
  return Citizen.Await(p)
end
local function pquery(sql, args)
  local p = promise.new()
  ox():query(sql, args or {}, function(r) p:resolve(r or {}) end)
  return Citizen.Await(p)
end

M.scalar  = pscalar
M.execute = pexec
M.query   = pquery

function M:initSchema()
  local s = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if not s then return false end
  local p = promise.new()
  ox():execute(s, {}, function() p:resolve(true) end)
  return Citizen.Await(p)
end

-- ----------------------------------------------------------------------------
-- Log
-- ----------------------------------------------------------------------------
function M:log(row)
  pexec([[
    INSERT INTO vhub_admin_log
      (actor_id, actor_name, action, target_id, target_src, payload, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], { row.actor_id, row.actor_name, row.action,
        row.target_id, row.target_src, row.payload, os.time() })
end

function M:listLogs(filter, limit)
  filter = filter or {}
  limit  = math.min(tonumber(limit) or 100, 500)
  local where, args = {}, {}
  if filter.actor_id  then where[#where+1] = 'actor_id = ?';  args[#args+1] = filter.actor_id end
  if filter.target_id then where[#where+1] = 'target_id = ?'; args[#args+1] = filter.target_id end
  if filter.action    then where[#where+1] = 'action = ?';    args[#args+1] = filter.action end
  local clause = #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''
  args[#args+1] = limit
  return pquery('SELECT * FROM vhub_admin_log' .. clause ..
                ' ORDER BY id DESC LIMIT ?', args)
end

-- ----------------------------------------------------------------------------
-- Jail
-- ----------------------------------------------------------------------------
function M:jailGet(char_id)
  local r = pquery('SELECT * FROM vhub_admin_jail WHERE char_id = ? LIMIT 1', { char_id })
  return r and r[1] or nil
end

function M:jailPut(char_id, expires_at, reason, jailer_id)
  return pexec([[
    INSERT INTO vhub_admin_jail (char_id, expires_at, reason, jailer_id, created_at)
    VALUES (?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at),
                            reason     = VALUES(reason),
                            jailer_id  = VALUES(jailer_id),
                            created_at = VALUES(created_at)
  ]], { char_id, expires_at, reason, jailer_id, os.time() })
end

function M:jailRemove(char_id)
  return pexec('DELETE FROM vhub_admin_jail WHERE char_id = ?', { char_id })
end

function M:jailListExpired()
  return pquery(
    'SELECT char_id FROM vhub_admin_jail WHERE expires_at <= ?', { os.time() })
end

-- ----------------------------------------------------------------------------
-- Mute
-- ----------------------------------------------------------------------------
function M:muteGet(char_id)
  local r = pquery('SELECT * FROM vhub_admin_mute WHERE char_id = ? LIMIT 1', { char_id })
  return r and r[1] or nil
end

function M:mutePut(char_id, expires_at, reason, muter_id)
  return pexec([[
    INSERT INTO vhub_admin_mute (char_id, expires_at, reason, muter_id, created_at)
    VALUES (?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at),
                            reason     = VALUES(reason),
                            muter_id   = VALUES(muter_id),
                            created_at = VALUES(created_at)
  ]], { char_id, expires_at, reason, muter_id, os.time() })
end

function M:muteRemove(char_id)
  return pexec('DELETE FROM vhub_admin_mute WHERE char_id = ?', { char_id })
end

function M:muteListExpired()
  return pquery(
    'SELECT char_id FROM vhub_admin_mute WHERE expires_at <= ?', { os.time() })
end

-- ----------------------------------------------------------------------------
-- Reports
-- ----------------------------------------------------------------------------
function M:reportCreate(reporter_id, reporter_src, message)
  local p = promise.new()
  ox():insert([[
    INSERT INTO vhub_admin_reports (reporter_id, reporter_src, message, status, created_at)
    VALUES (?, ?, ?, 'open', ?)
  ]], { reporter_id, reporter_src, message, os.time() }, function(id) p:resolve(id) end)
  return Citizen.Await(p)
end

function M:reportList(status)
  local sql = 'SELECT * FROM vhub_admin_reports'
  local args = {}
  if status then sql = sql .. ' WHERE status = ?'; args = { status } end
  sql = sql .. ' ORDER BY id DESC LIMIT 200'
  return pquery(sql, args)
end

function M:reportClaim(id, admin_id)
  return pexec([[
    UPDATE vhub_admin_reports
       SET status='claimed', claimed_by=?, claimed_at=?
     WHERE id=? AND status='open'
  ]], { admin_id, os.time(), id })
end

function M:reportClose(id, admin_id, notes)
  return pexec([[
    UPDATE vhub_admin_reports
       SET status='closed', closed_by=?, closed_at=?, notes=?
     WHERE id=?
  ]], { admin_id, os.time(), notes, id })
end

function M:reportLastByReporter(reporter_id)
  local r = pquery([[
    SELECT created_at FROM vhub_admin_reports
     WHERE reporter_id = ?
     ORDER BY id DESC LIMIT 1
  ]], { reporter_id })
  return r and r[1] and tonumber(r[1].created_at) or 0
end
