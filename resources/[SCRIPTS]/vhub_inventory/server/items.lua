---@diagnostic disable: undefined-global, lowercase-global

-- server/items.lua — acesso ao catalogo + geracao de serial + montagem de entry.
-- O catalogo (tags) e DADO de config; este modulo so consulta e cria instancias.

local M = {}; Inventory.Catalog = M
local U = Inventory.Utils


-- ============================================================
-- CONSULTA
-- ============================================================

-- item existe no catalogo?
function M.exists(id)
  return U.itemDef(id) ~= nil
end

-- definicao (tags) do item, ou nil
function M.def(id)
  return U.itemDef(id)
end

-- peso unitario do item (0 se desconhecido)
function M.weight(id)
  local d = U.itemDef(id)
  return d and d.peso or 0
end


-- ============================================================
-- INSTANCIAS
-- ============================================================

-- gera serial unico server-side (anti-dupe de itens valiosos)
function M.genSerial(id)
  return ('%s-%x%x'):format(id, os.time(), math.random(0, 0xFFFFFF))
end

-- cria uma entry de slot { id, amount, meta }. Se o item tem tag serial e nao
-- veio serial na meta, gera um. Meta vinda do cliente NUNCA chega aqui (so server).
function M.makeEntry(id, amount, meta)
  local d = U.itemDef(id)
  if not d then return nil end

  local m = nil
  if meta then
    m = {}
    for k, v in pairs(meta) do m[k] = v end
  end
  if d.serial then
    m = m or {}
    m.serial = m.serial or M.genSerial(id)
  end

  return { id = id, amount = amount, meta = m }
end
