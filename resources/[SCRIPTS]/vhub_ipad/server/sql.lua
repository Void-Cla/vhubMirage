---@diagnostic disable: undefined-global, lowercase-global

-- server/sql.lua — toda query do vhub_ipad (exports.oxmysql direto, decisão #8).
-- Resources externos NÃO usam S:prepare()/S:query() do core. Funções usam Await,
-- então só rodam dentro de Citizen.CreateThread.

VHubIpad = VHubIpad or {}

local M = {}; VHubIpad.SQL = M

local function ox() return exports['oxmysql'] end


-- ============================================================
-- WRAPPERS (Promise resolvida em thread)
-- ============================================================

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


-- ============================================================
-- SCHEMA
-- ============================================================

-- aplica sql/schema.sql (idempotente) no boot
function M:initSchema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if not schema then return false end
  local p = promise.new()
  ox():execute(schema, {}, function() p:resolve(true) end)
  return Citizen.Await(p)
end


-- ============================================================
-- ESTADO POR PERSONAGEM (vhub_ipad_state)
-- ============================================================

-- carrega o estado do personagem; retorna (installed[], prefs{}) ou (nil, nil) sem registro
function M:loadState(char_id)
  local r = pquery('SELECT installed, prefs FROM vhub_ipad_state WHERE char_id = ? LIMIT 1', { char_id })
  local row = r and r[1]
  if not row then return nil, nil end

  local installed, prefs
  if row.installed then
    local ok, dec = pcall(json.decode, row.installed)
    if ok and type(dec) == 'table' then installed = dec end
  end
  if row.prefs then
    local ok, dec = pcall(json.decode, row.prefs)
    if ok and type(dec) == 'table' then prefs = dec end
  end
  return installed, prefs
end

-- grava (upsert) o estado do personagem — write-through do cache VRAM
function M:saveState(char_id, installed, prefs)
  pexec([[
    INSERT INTO vhub_ipad_state (char_id, installed, prefs, updated_at)
      VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      installed = VALUES(installed), prefs = VALUES(prefs), updated_at = VALUES(updated_at)
  ]], { char_id, json.encode(installed or {}), json.encode(prefs or {}), os.time() })
end
