-- server/auction.lua — DELEGATOR fino: o leilão mora no vhub_ferinha (FASE 4).
-- O garage é dono da NUI: monta a lista (ferinha + catálogo-cache) e notifica o ator;
-- a transação/escrow/cron de leilão é do vhub_ferinha. Troca de dono via conce.
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E


-- ============================================================
-- LISTAR  (REQ_AUCTIONS: monta a NUI a partir de ferinha + catálogo-cache)
-- ============================================================
RegisterNetEvent(E.REQ_AUCTIONS)
AddEventHandler(E.REQ_AUCTIONS, function()
  local src = source
  Citizen.CreateThread(function()
    local list = exports.vhub_ferinha:listActiveAuctions() or {}
    local out = {}
    for _, a in ipairs(list) do
      local v     = SQL:getVehicle(a.plate)           -- proxy -> conce
      local entry = v and VHubGarage.catalog[v.model] -- cache do catálogo (conce)
      out[#out+1] = {
        id = a.id, plate = a.plate, seller_id = a.seller_id,
        min_bid = a.min_bid, buyout = a.buyout,
        current_bid = a.current_bid, current_bidder = a.current_bidder,
        ends_at = a.ends_at, status = a.status,
        model = v and v.model, vtype = v and v.vtype,
        nome = (entry and entry.nome) or (v and v.model),
        preco_ref = (entry and entry.preco) or 0,
      }
    end
    TriggerClientEvent(E.OPEN_UI, src, {
      view = VHubGarage.UI.OPEN_AUCTION,
      payload = { auctions = out, cfg = {
        fee = CFG.taxa_leilao, dur_min = CFG.leilao_duracao_min,
        increment = CFG.leilao_incremento,
      }},
    })
  end)
end)


-- ============================================================
-- NOVO LEILÃO  (delega ao ferinha)
-- ============================================================
RegisterNetEvent(E.ACT_AUCTION_NEW)
AddEventHandler(E.ACT_AUCTION_NEW, function(plate, min_bid, buyout, duracao_min)
  local src = source
  Citizen.CreateThread(function()
    local r = exports.vhub_ferinha:newAuction(src, plate, min_bid, buyout, duracao_min) or {}
    if r.msg then Core.notify(src, r.msg) end
  end)
end)


-- ============================================================
-- LANCE  (delega ao ferinha)
-- ============================================================
RegisterNetEvent(E.ACT_AUCTION_BID)
AddEventHandler(E.ACT_AUCTION_BID, function(auction_id, amount)
  local src = source
  Citizen.CreateThread(function()
    local r = exports.vhub_ferinha:bid(src, auction_id, amount) or {}
    if r.msg then Core.notify(src, r.msg) end
  end)
end)


-- ============================================================
-- CANCELAR (admin via NUI) — perm no garage, transação/escrow no ferinha
-- ============================================================
RegisterNetEvent(E.ACT_AUCTION_CANC)
AddEventHandler(E.ACT_AUCTION_CANC, function(auction_id)
  local src = source
  if not Core.hasPerm(src, CFG.perms.auction_admin) then return end
  Citizen.CreateThread(function()
    exports.vhub_ferinha:cancelAuction(auction_id, Core:getCharId(src))
  end)
end)
