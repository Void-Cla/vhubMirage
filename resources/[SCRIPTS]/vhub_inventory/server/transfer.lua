---@diagnostic disable: undefined-global, lowercase-global

-- server/transfer.lua — transferencias mochila <-> baú (atomicas, sob mutex).
--
-- Cliente e OTIMISTA so no LADO DE ORIGEM (remove do slot de onde arrastou). O DESTINO
-- e sempre escolhido pelo SERVIDOR (findDest / give) e chega por delta — sem mismatch.
-- Em falha: o servidor reenvia o estado autoritativo do slot tocado (reverte a UI).

local M = {}; Inventory.Transfer = M

local U          = Inventory.Utils
local Backpack   = Inventory.Bag
local Containers = Inventory.Containers
local E          = VHubInvE

local ERR = {
  fechado   = 'Baú fechado',           ocupado  = 'Baú em uso, tente de novo',
  vazio     = 'Item não encontrado',   item     = 'Item inválido',
  qty       = 'Quantidade inválida',   bloqueado= 'Item não permitido no baú',
  cheio     = 'Baú cheio',             peso     = 'Mochila cheia',
}
local function notify(src, e) TriggerClientEvent(E.NOTIFY, src, ERR[e] or 'Falha na transferência') end


-- ============================================================
-- STORE — mochila[from] -> baú aberto (destino escolhido pelo servidor)
-- ============================================================

local function doStore(src, cid, from, to, qty)
  local entry = Backpack.peek(src, from);            if not entry then return false, 'vazio' end
  local def   = U.itemDef(entry.id);                 if not def   then return false, 'item' end
  qty = U.validQty(qty, entry.amount);               if not qty   then return false, 'qty' end
  if def.permitido_bau == false then return false, 'bloqueado' end

  -- capacidade (peso) do baú
  if Containers.weight(cid) + (def.peso or 0) * qty > Containers.capacity(cid) then return false, 'cheio' end

  local dst = Containers.findDest(cid, entry.id, qty, to)
  if not dst then return false, 'cheio' end

  -- atomico (sob mutex, ja validado): tira da mochila, poe no baú
  if not Backpack.takeFromSlot(src, from, qty) then return false, 'vazio' end
  if not Containers.giveToSlot(cid, dst, entry.id, qty, entry.meta) then
    Backpack.giveToSlot(src, from, entry.id, qty, entry.meta)   -- reembolso (nao deveria ocorrer)
    return false, 'cheio'
  end
  return true
end

function M.store(src, from, to, qty)
  local cid = Containers.openedBy(src)
  if not cid then notify(src, 'fechado'); return end
  if not Containers.lock(cid) then Backpack.rollback(src, { from }, 'ocupado'); return end

  local ok, err = doStore(src, cid, from, to, qty)
  Containers.unlock(cid)

  -- falha: reenvia o slot de origem da mochila (reverte a remocao otimista) + razao
  if not ok then Backpack.rollback(src, { from }, err) end
end


-- ============================================================
-- RETRIEVE — baú aberto[from] -> mochila (destino escolhido pelo servidor)
-- ============================================================

local function doRetrieve(src, cid, from, to, qty)
  local entry = Containers.peek(cid, from);   if not entry then return false, 'vazio' end
  qty = U.validQty(qty, entry.amount);        if not qty   then return false, 'qty' end
  if not Backpack.canFit(src, entry.id, qty) then return false, 'peso' end

  -- atomico: tira do baú, poe na mochila (slot pedido se valido, senao auto-place)
  if not Containers.takeFromSlot(cid, from, qty) then return false, 'vazio' end

  local toSlot = U.validSlot(to, Inventory.Backpack.slots or 30)
  local placed = toSlot and Backpack.giveToSlot(src, toSlot, entry.id, qty, entry.meta)
  if not placed then placed = Backpack.give(src, entry.id, qty, entry.meta) end
  if not placed then
    Containers.giveToSlot(cid, from, entry.id, qty, entry.meta)  -- reembolso
    return false, 'peso'
  end
  return true
end

function M.retrieve(src, from, to, qty)
  local cid = Containers.openedBy(src)
  if not cid then notify(src, 'fechado'); return end
  if not Containers.lock(cid) then notify(src, 'ocupado'); return end

  local ok, err = doRetrieve(src, cid, from, to, qty)
  Containers.unlock(cid)

  -- falha: reenvia o slot de origem do baú (reverte a remocao otimista) + razao
  if not ok then Containers.resend(src, cid, { from }); notify(src, err) end
end
