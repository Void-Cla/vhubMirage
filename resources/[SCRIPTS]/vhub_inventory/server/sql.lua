---@diagnostic disable: undefined-global, lowercase-global

-- server/sql.lua — toda query SQL vive aqui (exports.oxmysql direto, decisao #8).
-- Resources externos NAO usam S:prepare()/S:query() do core. Funcoes usam Await,
-- entao SO podem ser chamadas dentro de Citizen.CreateThread.

local M = {}; Inventory.SQL = M

local ox = function() return exports['oxmysql'] end


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

M.execute = pexec
M.query   = pquery


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
-- MOCHILA (vhub_inv_player)
-- ============================================================

-- carrega o personagem; retorna (slots, hotbar) — ou (nil, nil) sem registro
function M:loadPlayer(char_id)
  local r = pquery('SELECT data FROM vhub_inv_player WHERE char_id = ? LIMIT 1', { char_id })
  if r and r[1] and r[1].data then
    local ok, decoded = pcall(json.decode, r[1].data)
    if ok and type(decoded) == 'table' then return decoded.slots or {}, decoded.hotbar end
  end
  return nil, nil
end

-- grava slots + hotbar do personagem (upsert) — write-through do cache
function M:savePlayer(char_id, slots, hotbar)
  local data = json.encode({ slots = slots or {}, hotbar = hotbar or {} })
  pexec([[
    INSERT INTO vhub_inv_player (char_id, data) VALUES (?, ?)
    ON DUPLICATE KEY UPDATE data = VALUES(data)
  ]], { char_id, data })
end


-- ============================================================
-- BAUS (vhub_inv_containers) — usado a partir do SPRINT-INV-2
-- ============================================================

-- carrega um container; retorna { slots, capacity, kind, owner } ou nil
function M:loadContainer(container_id)
  local r = pquery('SELECT * FROM vhub_inv_containers WHERE container_id = ? LIMIT 1', { container_id })
  local row = r and r[1]
  if not row then return nil end
  local ok, decoded = pcall(json.decode, row.data or '{}')
  return {
    slots    = (ok and type(decoded) == 'table' and decoded.slots) or {},
    capacity = row.capacity,
    kind     = row.kind,
    owner    = row.owner,
  }
end

-- grava um container (upsert)
function M:saveContainer(container_id, kind, owner, slots, capacity)
  local data = json.encode({ slots = slots or {} })
  pexec([[
    INSERT INTO vhub_inv_containers (container_id, kind, owner, data, capacity)
      VALUES (?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE data = VALUES(data), capacity = VALUES(capacity)
  ]], { container_id, kind, owner, data, capacity or 100 })
end

-- remove um container (cleanup de orfaos / trunk deletado)
function M:deleteContainer(container_id)
  pexec('DELETE FROM vhub_inv_containers WHERE container_id = ?', { container_id })
end


-- ============================================================
-- MOCHILA F2 — double-track (v1=LONGTEXT, v2=BLOB+revision)
-- ============================================================

-- lê slots+hotbar pelo melhor track disponível (v2 tem precedência sobre v1)
function M:loadPlayerRevision(char_id)
  local r = pquery([[
    SELECT data, payload, schema_version, revision
    FROM vhub_inv_player WHERE char_id = ? LIMIT 1
  ]], { char_id })
  local row = r and r[1]
  if not row then return nil, nil, 0 end

  -- v2: payload BLOB (schema_version >= 2 OU payload presente)
  if row.payload and #tostring(row.payload) > 0 then
    local ok, decoded = pcall(json.decode, tostring(row.payload))
    if ok and type(decoded) == 'table' then
      return decoded.slots or {}, decoded.hotbar, tonumber(row.revision) or 0
    end
  end

  -- v1: data LONGTEXT (fallback)
  if row.data and #row.data > 0 then
    local ok, decoded = pcall(json.decode, row.data)
    if ok and type(decoded) == 'table' then
      return decoded.slots or {}, decoded.hotbar, tonumber(row.revision) or 0
    end
  end

  return nil, nil, 0
end

-- grava com revision e payload BLOB; mantém coluna data em sincronia (dupla escrita)
function M:savePlayerRevision(char_id, slots, hotbar, revision)
  local body    = json.encode({ slots = slots or {}, hotbar = hotbar or {} })
  local payload = body   -- BLOB recebe o mesmo JSON; v3 pode mudar para msgpack
  pexec([[
    INSERT INTO vhub_inv_player (char_id, data, payload, revision, schema_version)
      VALUES (?, ?, ?, ?, 2)
    ON DUPLICATE KEY UPDATE
      data           = VALUES(data),
      payload        = VALUES(payload),
      revision       = VALUES(revision),
      schema_version = 2
  ]], { char_id, body, payload, revision })
end
