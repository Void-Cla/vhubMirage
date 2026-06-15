---@diagnostic disable: undefined-global, lowercase-global

-- server/item_use.lua — DISPATCHER de uso de item.
--
-- O inventory NAO contem regra de dominio. Cada script dono registra o efeito do
-- seu item (ex: vhub_survival registra 'agua'). Aqui so roteamos e garantimos o
-- consumo atomico (tira 1 antes do efeito; reembolsa se o efeito falhar).

local M = {}; Inventory.ItemUse = M
local Backpack = Inventory.Bag

local _handlers = {}    -- [item_id] = function(src, slot, meta) -> consumed:bool


-- ============================================================
-- REGISTRO (chamado por resources externos via export)
-- ============================================================

-- registra o handler de uso de um item (substitui se ja existir)
function M.register(id, fn)
  if type(id) == 'string' and type(fn) == 'function' then
    _handlers[id] = fn
  end
end

-- ha efeito registrado para este item?
function M.hasHandler(id)
  return _handlers[id] ~= nil
end


-- ============================================================
-- EXECUCAO (consumo atomico com reembolso)
-- ============================================================

-- usa o item do slot. `expected_id` (vindo da NUI) protege contra o slot ter
-- mudado entre o clique e o evento chegar. Sem handler => nao faz nada.
function M.run(src, slot, expected_id)
  local entry = Backpack.peek(src, slot)
  if not entry then return false end
  if expected_id and entry.id ~= expected_id then return false end

  -- evento server-local: resources reagem ao uso SEM registrar funcref cross-resource
  -- (robusto quando o funcref nao sobrevive a fronteira do export). Cliente nao forja
  -- (AddEventHandler, nao RegisterNetEvent). Itens sem handler NAO sao consumidos.
  TriggerEvent('vhub_inventory:server:itemUsed', src, entry.id, slot, entry.meta)

  local handler = _handlers[entry.id]
  if not handler then return false end

  local item_id, meta = entry.id, entry.meta

  -- consumo atomico: decrementa ANTES do efeito
  if not Backpack.takeFromSlot(src, slot, 1) then return false end

  local ok, consumed = pcall(handler, src, slot, meta)
  if not ok or consumed == false then
    Backpack.giveToSlot(src, slot, item_id, 1, meta)   -- reembolso (efeito falhou)
    return false
  end

  return true
end
