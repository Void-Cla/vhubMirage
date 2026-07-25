---@diagnostic disable: undefined-global, lowercase-global

-- server/items.lua — acesso ao catalogo + geracao de serial + montagem de entry.
-- O catalogo (tags) e DADO de config; este modulo so consulta e cria instancias.

local M = {}; Inventory.Catalog = M
local U = Inventory.Utils

local _serialSeq = 0


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
  _serialSeq = (_serialSeq + 1) % 0xFFFFFF
  return ('%s-%x-%x-%x'):format(id, os.time(), GetGameTimer(), _serialSeq)
end

-- cria uma entry de slot { id, amount, meta }. Se o item tem tag serial e nao
-- veio serial na meta, gera um. Meta vinda do cliente NUNCA chega aqui (so server).
function M.makeEntry(id, amount, meta)
  local d = U.itemDef(id)
  if not d then return nil end

  local m = U.copyEntry({ id = id, amount = amount, meta = meta }).meta
  if d.serial then
    m = m or {}
    m.serial = m.serial or M.genSerial(id)
  end

  return { id = id, amount = amount, meta = m }
end
