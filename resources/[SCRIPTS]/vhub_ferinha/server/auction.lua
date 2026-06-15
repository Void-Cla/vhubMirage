-- server/auction.lua — leilão de veículos (server-authoritative)
-- Fluxo: dono lista (status 'auction', chave-item em escrow) → outros dão lances
--        (escrow do valor por jogador) → fim: maior lance vence, recebe chave;
--        vendedor recebe valor. A troca de DONO passa por conce:transferOwner.
-- newAuction/bid retornam {ok,msg} (o garage notifica e é dono da NUI).
---@diagnostic disable: undefined-global

local SQL  = VHubFerinha.SQL
local Core = VHubFerinha.Core
local CFG  = VHubFerinha.cfg
local UPDATE_AUCTION = VHubFerinha.GARAGE_UI.UPDATE_AUCTION

-- escrow de lances em memória: { [auction_id] = { [bidder_char_id] = amount } }
-- O escrow é volátil, mas BLINDADO: (#3) payout/refund usam Core.payChar→vhub_money:giveBankChar,
-- que credita o banco do char ONLINE ou OFFLINE (sem perda silenciosa); (#2) reconcileOrphans()
-- no boot estorna leilões 'active' perdidos num restart (lances vêm de vhub_auction_bids). A
-- chave-item do dono volta pelo self-heal da FASE 3. Resta só a janela ínfima lance↔crash.
local Escrow = {}

-- lock cooperativo por leilão: serializa bid/finalize/cancel para evitar TOCTOU
-- sobre os yields (Citizen.Await) do money/SQL. Lua é cooperativo → flag + rejeita-se-ocupado.
local Busy = {}
local function lock(id)   if Busy[id] then return false end Busy[id] = true return true end
local function unlock(id) Busy[id] = nil end


-- ============================================================
-- ESCROW (helpers)
-- ============================================================

-- estorna o lance retido de um char (offline-safe: crédito em banco por char_id)
local function refundEscrow(id, cid)
  local a = Escrow[id]; if not a then return end
  local amt = a[cid]
  if amt and amt > 0 then
    Core.payChar(cid, amt)   -- online ou offline (vhub_money:giveBankChar)
    a[cid] = nil
  end
end

-- estorna todos os lances retidos (exceto exceptCid) e limpa o escrow do leilão
local function clearEscrow(id, exceptCid)
  local a = Escrow[id]; if not a then return end
  for cid, _ in pairs(a) do
    if cid ~= exceptCid then refundEscrow(id, cid) end
  end
  Escrow[id] = nil
end

-- publica o snapshot do leilão para os clientes (NUI do garage)
local function broadcast(id)
  local a = SQL:getAuction(id); if not a then return end
  TriggerClientEvent(UPDATE_AUCTION, -1, a)
end


-- ============================================================
-- FINALIZE (interno — chamado pelo cron, buyout ou fim do tempo)
-- ============================================================

-- encerra o leilão: vencedor recebe chave + dono via conce; vendedor recebe valor
function VHubFerinha.finalizeAuction(id, byBuyout)
  local a = SQL:getAuction(id); if not a or a.status ~= 'active' then return end

  if a.current_bidder and a.current_bid and a.current_bid > 0 then
    local winner, amt = a.current_bidder, a.current_bid
    Escrow[id] = Escrow[id] or {}
    Escrow[id][winner] = nil          -- vencedor não recebe de volta
    clearEscrow(id, nil)              -- estorna os perdedores

    Core.transferOwner(a.plate, winner)   -- char_id + chave-row 'owner' (atômico, conce)
    Core.setStatus(a.plate, 'garage')     -- status volta p/ garagem (conce)
    SQL:setAuctionStatus(id, 'sold')

    -- chave-item ao vencedor: viva se online; offline → self-heal no login (FASE 3, já é dono)
    local ws = Core:srcByCharId(winner); if ws then Core.giveKeyItem(ws, a.plate) end
    Core.payChar(a.seller_id, amt)   -- pagamento ao vendedor (offline-safe, banco por char_id)

    Core:log(a.plate, 'auction_sold', winner, { id = id, amount = amt, buyout = byBuyout == true })
  else
    -- sem lances: devolve chave ao vendedor e marca expirado
    Core.setStatus(a.plate, 'garage')
    SQL:setAuctionStatus(id, 'expired')
    local ss = Core:srcByCharId(a.seller_id); if ss then Core.giveKeyItem(ss, a.plate) end
    Core:log(a.plate, 'auction_expired', a.seller_id, { id = id })
    clearEscrow(id, nil)
  end
  broadcast(id)
end


-- ============================================================
-- NEW (delegado por vhub_garage:ACT_AUCTION_NEW)
-- ============================================================

-- abre um leilão (apenas o dono); retorna {ok,msg}
function VHubFerinha.newAuction(src, plate, min_bid, buyout, dur_min)
  local cid = Core:getCharId(src); if not cid then return { ok = false } end
  local p   = tostring(plate or ''):upper():match('^%s*(.-)%s*$')
  if p == '' then return { ok = false } end
  local min_n  = tonumber(min_bid) or 0
  local buyout_n = tonumber(buyout)
  dur_min = tonumber(dur_min) or CFG.auction_dur_default
  if dur_min < CFG.auction_dur_min then dur_min = CFG.auction_dur_min end
  if dur_min > CFG.auction_dur_max then dur_min = CFG.auction_dur_max end

  local v = Core.getVehicle(p)
  if not v or v.char_id ~= cid then return { ok = false, msg = 'Apenas o dono pode leiloar.' } end
  if v.status ~= 'garage' then return { ok = false, msg = 'Veículo precisa estar na garagem para leiloar.' } end
  if SQL:getAuctionByPlate(p) then return { ok = false, msg = 'Veículo já está em leilão.' } end
  if min_n <= 0 then return { ok = false, msg = 'Lance mínimo inválido.' } end
  if not Core.payWallet(src, CFG.auction_fee) then
    return { ok = false, msg = ('Saldo na carteira insuficiente. Taxa: R$ %d.'):format(CFG.auction_fee) }
  end

  -- chave-item vai para escrow (toma do dono) + marca status no conce
  Core.takeKeyItem(src, p)
  Core.setStatus(p, 'auction')

  local id = SQL:createAuction({
    plate = p, seller_id = cid, min_bid = min_n, buyout = buyout_n,
    fee_paid = CFG.auction_fee, ends_at = os.time() + dur_min * 60,
  })
  Escrow[id] = {}
  Core:log(p, 'auction_new', cid, { id = id, min = min_n, buyout = buyout_n, dur = dur_min })
  broadcast(id)
  return { ok = true, msg = ('Leilão aberto. Termina em %d min.'):format(dur_min) }
end


-- ============================================================
-- BID (delegado por vhub_garage:ACT_AUCTION_BID)
-- ============================================================

-- registra um lance (serializado pelo lock do leilão; escrow integral; buyout encerra na hora)
function VHubFerinha.bid(src, auction_id, amount)
  local id = tonumber(auction_id); if not id then return { ok = false } end
  if not lock(id) then return { ok = false, msg = 'Processando outro lance — tente novamente.' } end
  local ok, r = pcall(VHubFerinha._doBid, src, id, amount)
  unlock(id)
  return (ok and r) or { ok = false }
end

-- lógica real do lance (sempre executada sob lock(id), sem interleave de bid/finalize)
function VHubFerinha._doBid(src, id, amount)
  local cid = Core:getCharId(src); if not cid then return { ok = false } end
  local amt = tonumber(amount) or 0

  local a = SQL:getAuction(id)
  if not a or a.status ~= 'active' then return { ok = false, msg = 'Leilão não ativo.' } end
  if a.ends_at <= os.time() then return { ok = false, msg = 'Leilão encerrado.' } end
  if a.seller_id == cid then return { ok = false, msg = 'Você não pode dar lance no próprio leilão.' } end

  local current = a.current_bid or a.min_bid
  local minimo  = a.current_bid and math.floor(current * (1 + CFG.auction_increment)) or current
  if amt < minimo then
    return { ok = false, msg = ('Lance mínimo: R$ %d (+%d%%).'):format(minimo, math.floor(CFG.auction_increment * 100)) }
  end

  -- escrow: cobra o delta vs lance anterior do mesmo bidder
  Escrow[id] = Escrow[id] or {}
  local prev, diff = Escrow[id][cid] or 0, 0
  diff = amt - prev
  if diff > 0 then
    if not Core.pay(src, diff) then return { ok = false, msg = 'Saldo insuficiente para esse lance.' } end
  elseif diff < 0 then
    Core.refund(src, -diff)
  end
  Escrow[id][cid] = amt

  -- estorna o bidder anterior (se for outro)
  if a.current_bidder and a.current_bidder ~= cid then refundEscrow(id, a.current_bidder) end

  SQL:setAuctionBid(id, cid, amt)
  SQL:addBid(id, cid, amt)
  Core:log(a.plate, 'auction_bid', cid, { id = id, amount = amt })

  if a.buyout and amt >= a.buyout then
    VHubFerinha.finalizeAuction(id, true)
  else
    broadcast(id)
  end
  return { ok = true, msg = ('Lance R$ %d registrado.'):format(amt) }
end


-- ============================================================
-- CANCEL (admin) + FINALIZE EXPIRED (cron)
-- ============================================================

-- cancela o leilão (sob lock): devolve chave ao vendedor + estorna lances. actor = char do admin.
function VHubFerinha.cancelAuction(id, actor_cid)
  id = tonumber(id); if not id then return false end
  if not lock(id) then return false end
  local ok, r = pcall(VHubFerinha._doCancel, id, actor_cid)
  unlock(id)
  return (ok and r) or false
end

function VHubFerinha._doCancel(id, actor_cid)
  local a = SQL:getAuction(id); if not a or a.status ~= 'active' then return false end
  SQL:setAuctionStatus(id, 'cancelled')
  Core.setStatus(a.plate, 'garage')
  local ss = Core:srcByCharId(a.seller_id); if ss then Core.giveKeyItem(ss, a.plate) end
  clearEscrow(id, nil)
  Core:log(a.plate, 'auction_cancelled', actor_cid, { id = id })
  broadcast(id)
  return true
end

-- encerra todos os leilões vencidos (cron/admin), cada um sob seu lock; retorna a contagem
function VHubFerinha.finalizeExpired()
  local rows = SQL:listExpiringAuctions() or {}
  local n = 0
  for _, a in ipairs(rows) do
    if lock(a.id) then
      pcall(VHubFerinha.finalizeAuction, a.id, false)
      unlock(a.id)
      n = n + 1
    end
    Citizen.Wait(0)
  end
  return n
end

-- RECONCILIAÇÃO DE BOOT (fecha o finding #2 — escrow é volátil): se o servidor reiniciou
-- com leilões 'active', o escrow em memória se perdeu. Cancela cada um: estorna a cada bidder
-- seu MAIOR lance (banco, offline-safe via maxBidPerBidder) + devolve o carro p/ a garagem do
-- dono (a chave-item do dono volta pelo self-heal da FASE 3 no login) + marca cancelado.
function VHubFerinha.reconcileOrphans()
  local rows = SQL:listAllActiveAuctions() or {}
  local n = 0
  for _, a in ipairs(rows) do
    if lock(a.id) then
      -- SÓ o lance vigente está em escrow: os perdedores já foram estornados ao vivo
      -- (refundEscrow ao serem superados). Estornar todos os bids = duplo estorno.
      local amt = tonumber(a.current_bid)
      if a.current_bidder and amt and amt > 0 then Core.payChar(a.current_bidder, amt) end
      Core.setStatus(a.plate, 'garage')
      SQL:setAuctionStatus(a.id, 'cancelled')
      Core:log(a.plate, 'auction_restart_cancel', 0, { id = a.id })
      unlock(a.id)
      n = n + 1
    end
    Citizen.Wait(0)
  end
  return n
end
