-- server/auction.lua  leil o de ve culos
-- Fluxo: dono lista (ve culo vai para status 'auction', chave-item fica em escrow)
--        outros d o lances (escrow do valor por jogador)
--        ao fim: maior lance vence, recebe chave; vendedor recebe valor
-- Cron leve: a cada 60s verifica leil es expirados.
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local U    = VHubGarage.U
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

-- escrow de lances: { [auction_id] = { [bidder_char_id] = amount } }
local Escrow = {}

local function refundEscrow(auction_id, char_id)
  local a = Escrow[auction_id]; if not a then return end
  local amt = a[char_id]
  if amt and amt > 0 then
    -- procura src online com aquele char
    for src, u in pairs(Core.sessions) do
      if u.char_id == char_id then Core.refund(src, amt); break end
    end
    a[char_id] = nil
  end
end

local function clearEscrow(auction_id, exceptCharId, doRefund)
  local a = Escrow[auction_id]; if not a then return end
  for cid, _ in pairs(a) do
    if cid ~= exceptCharId and doRefund then refundEscrow(auction_id, cid) end
  end
  Escrow[auction_id] = nil
end

-- broadcast snapshot do leil o para clientes na zona da auction house
local function broadcastUpdate(id)
  local a = SQL:getAuction(id); if not a then return end
  TriggerClientEvent(E.UPDATE_AUCTION, -1, a)
end

-- ----------------------------------------------------------------------------
-- LIST: REQ_AUCTIONS
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REQ_AUCTIONS)
AddEventHandler(E.REQ_AUCTIONS, function()
  local src = source
  Citizen.CreateThread(function()
    local list = SQL:listActiveAuctions() or {}
    local out = {}
    for _, a in ipairs(list) do
      local v = SQL:getVehicle(a.plate)
      out[#out+1] = {
        id = a.id, plate = a.plate,
        seller_id = a.seller_id,
        min_bid = a.min_bid, buyout = a.buyout,
        current_bid = a.current_bid, current_bidder = a.current_bidder,
        ends_at = a.ends_at, status = a.status,
        model = v and v.model, vtype = v and v.vtype,
        nome = v and (VHubGarage.catalog[v.model] and VHubGarage.catalog[v.model].nome) or v and v.model,
        preco_ref = v and (VHubGarage.catalog[v.model] and VHubGarage.catalog[v.model].preco) or 0,
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

-- ----------------------------------------------------------------------------
-- NEW
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_AUCTION_NEW)
AddEventHandler(E.ACT_AUCTION_NEW, function(plate, min_bid, buyout, duracao_min)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end
  local min_n = tonumber(min_bid) or 0
  local buyout_n = tonumber(buyout)
  duracao_min = tonumber(duracao_min) or CFG.leilao_duracao_min
  if duracao_min < 5  then duracao_min = 5  end
  if duracao_min > 1440 then duracao_min = 1440 end

  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p)
    if not v or v.char_id ~= cid then
      Core.notify(src, 'Apenas o dono pode leiloar.'); return
    end
    if v.status ~= 'garage' then
      Core.notify(src, 'Ve culo precisa estar na garagem para leiloar.'); return
    end
    if SQL:getAuctionByPlate(p) then
      Core.notify(src, 'Ve culo j  est  em leil o.'); return
    end
    if min_n <= 0 then
      Core.notify(src, 'Lance m nimo inv lido.'); return
    end
    if not Core.payWallet(src, CFG.taxa_leilao) then
      Core.notify(src, ('Saldo na carteira insuficiente. Taxa: R$ %d.'):format(CFG.taxa_leilao))
      return
    end

    -- chave-item vai para escrow (toma do dono e marca status)
    Core.takeKeyItem(src, p)
    SQL:updateStatus(p, 'auction')

    local id = SQL:createAuction({
      plate = p, seller_id = cid,
      min_bid = min_n, buyout = buyout_n,
      fee_paid = CFG.taxa_leilao,
      ends_at = os.time() + duracao_min * 60,
    })
    Escrow[id] = {}
    Core:log(p, 'auction_new', cid, { id = id, min = min_n, buyout = buyout_n, dur = duracao_min })
    Core.notify(src, ('Leil o aberto. Termina em %s.'):format(U.fmtDur(duracao_min * 60)))
    broadcastUpdate(id)
  end)
end)

-- ----------------------------------------------------------------------------
-- BID
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_AUCTION_BID)
AddEventHandler(E.ACT_AUCTION_BID, function(auction_id, amount)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local id  = tonumber(auction_id); if not id then return end
  local amt = tonumber(amount) or 0

  Citizen.CreateThread(function()
    local a = SQL:getAuction(id)
    if not a or a.status ~= 'active' then
      Core.notify(src, 'Leil o n o ativo.'); return
    end
    if a.ends_at <= os.time() then
      Core.notify(src, 'Leil o encerrado.'); return
    end
    if a.seller_id == cid then
      Core.notify(src, 'Voc  n o pode dar lance no pr prio leil o.'); return
    end

    local current = a.current_bid or a.min_bid
    local minimo  = current
    if a.current_bid then
      minimo = math.floor(current * (1 + CFG.leilao_incremento))
    end
    if amt < minimo then
      Core.notify(src, ('Lance m nimo: R$ %d (+ %d%%).')
        :format(minimo, math.floor(CFG.leilao_incremento * 100)))
      return
    end

    -- escrow: cobra integral; refund de lance anterior do mesmo
    Escrow[id] = Escrow[id] or {}
    local prev = Escrow[id][cid] or 0
    local diff = amt - prev
    if diff > 0 then
      if not Core.pay(src, diff) then
        Core.notify(src, 'Saldo insuficiente para esse lance.'); return
      end
    elseif diff < 0 then
      Core.refund(src, -diff)
    end
    Escrow[id][cid] = amt

    -- refund do bidder anterior (se outro)
    if a.current_bidder and a.current_bidder ~= cid then
      refundEscrow(id, a.current_bidder)
    end

    SQL:setAuctionBid(id, cid, amt)
    SQL:addBid(id, cid, amt)
    Core:log(a.plate, 'auction_bid', cid, { id = id, amount = amt })
    Core.notify(src, ('Lance R$ %d registrado.'):format(amt))

    -- buyout
    if a.buyout and amt >= a.buyout then
      finalizeAuction(id, true)
    else
      broadcastUpdate(id)
    end
  end)
end)

-- ----------------------------------------------------------------------------
-- FINALIZE (interno; chamado pelo cron ou buyout)
-- ----------------------------------------------------------------------------
function finalizeAuction(id, byBuyout)
  local a = SQL:getAuction(id); if not a or a.status ~= 'active' then return end

  if a.current_bidder and a.current_bid and a.current_bid > 0 then
    -- vencedor: refund de escrow + recebe chave; vendedor recebe na carteira
    local cid_winner = a.current_bidder
    local amt = a.current_bid
    Escrow[id] = Escrow[id] or {}
    Escrow[id][cid_winner] = nil    -- vencedor n o leva de volta
    clearEscrow(id, nil, true)      -- refunda perdedores

    -- transfere ve culo: troca dono, restaura status
    SQL:updateOwner(a.plate, cid_winner)
    SQL:updateStatus(a.plate, 'garage')
    SQL:setAuctionStatus(id, 'sold')
    SQL:revokeKey(a.plate, a.seller_id, 'owner')
    SQL:grantKey(a.plate, cid_winner, 'owner', cid_winner, nil)

    -- entrega chave-item ao vencedor online (se off, ele recebe no pr ximo login via authorized())
    for src, u in pairs(Core.sessions) do
      if u.char_id == cid_winner then Core.giveKeyItem(src, a.plate); break end
      if u.char_id == a.seller_id then Core.giveBank(src, amt) end
    end
    -- garante banco do vendedor mesmo offline (cr dito direto):
    -- (vhub_money tem giveBank que opera por src; se off-line, recurso interno paga
    --  no pr ximo getSession)
    -- TODO: dep sito direto por char_id (futuro)

    Core:log(a.plate, 'auction_sold', cid_winner, { id = id, amount = amt, buyout = byBuyout })
  else
    -- sem lances: devolve chave ao vendedor e marca expirado
    SQL:updateStatus(a.plate, 'garage')
    SQL:setAuctionStatus(id, 'expired')
    for src, u in pairs(Core.sessions) do
      if u.char_id == a.seller_id then Core.giveKeyItem(src, a.plate); break end
    end
    Core:log(a.plate, 'auction_expired', a.seller_id, { id = id })
    clearEscrow(id, nil, true)
  end
  broadcastUpdate(id)
end

-- ----------------------------------------------------------------------------
-- CANCEL (admin)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_AUCTION_CANC)
AddEventHandler(E.ACT_AUCTION_CANC, function(auction_id)
  local src = source
  if not Core.hasPerm(src, CFG.perms.auction_admin) then return end
  local id = tonumber(auction_id); if not id then return end
  Citizen.CreateThread(function()
    local a = SQL:getAuction(id); if not a or a.status ~= 'active' then return end
    SQL:setAuctionStatus(id, 'cancelled')
    SQL:updateStatus(a.plate, 'garage')
    -- chave-item de volta ao vendedor; lances todos estornados
    for s, u in pairs(Core.sessions) do
      if u.char_id == a.seller_id then Core.giveKeyItem(s, a.plate); break end
    end
    clearEscrow(id, nil, true)
    Core:log(a.plate, 'auction_cancelled', Core:getCharId(src), { id = id })
    broadcastUpdate(id)
  end)
end)

-- ----------------------------------------------------------------------------
-- CRON: leil es expirando
-- ----------------------------------------------------------------------------
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(60 * 1000)
    local rows = SQL:listExpiringAuctions() or {}
    for _, a in ipairs(rows) do finalizeAuction(a.id, false) end
  end
end)
