---@diagnostic disable: undefined-global, lowercase-global

-- server/exports.lua — API publica para outros resources.
-- Mutadores validam invoker (_invoker_allowed); leitura e publica.
-- Mantem compat com os nomes do stub antigo (giveItem/takeItem/hasItem/chaves).

local Backpack = Inventory.Bag
local ItemUse  = Inventory.ItemUse
local Cat      = Inventory.Catalog


-- ============================================================
-- CONTROLE DE INVOCADOR
-- ============================================================

-- libera chamada local; cross-resource passa se nao houver whitelist (ou se estiver nela)
local function _invoker_allowed()
  local trust = Inventory.TrustedResources
  if not trust or next(trust) == nil then return true end
  local caller = GetInvokingResource()
  if not caller then return true end
  return trust[caller] == true
end


-- ============================================================
-- LEITURA (publica)
-- ============================================================

-- retorna { slots, weight, max, size } da mochila (copia ao cruzar resource)
exports('getInventory', function(src)
  return Backpack.snapshot(src) or { slots = {}, weight = 0, max = 0, size = 0 }
end)

exports('getItemAmount',  function(src, id)      return Backpack.amount(src, id)        end)
exports('hasItem',        function(src, id, qty) return Backpack.has(src, id, qty)      end)
exports('getInventoryWeight', function(src)      return Backpack.weight(src)            end)
exports('getItemDef',     function(id)           return Cat.def(id)                     end)
exports('getItemName',    function(id)           local d = Cat.def(id); return d and d.nome or id end)


-- ============================================================
-- MUTACAO (validar invoker)
-- ============================================================

exports('giveItem', function(src, id, amount, meta)
  if not _invoker_allowed() then return false end
  return (Backpack.give(src, id, amount, meta)) == true
end)

exports('takeItem', function(src, id, amount)
  if not _invoker_allowed() then return false end
  return (Backpack.take(src, id, amount)) == true
end)

-- registra o efeito de uso de um item (dono do dominio chama isto)
exports('registerItemUse', function(id, fn)
  if not _invoker_allowed() then return false end
  ItemUse.register(id, fn)
  return true
end)

-- abre um baú para o jogador (valida proximidade/permissao). desc = { kind, name|group|netId }
exports('openContainer', function(src, desc)
  if not _invoker_allowed() then return false end
  Inventory.Containers.requestOpen(src, desc)
  return true
end)

-- ============================================================
-- CHAVES DE VEICULO (compat — meta carrega a placa)
-- ============================================================

exports('giveVehicleKey', function(src, plate)
  if not _invoker_allowed() then return false end
  if type(plate) ~= 'string' then return false end
  return (Backpack.give(src, 'veh_key', 1, { plate = plate })) == true
end)

exports('hasVehicleKey', function(src, plate)
  local snap = Backpack.snapshot(src); if not snap then return false end
  for _, e in pairs(snap.slots) do
    if e.id == 'veh_key' and e.meta and e.meta.plate == plate then return true end
  end
  return false
end)

exports('takeVehicleKey', function(src, plate)
  if not _invoker_allowed() then return false end
  local snap = Backpack.snapshot(src); if not snap then return false end
  for slot, e in pairs(snap.slots) do
    if e.id == 'veh_key' and e.meta and e.meta.plate == plate then
      return Backpack.takeFromSlot(src, slot, 1) == true
    end
  end
  return false
end)

exports('getVehicleKeys', function(src)
  local snap = Backpack.snapshot(src); if not snap then return {} end
  local keys = {}
  for _, e in pairs(snap.slots) do
    if e.id == 'veh_key' and e.meta and e.meta.plate then keys[#keys + 1] = e.meta.plate end
  end
  return keys
end)
