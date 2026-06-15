---@diagnostic disable: undefined-global, lowercase-global

-- shared/utils.lua — helpers PUROS (sem side-effect), usados por client e server.
-- Calculo de peso e regras de slot vivem aqui pois a NUI (otimista) e o servidor
-- (autoritativo) precisam da MESMA matematica. Fonte unica de calculo.

Inventory.Utils = {}
local U = Inventory.Utils


-- ============================================================
-- CATALOGO
-- ============================================================

-- retorna a definicao (tags) de um item, ou nil se nao existir
function U.itemDef(id)
  return type(id) == 'string' and Inventory.Items[id] or nil
end

-- item empilha?
function U.isStackable(id)
  local d = U.itemDef(id)
  return d ~= nil and d.stack == true
end

-- teto da pilha (1 quando nao empilha)
function U.stackMax(id)
  local d = U.itemDef(id)
  if not d or not d.stack then return 1 end
  return d.max or 999
end


-- ============================================================
-- VALIDACAO (anti-exploit)
-- ============================================================

-- coage e valida quantidade: inteiro >= 1, opcionalmente limitada por maxv.
-- retorna numero valido ou nil (rejeita negativo, fracao e lixo).
function U.validQty(q, maxv)
  q = tonumber(q)
  if not q then return nil end
  q = math.floor(q)
  if q < 1 then return nil end
  if maxv and q > maxv then q = maxv end
  return q
end

-- indice de slot valido dentro do tamanho declarado
function U.validSlot(slot, size)
  slot = tonumber(slot)
  if not slot then return nil end
  slot = math.floor(slot)
  if slot < 1 or slot > (size or 0) then return nil end
  return slot
end


-- ============================================================
-- PESO E OCUPACAO
-- ============================================================

-- soma o peso de uma tabela de slots { [i]={id,amount} } (derivado, nunca salvo)
function U.calcWeight(slots)
  local w = 0.0
  for _, e in pairs(slots or {}) do
    local d = U.itemDef(e.id)
    if d then w = w + (d.peso or 0) * (e.amount or 0) end
  end
  return w
end

-- numero de slots ocupados
function U.slotsUsed(slots)
  local n = 0
  for _ in pairs(slots or {}) do n = n + 1 end
  return n
end


-- ============================================================
-- BUSCA DE SLOT (stacking / espaco livre)
-- ============================================================

-- acha um slot que ja tem `id` empilhavel com espaco; retorna indice ou nil
function U.findStack(slots, id, want)
  if not U.isStackable(id) then return nil end
  local cap = U.stackMax(id)
  for i, e in pairs(slots or {}) do
    if e.id == id and (e.amount + (want or 0)) <= cap then
      return i
    end
  end
  return nil
end

-- primeiro slot vazio dentro de `size`; retorna indice ou nil (cheio)
function U.firstEmpty(slots, size)
  for i = 1, (size or 0) do
    if not slots[i] then return i end
  end
  return nil
end


-- ============================================================
-- COPIA (snapshots de rollback)
-- ============================================================

-- converte changes{ [slot]=entry|false } em LISTA de fio (slot embutido).
-- Evita a ambiguidade do json.encode (tabela contigua viraria array 0-based).
function U.wireList(changes)
  local list = {}
  for slot, e in pairs(changes or {}) do
    if e == false then list[#list + 1] = { slot = slot, clear = true }
    else list[#list + 1] = { slot = slot, id = e.id, amount = e.amount, meta = e.meta } end
  end
  return list
end


-- copia rasa-recursiva de uma entry de slot (id, amount, meta)
function U.copyEntry(e)
  if not e then return nil end
  local m = nil
  if e.meta then
    m = {}
    for k, v in pairs(e.meta) do m[k] = v end
  end
  return { id = e.id, amount = e.amount, meta = m }
end
