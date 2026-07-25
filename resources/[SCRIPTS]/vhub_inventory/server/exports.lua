---@diagnostic disable: undefined-global, lowercase-global

-- server/exports.lua — API publica para outros resources.
-- Mutadores validam invoker (_invoker_allowed); leitura e publica.
-- Mantem compat com os nomes do stub antigo (giveItem/takeItem/hasItem/chaves).

local Backpack = Inventory.Bag
local ItemUse  = Inventory.ItemUse
local Cat      = Inventory.Catalog
local CATALOG_SNAPSHOT_TRUSTED = { ['vhub_coinshop'] = true, ['vhub_admin'] = true }

local function copyDef(def)
  if type(def) ~= 'table' then return nil end
  local out = {}
  for k, v in pairs(def) do
    if type(k) == 'string' and (type(v) == 'string' or type(v) == 'number'
        or type(v) == 'boolean') then
      out[k] = v
    end
  end
  return out
end

local function catalogSnapshot()
  local out = {}
  for id, def in pairs(Inventory.Items) do
    if type(id) == 'string' and type(def) == 'table' then
      out[#out + 1] = {
        id       = id,
        name     = tostring(def.nome or id):sub(1, 100),
        category = tostring(def.categoria or ''):sub(1, 32),
      }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end


-- ============================================================
-- CONTROLE DE INVOCADOR
-- ============================================================

-- libera somente resource explicitamente confiável; ausência de trust falha fechada
local function _invoker_allowed(caller)
  local trust = Inventory.TrustedResources
  if type(trust) ~= 'table' or next(trust) == nil then return false end
  caller = caller or GetInvokingResource()
  if type(caller) ~= 'string' or caller == '' then return false end
  return trust[caller] == true
end


-- ============================================================
-- LEITURA (publica)
-- ============================================================

-- retorna uma cópia enxuta e ordenada do catálogo para importadores autorizados
exports('getCatalogSnapshot', function()
  local caller = GetInvokingResource()
  if caller and caller ~= GetCurrentResourceName() and not CATALOG_SNAPSHOT_TRUSTED[caller] then
    return {}
  end

  return catalogSnapshot()
end)

exports('getItemsSnapshot', function()
  local caller = GetInvokingResource()
  if caller and caller ~= GetCurrentResourceName() and not CATALOG_SNAPSHOT_TRUSTED[caller] then
    return {}
  end
  return catalogSnapshot()
end)

-- retorna { slots, weight, max, size } da mochila (copia ao cruzar resource)
exports('getInventory', function(src)
  return Backpack.snapshot(src) or { slots = {}, weight = 0, max = 0, size = 0 }
end)

exports('getItemAmount',  function(src, id)      return Backpack.amount(src, id)        end)
exports('hasItem',        function(src, id, qty) return Backpack.has(src, id, qty)      end)
exports('getInventoryWeight', function(src)      return Backpack.weight(src)            end)
exports('getItemDef',     function(id)           return copyDef(Cat.def(id))            end)
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

-- Retira quantidade de um slot validado para domínios que preservam metadata.
exports('takeItemFromSlot', function(src, slot, amount)
  if not _invoker_allowed() then return false end
  src, slot, amount = tonumber(src), tonumber(slot), tonumber(amount)
  if not src or not slot or slot % 1 ~= 0 or not amount or amount % 1 ~= 0 then return false end
  if amount < 1 or amount > 1000 then return false end
  return Backpack.takeFromSlot(src, slot, amount) == true
end)

-- registra função legada ou nome de export síncrono do dono do domínio
exports('registerItemUse', function(id, handler)
  local caller = GetInvokingResource()
  if not _invoker_allowed(caller) then return false end
  return ItemUse.register(id, handler, caller) == true
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
  plate = Inventory.Utils.normalizePlate(plate)
  if not plate then return false end
  return (Backpack.give(src, 'veh_key', 1, { plate = plate })) == true
end)

exports('hasVehicleKey', function(src, plate)
  plate = Inventory.Utils.normalizePlate(plate)
  if not plate then return false end
  local snap = Backpack.snapshot(src); if not snap then return false end
  for _, e in pairs(snap.slots) do
    if e.id == 'veh_key' and e.meta and Inventory.Utils.normalizePlate(e.meta.plate) == plate then return true end
  end
  return false
end)

exports('takeVehicleKey', function(src, plate)
  if not _invoker_allowed() then return false end
  plate = Inventory.Utils.normalizePlate(plate)
  if not plate then return false end
  local snap = Backpack.snapshot(src); if not snap then return false end
  for slot, e in pairs(snap.slots) do
    if e.id == 'veh_key' and e.meta and Inventory.Utils.normalizePlate(e.meta.plate) == plate then
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
