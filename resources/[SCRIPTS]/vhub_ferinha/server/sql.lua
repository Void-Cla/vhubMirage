-- server/sql.lua — repositório do vhub_ferinha (oxmysql direto, decisão #8)
-- Dono de WRITE em: vhub_auctions, vhub_auction_bids. O DDL ainda é aplicado pelo
-- vhub_garage até a FASE 6 (ferinha "pega emprestado" as tabelas; só faz DML).
-- Toda função roda dentro de thread (Citizen.Await).
---@diagnostic disable: undefined-global

local M = {}; VHubFerinha = VHubFerinha or {}; VHubFerinha.SQL = M

local ox = function() return exports['oxmysql'] end

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
-- vhub_auctions / vhub_auction_bids
-- ============================================================

-- cria leilão e retorna o id gerado
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
  return pexec('UPDATE vhub_auctions SET status = ? WHERE id = ?', { status, auction_id })
end

function M:addBid(auction_id, bidder_id, amount)
  return pexec([[
    INSERT INTO vhub_auction_bids (auction_id, bidder_id, amount, created_at)
    VALUES (?, ?, ?, ?)
  ]], { auction_id, bidder_id, amount, os.time() })
end

-- todos os leilões ainda 'active' (independe de ends_at) — base da reconciliação de boot
function M:listAllActiveAuctions()
  return pquery("SELECT * FROM vhub_auctions WHERE status = 'active'", {})
end

-- auditoria append-only (mesma tabela do garage/conce; é log, não verdade)
function M:log(plate, action, actor_id, payloadJson)
  pexec([[
    INSERT INTO vhub_vehicle_log (plate, action, actor_id, payload, created_at)
    VALUES (?, ?, ?, ?, ?)
  ]], { plate, action, actor_id, payloadJson, os.time() })
end
