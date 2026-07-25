---@diagnostic disable: undefined-global, lowercase-global

-- server/transfer.lua — transferencias mochila <-> bau sob mutex.

local M = {}; Inventory.Transfer = M

local U          = Inventory.Utils
local Backpack   = Inventory.Bag
local Containers = Inventory.Containers
local E          = VHubInvE

local TRACE = debug and debug.traceback or function(err) return tostring(err) end

local ERR = {
  fechado   = 'Bau fechado',
  ocupado   = 'Bau em uso, tente de novo',
  vazio     = 'Item nao encontrado',
  item      = 'Item invalido',
  qty       = 'Quantidade invalida',
  bloqueado = 'Item nao permitido no bau',
  cheio     = 'Bau cheio',
  peso      = 'Mochila cheia',
  erro      = 'Falha interna na transferencia',
}

local function notify(src, e)
  TriggerClientEvent(E.NOTIFY, src, ERR[e] or 'Falha na transferencia')
end

local function logError(msg, err)
  pcall(function()
    local core = exports.vhub:getVHub()
    local logger = type(core) == 'table' and core.Logger or nil
    if logger and logger.error then
      logger:error('inventory', msg, { err = tostring(err) })
    end
  end)
end

local function closeInvalid(src)
  Containers.close(src)
  TriggerClientEvent(E.CONTAINER_CLOSE, src)
  notify(src, 'fechado')
end

local function withLock(cid, onBusy, fn)
  local token = Containers.lock(cid)
  if not token then
    if onBusy then onBusy() end
    return false, 'ocupado'
  end

  local ran, ok, err = xpcall(fn, TRACE)
  Containers.unlock(cid, token)
  if not ran then
    logError('erro em transferencia de container', ok)
    return false, 'erro'
  end

  return ok, err
end


-- ============================================================
-- STORE — mochila[from] -> bau aberto
-- ============================================================

local function doStore(src, cid, from, to, qty)
  local entry = Backpack.peek(src, from)
  if not entry then return false, 'vazio' end

  local def = U.itemDef(entry.id)
  if not def then return false, 'item' end

  qty = U.validQty(qty, entry.amount)
  if not qty then return false, 'qty' end
  if def.permitido_bau == false then return false, 'bloqueado' end

  if Containers.weight(cid) + (def.peso or 0) * qty > Containers.capacity(cid) then
    return false, 'cheio'
  end

  local dst = Containers.findDest(cid, entry.id, qty, to, entry.meta)
  if not dst then return false, 'cheio' end

  if not Backpack.takeFromSlot(src, from, qty) then return false, 'vazio' end
  if not Containers.giveToSlot(cid, dst, entry.id, qty, entry.meta) then
    if not Backpack.giveToSlot(src, from, entry.id, qty, entry.meta) then
      logError('falha em reembolso mochila->bau', { src = src, cid = cid, slot = from })
      return false, 'erro'
    end
    return false, 'cheio'
  end

  return true
end

function M.store(src, from, to, qty)
  local cid = Containers.openedBy(src)
  if not cid then notify(src, 'fechado'); return end
  if not Containers.validateOpen(src, cid) then closeInvalid(src); return end

  local ok, err = withLock(cid, function()
    Backpack.rollback(src, { from }, 'ocupado')
  end, function()
    if not Containers.validateOpen(src, cid) then return false, 'fechado' end
    return doStore(src, cid, from, to, qty)
  end)

  if err == 'ocupado' then return end
  if err == 'fechado' then closeInvalid(src); return end
  if not ok then Backpack.rollback(src, { from }, err) end
end


-- ============================================================
-- RETRIEVE — bau aberto[from] -> mochila
-- ============================================================

local function doRetrieve(src, cid, from, to, qty)
  local entry = Containers.peek(cid, from)
  if not entry then return false, 'vazio' end

  qty = U.validQty(qty, entry.amount)
  if not qty then return false, 'qty' end
  if not Backpack.canFit(src, entry.id, qty) then return false, 'peso' end

  if not Containers.takeFromSlot(cid, from, qty) then return false, 'vazio' end

  local toSlot = U.validSlot(to, Inventory.Backpack.slots or 30)
  local placed = toSlot and Backpack.giveToSlot(src, toSlot, entry.id, qty, entry.meta)
  if not placed then placed = Backpack.give(src, entry.id, qty, entry.meta) end
  if not placed then
    if not Containers.giveToSlot(cid, from, entry.id, qty, entry.meta) then
      logError('falha em reembolso bau->mochila', { src = src, cid = cid, slot = from })
      return false, 'erro'
    end
    return false, 'peso'
  end

  return true
end

function M.retrieve(src, from, to, qty)
  local cid = Containers.openedBy(src)
  if not cid then notify(src, 'fechado'); return end
  if not Containers.validateOpen(src, cid) then closeInvalid(src); return end

  local ok, err = withLock(cid, function()
    notify(src, 'ocupado')
  end, function()
    if not Containers.validateOpen(src, cid) then return false, 'fechado' end
    return doRetrieve(src, cid, from, to, qty)
  end)

  if err == 'ocupado' then return end
  if err == 'fechado' then closeInvalid(src); return end
  if not ok then Containers.resend(src, cid, { from }); notify(src, err) end
end
