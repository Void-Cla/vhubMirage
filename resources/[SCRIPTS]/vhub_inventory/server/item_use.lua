---@diagnostic disable: undefined-global, lowercase-global

-- server/item_use.lua — DISPATCHER de uso de item.
--
-- O inventory NAO contem regra de dominio. Cada script dono registra o efeito do
-- seu item (ex: vhub_survival registra 'agua'). Aqui so roteamos e garantimos o
-- consumo sequencial em VRAM (tira 1 antes do efeito; reembolsa se o efeito falhar).
--
-- VNext: op dedup via Transaction.guarded garante idempotencia no replay/timeout.

local M = {}; Inventory.ItemUse = M
local Backpack = Inventory.Bag
local Cat      = Inventory.Catalog
local U        = Inventory.Utils

local function logError(msg, meta)
  pcall(function()
    local core = exports.vhub:getVHub()
    local logger = type(core) == 'table' and core.Logger or nil
    if logger and logger.error then logger:error('inventory', msg, meta) end
  end)
end

local _handlers = {}   -- [item_id] = descriptor
local _owners   = {}   -- [item_id] = resource dono do efeito
local _req      = {}   -- [src] = contador de request_id (VNext only; reinicia em disconnect)


-- ============================================================
-- REGISTRO (chamado por resources externos via export)
-- ============================================================

-- registra handler; primeiro owner vence e só ele pode substituir
function M.register(id, handler, owner)
  if type(id) ~= 'string' or id == '' or #id > 64 then return false end
  if type(owner) ~= 'string' or owner == '' then return false end
  if _owners[id] and _owners[id] ~= owner then return false end

  local descriptor
  if type(handler) == 'function' then
    descriptor = { kind = 'function', owner = owner, handler = handler }
  elseif type(handler) == 'string'
      and #handler <= 64
      and handler:match('^[%a][%w_]*$') then
    descriptor = { kind = 'export', owner = owner, handler = handler }
  else
    return false
  end

  _owners[id] = owner
  _handlers[id] = descriptor
  return true
end

-- ha efeito registrado para este item?
function M.hasHandler(id)
  return _handlers[id] ~= nil
end

-- limpa contador de request_id ao desconectar / trocar personagem
function M.resetSession(src)
  _req[src] = nil
end


-- ============================================================
-- EXECUCAO INTERNA (sem dedup)
-- ============================================================

local function callHandler(src, slot, item_id, meta, descriptor)
  if descriptor.kind == 'function' then
    return pcall(descriptor.handler, src, slot, meta)
  end
  if GetResourceState(descriptor.owner) ~= 'started' then return false, false end
  local proxy = exports[descriptor.owner]
  return pcall(function()
    return proxy[descriptor.handler](proxy, src, item_id, slot, meta)
  end)
end

-- executa o uso sem dedup (path v0 e fallback do VNext sem char_id)
local function runEffect(src, slot, item_id, meta, descriptor, consumePolicy)
  if consumePolicy == 'never' then
    local ok = callHandler(src, slot, item_id, meta, descriptor)
    return ok == true
  end

  -- consume antes do efeito; reembolsa se handler negar
  if not Backpack.takeFromSlot(src, slot, 1) then return false end

  local ok, consumed = callHandler(src, slot, item_id, meta, descriptor)
  if not ok or consumed ~= true then
    if not Backpack.giveToSlot(src, slot, item_id, 1, meta) then
      logError('falha em reembolso de uso de item', { src = src, item = item_id, slot = slot })
    end
    return false
  end

  return true
end


-- ============================================================
-- API PUBLICA
-- ============================================================

-- usa o item do slot. `expected_id` protege contra slot mudar entre clique e evento.
-- VNext: envolve em Transaction.guarded para op dedup (idempotencia em replay/timeout).
function M.run(src, slot, expected_id)
  local entry = Backpack.peek(src, slot)
  if not entry then return false end
  if expected_id and entry.id ~= expected_id then return false end

  local descriptor = _handlers[entry.id]
  if not descriptor then return false end

  local item_id, meta = entry.id, entry.meta
  local def = Cat.def(item_id) or {}
  local consumePolicy = def.consume_policy or 'on_applied'

  -- VNext: op dedup via Transaction.guarded garante idempotência
  if Inventory.VNext and Inventory.VNext.enabled and Inventory.Transaction then
    local char_id = Backpack.charId(src)
    if char_id then
      _req[src] = (_req[src] or 0) + 1
      local session_id = tostring(char_id)
      local request_id = tostring(_req[src])
      local fp = U.checksum(session_id .. ':' .. item_id .. ':' .. tostring(slot))
      return Inventory.Transaction.guarded(src, session_id, request_id, 'item_use', fp, function()
        return runEffect(src, slot, item_id, meta, descriptor, consumePolicy)
      end)
    end
  end

  return runEffect(src, slot, item_id, meta, descriptor, consumePolicy)
end
