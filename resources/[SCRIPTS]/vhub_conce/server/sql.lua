-- server/sql.lua — repositório do vhub_conce (oxmysql direto, decisão #8)
-- Dono ÚNICO de WRITE em: vhub_vehicles, vhub_vehicle_keys, vhub_dealership_stock
-- e do espelho vh_vehicles (CORE) — pré-requisito da FK que persiste o físico.
-- O schema (DDL) ainda é aplicado pelo vhub_garage até a FASE 6; aqui é só DML.
-- Toda função roda dentro de thread (Citizen.Await).
---@diagnostic disable: undefined-global

local M = {}; VHubConce = VHubConce or {}; VHubConce.SQL = M

local ox = function() return exports['oxmysql'] end


-- ============================================================
-- HELPERS (promise → valor resolvido em thread)
-- ============================================================

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


-- ============================================================
-- ESPELHO vh_vehicles (CORE) — dono único do espelho
-- ============================================================

-- backfill idempotente: toda placa de negócio existe como âncora física no CORE.
-- pcall externo (em init): em DB nova as tabelas podem não existir no boot.
function M:backfillMirror()
  return pexec('INSERT IGNORE INTO vh_vehicles (plate) SELECT plate FROM vhub_vehicles', {})
end


-- ============================================================
-- vhub_vehicles (QUERIES)
-- ============================================================

-- existe linha para a placa?
function M:plateExists(plate)
  return pscalar('SELECT 1 FROM vhub_vehicles WHERE plate = ? LIMIT 1', { plate }) ~= nil
end

-- retorna a linha de negócio do veículo (read-only para o chamador)
function M:getVehicle(plate)
  local r = pquery('SELECT * FROM vhub_vehicles WHERE plate = ? LIMIT 1', { plate })
  return r and r[1] or nil
end

-- veículos cujo dono real é char_id
function M:listByOwner(char_id)
  return pquery('SELECT * FROM vhub_vehicles WHERE char_id = ?', { char_id })
end

-- veículos em um status
function M:listByStatus(status)
  return pquery('SELECT * FROM vhub_vehicles WHERE status = ?', { status })
end


-- ============================================================
-- vhub_vehicles (MUTATIONS)
-- ============================================================

-- cria o registro de negócio + espelha a placa em vh_vehicles (CORE)
function M:createVehicle(row)
  local now = os.time()
  local ok = pexec([[
    INSERT INTO vhub_vehicles
      (plate, model, vtype, category, char_id, status, customization, locked,
       position, ipva_paid_until, rented_until, purchase_price, purchase_at,
       last_seen_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    row.plate, row.model, row.vtype, row.category, row.char_id,
    row.status or 'garage',
    row.customization,
    row.locked and 1 or 0,
    row.position,
    row.ipva_paid_until, row.rented_until,
    row.purchase_price or 0, row.purchase_at or now,
    row.last_seen_at or now, now, now,
  }) ~= nil
  if ok then
    -- espelho legado do CORE (FK de vh_vehicle_data — cadeia inerte, mantido por compat)
    pexec('INSERT IGNORE INTO vh_vehicles (plate) VALUES (?)', { row.plate })
    -- prontuário: linha de fábrica + cosmético inicial (escritor único = VState)
    VHubConce.VState:seed(row.plate, row.customization)
  end
  return ok
end

function M:updateStatus(plate, status)
  return pexec('UPDATE vhub_vehicles SET status = ?, updated_at = ? WHERE plate = ?',
    { status, os.time(), plate })
end

function M:updateOwner(plate, char_id)
  return pexec('UPDATE vhub_vehicles SET char_id = ?, updated_at = ? WHERE plate = ?',
    { char_id, os.time(), plate })
end

function M:updatePosition(plate, posJson)
  return pexec(
    'UPDATE vhub_vehicles SET position = ?, last_seen_at = ?, updated_at = ? WHERE plate = ?',
    { posJson, os.time(), os.time(), plate })
end

-- CONTRATO CONGELADO (plate, custJson, locked): o cosmético migrou para o prontuário
-- (vhub_vehicle_state.customization, sprint PRONTUÁRIO); aqui persiste só o locked
-- (negócio) e redireciona a customization ao escritor único. Coluna legada
-- vhub_vehicles.customization é DEPRECATED — nunca mais lida nem escrita.
function M:updateCustomization(plate, custJson, locked)
  pexec('UPDATE vhub_vehicles SET locked = ?, updated_at = ? WHERE plate = ?',
    { locked and 1 or 0, os.time(), plate })
  if custJson then
    return VHubConce.VState:save(plate, { customization = VHubConce.U.jdec(custJson) }, 'store')
  end
  return true
end

function M:updateIpva(plate, paidUntil)
  return pexec('UPDATE vhub_vehicles SET ipva_paid_until = ?, updated_at = ? WHERE plate = ?',
    { paidUntil, os.time(), plate })
end

function M:updateRental(plate, rentedUntil)
  return pexec('UPDATE vhub_vehicles SET rented_until = ?, updated_at = ? WHERE plate = ?',
    { rentedUntil, os.time(), plate })
end

-- remove prontuário + espelho CORE (FK CASCADE limpa vh_vehicle_data), depois o negócio
function M:deleteVehicle(plate)
  VHubConce.VState:delete(plate)
  pexec('DELETE FROM vh_vehicles WHERE plate = ?', { plate })
  return pexec('DELETE FROM vhub_vehicles WHERE plate = ?', { plate })
end


-- ============================================================
-- vhub_vehicle_keys (autorização lógica; a chave-item física vive no inventory)
-- ============================================================

function M:grantKey(plate, char_id, kind, granted_by, expires_at)
  return pexec([[
    INSERT INTO vhub_vehicle_keys (plate, char_id, kind, granted_by, expires_at, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE granted_by = VALUES(granted_by),
                            expires_at = VALUES(expires_at),
                            created_at = VALUES(created_at)
  ]], { plate, char_id, kind or 'shared', granted_by, expires_at, os.time() })
end

function M:revokeKey(plate, char_id, kind)
  if kind then
    return pexec(
      'DELETE FROM vhub_vehicle_keys WHERE plate = ? AND char_id = ? AND kind = ?',
      { plate, char_id, kind })
  end
  return pexec(
    'DELETE FROM vhub_vehicle_keys WHERE plate = ? AND char_id = ? AND kind != ?',
    { plate, char_id, 'owner' })
end

function M:hasValidKey(plate, char_id)
  local r = pquery([[
    SELECT 1 FROM vhub_vehicle_keys
    WHERE plate = ? AND char_id = ? AND (expires_at IS NULL OR expires_at > ?)
    LIMIT 1
  ]], { plate, char_id, os.time() })
  return r and #r > 0
end

function M:listKeys(plate)
  return pquery('SELECT * FROM vhub_vehicle_keys WHERE plate = ?', { plate })
end

function M:listKeysOfChar(char_id)
  return pquery([[
    SELECT * FROM vhub_vehicle_keys
    WHERE char_id = ? AND (expires_at IS NULL OR expires_at > ?)
  ]], { char_id, os.time() })
end

function M:purgeExpiredKeys()
  return pexec(
    'DELETE FROM vhub_vehicle_keys WHERE expires_at IS NOT NULL AND expires_at < ?',
    { os.time() })
end


-- ============================================================
-- vhub_dealership_stock
-- ============================================================

function M:stockGet(model)
  local r = pquery('SELECT * FROM vhub_dealership_stock WHERE model = ? LIMIT 1', { model })
  return r and r[1] or nil
end

function M:stockSet(model, qty, custom_price)
  return pexec([[
    INSERT INTO vhub_dealership_stock (model, qty, custom_price, updated_at)
    VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE qty = VALUES(qty),
                            custom_price = VALUES(custom_price),
                            updated_at = VALUES(updated_at)
  ]], { model, qty or -1, custom_price, os.time() })
end

function M:stockDecrement(model)
  return pexec([[
    UPDATE vhub_dealership_stock
       SET qty = qty - 1, updated_at = ?
     WHERE model = ? AND qty > 0
  ]], { os.time(), model })
end


-- ============================================================
-- AUXILIARES (contagem + auditoria append-only)
-- ============================================================

-- quantos veículos o char_id possui (limite de compra)
function M:ownedCount(char_id)
  return tonumber(pscalar('SELECT COUNT(*) FROM vhub_vehicles WHERE char_id = ?', { char_id })) or 0
end

-- registra ação no log de auditoria (append-only; payload já em JSON)
function M:log(plate, action, actor_id, payloadJson)
  pexec([[
    INSERT INTO vhub_vehicle_log (plate, action, actor_id, payload, created_at)
    VALUES (?, ?, ?, ?, ?)
  ]], { plate, action, actor_id, payloadJson, os.time() })
end


-- ============================================================
-- FASE 3 — backfill de chave 'owner' + varredura de posse temporária
-- ============================================================

-- garante linha 'owner' para todo dono atual (idempotente; pré-req da pura-chave)
function M:backfillOwnerKeys()
  return pexec([[
    INSERT IGNORE INTO vhub_vehicle_keys (plate, char_id, kind, granted_by, expires_at, created_at)
    SELECT plate, char_id, 'owner', char_id, NULL, ?
      FROM vhub_vehicles WHERE char_id IS NOT NULL
  ]], { os.time() })
end

-- chaves NÃO-dono vencidas: expires passou, OU clone sem expires com 24h+ de posse
function M:listExpiredTempKeys(now, ttl)
  return pquery([[
    SELECT plate, char_id, kind FROM vhub_vehicle_keys
    WHERE kind IN ('clone','shared','rental')
      AND ( (expires_at IS NOT NULL AND expires_at < ?)
         OR (expires_at IS NULL AND created_at < ?) )
  ]], { now, now - (ttl or 86400) })
end
