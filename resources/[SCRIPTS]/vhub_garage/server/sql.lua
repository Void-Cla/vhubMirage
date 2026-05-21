-- server/sql.lua  reposit rio centralizado (todas as queries SQL vivem aqui)
-- Resources externos N O usam S:prepare()/S:query() do core  decis o congelada em contexto.md.
-- Usamos exports.oxmysql diretamente. Toda fun  o pode ser chamada dentro de thread (Citizen.Await).
---@diagnostic disable: undefined-global

local M = {}; VHubGarage = VHubGarage or {}; VHubGarage.SQL = M

local ox = function() return exports['oxmysql'] end

-- helpers que devolvem Promise resolvida em thread ---------------------------
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

-- ----------------------------------------------------------------------------
-- Inicializa o schema (cria tabelas se n o existirem)
-- ----------------------------------------------------------------------------
function M:initSchema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if not schema then return false end
  local p = promise.new()
  ox():execute(schema, {}, function() p:resolve(true) end)
  return Citizen.Await(p)
end

-- ----------------------------------------------------------------------------
-- vhub_vehicles
-- ----------------------------------------------------------------------------
function M:plateExists(plate)
  return pscalar('SELECT 1 FROM vhub_vehicles WHERE plate = ? LIMIT 1', { plate }) ~= nil
end

function M:getVehicle(plate)
  local r = pquery('SELECT * FROM vhub_vehicles WHERE plate = ? LIMIT 1', { plate })
  return r and r[1] or nil
end

function M:listByOwner(char_id)
  return pquery('SELECT * FROM vhub_vehicles WHERE char_id = ?', { char_id })
end

function M:listByStatus(status)
  return pquery('SELECT * FROM vhub_vehicles WHERE status = ?', { status })
end

-- cria registro inicial (compra)  retorna true/false
function M:createVehicle(row)
  local now = os.time()
  return pexec([[
    INSERT INTO vhub_vehicles
      (plate, model, vtype, category, char_id, status, customization, locked,
       position, ipva_paid_until, rented_until, purchase_price, purchase_at,
       last_seen_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    row.plate, row.model, row.vtype, row.category, row.char_id,
    row.status or 'garage',
    row.customization,         -- JSON string ou null
    row.locked and 1 or 0,
    row.position,
    row.ipva_paid_until, row.rented_until,
    row.purchase_price or 0, row.purchase_at or now,
    row.last_seen_at or now, now, now,
  }) ~= nil
end

function M:updateStatus(plate, status)
  return pexec(
    'UPDATE vhub_vehicles SET status = ?, updated_at = ? WHERE plate = ?',
    { status, os.time(), plate })
end

function M:updateOwner(plate, char_id)
  return pexec(
    'UPDATE vhub_vehicles SET char_id = ?, updated_at = ? WHERE plate = ?',
    { char_id, os.time(), plate })
end

function M:updatePosition(plate, posJson)
  return pexec(
    'UPDATE vhub_vehicles SET position = ?, last_seen_at = ?, updated_at = ? WHERE plate = ?',
    { posJson, os.time(), os.time(), plate })
end

function M:updateCustomization(plate, custJson, locked)
  return pexec(
    'UPDATE vhub_vehicles SET customization = ?, locked = ?, updated_at = ? WHERE plate = ?',
    { custJson, locked and 1 or 0, os.time(), plate })
end

function M:updateIpva(plate, paidUntil)
  return pexec(
    'UPDATE vhub_vehicles SET ipva_paid_until = ?, updated_at = ? WHERE plate = ?',
    { paidUntil, os.time(), plate })
end

function M:updateRental(plate, rentedUntil)
  return pexec(
    'UPDATE vhub_vehicles SET rented_until = ?, updated_at = ? WHERE plate = ?',
    { rentedUntil, os.time(), plate })
end

function M:deleteVehicle(plate)
  return pexec('DELETE FROM vhub_vehicles WHERE plate = ?', { plate })
end

-- ----------------------------------------------------------------------------
-- vhub_vehicle_keys (autoriza  o l gica;  tem f sico mora no vhub_inventory)
-- ----------------------------------------------------------------------------
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
  local now = os.time()
  local r = pquery([[
    SELECT 1 FROM vhub_vehicle_keys
    WHERE plate = ? AND char_id = ? AND (expires_at IS NULL OR expires_at > ?)
    LIMIT 1
  ]], { plate, char_id, now })
  return r and #r > 0
end

function M:listKeys(plate)
  return pquery('SELECT * FROM vhub_vehicle_keys WHERE plate = ?', { plate })
end

function M:listKeysOfChar(char_id)
  local now = os.time()
  return pquery([[
    SELECT * FROM vhub_vehicle_keys
    WHERE char_id = ? AND (expires_at IS NULL OR expires_at > ?)
  ]], { char_id, now })
end

function M:purgeExpiredKeys()
  return pexec(
    'DELETE FROM vhub_vehicle_keys WHERE expires_at IS NOT NULL AND expires_at < ?',
    { os.time() })
end

-- ----------------------------------------------------------------------------
-- vhub_auctions / vhub_auction_bids
-- ----------------------------------------------------------------------------
function M:createAuction(row)
  local p = promise.new()
  ox():insert([[
    INSERT INTO vhub_auctions
      (plate, seller_id, min_bid, buyout, fee_paid, ends_at, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?, 'active', ?)
  ]], { row.plate, row.seller_id, row.min_bid, row.buyout,
        row.fee_paid or 0, row.ends_at, os.time() },
     function(id) p:resolve(id) end)
  return Citizen.Await(p)
end

function M:getAuction(id)
  local r = pquery('SELECT * FROM vhub_auctions WHERE id = ? LIMIT 1', { id })
  return r and r[1] or nil
end

function M:getAuctionByPlate(plate)
  local r = pquery(
    'SELECT * FROM vhub_auctions WHERE plate = ? AND status = ? LIMIT 1',
    { plate, 'active' })
  return r and r[1] or nil
end

function M:listActiveAuctions()
  return pquery([[
    SELECT * FROM vhub_auctions
    WHERE status = 'active' AND ends_at > ?
    ORDER BY ends_at ASC
  ]], { os.time() })
end

function M:listExpiringAuctions()
  return pquery([[
    SELECT * FROM vhub_auctions
    WHERE status = 'active' AND ends_at <= ?
  ]], { os.time() })
end

function M:setAuctionBid(auction_id, bidder_id, amount)
  return pexec([[
    UPDATE vhub_auctions
       SET current_bid = ?, current_bidder = ?
     WHERE id = ? AND status = 'active'
  ]], { amount, bidder_id, auction_id })
end

function M:setAuctionStatus(auction_id, status)
  return pexec('UPDATE vhub_auctions SET status = ? WHERE id = ?',
    { status, auction_id })
end

function M:addBid(auction_id, bidder_id, amount)
  return pexec([[
    INSERT INTO vhub_auction_bids (auction_id, bidder_id, amount, created_at)
    VALUES (?, ?, ?, ?)
  ]], { auction_id, bidder_id, amount, os.time() })
end

function M:listBids(auction_id)
  return pquery([[
    SELECT * FROM vhub_auction_bids
    WHERE auction_id = ?
    ORDER BY amount DESC, created_at DESC
  ]], { auction_id })
end

-- ----------------------------------------------------------------------------
-- vhub_impound
-- ----------------------------------------------------------------------------
function M:impoundPut(plate, reason, fee, by)
  return pexec([[
    INSERT INTO vhub_impound (plate, reason, fee, impounded_by, impounded_at)
    VALUES (?, ?, ?, ?, ?)
  ]], { plate, reason or 'apreendido', fee or 0, by, os.time() })
end

function M:impoundGetActive(plate)
  local r = pquery([[
    SELECT * FROM vhub_impound
    WHERE plate = ? AND released_at IS NULL
    ORDER BY id DESC LIMIT 1
  ]], { plate })
  return r and r[1] or nil
end

function M:impoundRelease(id, by)
  return pexec(
    'UPDATE vhub_impound SET released_at = ?, released_by = ? WHERE id = ?',
    { os.time(), by, id })
end

function M:impoundList()
  return pquery([[
    SELECT i.*, v.model, v.vtype
      FROM vhub_impound i
      JOIN vhub_vehicles v ON v.plate = i.plate
     WHERE i.released_at IS NULL
     ORDER BY i.impounded_at DESC
  ]], {})
end

-- ----------------------------------------------------------------------------
-- vhub_dealership_stock
-- ----------------------------------------------------------------------------
function M:stockGet(model)
  local r = pquery(
    'SELECT * FROM vhub_dealership_stock WHERE model = ? LIMIT 1', { model })
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

-- ----------------------------------------------------------------------------
-- vhub_vehicle_log
-- ----------------------------------------------------------------------------
function M:log(plate, action, actor_id, payload)
  pexec([[
    INSERT INTO vhub_vehicle_log (plate, action, actor_id, payload, created_at)
    VALUES (?, ?, ?, ?, ?)
  ]], { plate, action, actor_id, payload, os.time() })
end
