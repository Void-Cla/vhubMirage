---@diagnostic disable: undefined-global, lowercase-global

-- shared/utils.lua — helpers PUROS (sem side-effect), usados por client e server.
-- Calculo de peso e regras de slot vivem aqui pois a NUI e o servidor
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

-- valida quantidade numerica: inteiro >= 1, opcionalmente limitada por maxv.
function U.validQty(q, maxv)
  if type(q) ~= 'number' then return nil end
  if q ~= q or q == math.huge or q == -math.huge then return nil end
  if q % 1 ~= 0 then return nil end
  if q < 1 then return nil end
  if maxv and q > maxv then return nil end
  return q
end

-- indice de slot valido dentro do tamanho declarado
function U.validSlot(slot, size)
  if type(slot) ~= 'number' then return nil end
  if slot ~= slot or slot == math.huge or slot == -math.huge then return nil end
  if slot % 1 ~= 0 then return nil end
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
    else
      local copy = U.copyEntry(e)
      list[#list + 1] = { slot = slot, id = copy.id, amount = copy.amount, meta = copy.meta }
    end
  end
  return list
end


-- copia rasa-recursiva de uma entry de slot (id, amount, meta)
function U.copyEntry(e)
  if not e then return nil end
  local m = nil
  if type(e.meta) == 'table' then
    m = {}
    for k, v in pairs(e.meta) do
      local vt = type(v)
      local finiteNumber = vt == 'number' and v == v and v ~= math.huge and v ~= -math.huge
      if type(k) == 'string' and (vt == 'string' or finiteNumber or vt == 'boolean') then
        m[k] = v
      end
    end
  end
  return { id = e.id, amount = e.amount, meta = m }
end

-- copia uma tabela de slots sem vazar referencia viva para outro resource.
function U.copySlots(slots)
  local out = {}
  for slot, entry in pairs(slots or {}) do out[slot] = U.copyEntry(entry) end
  return out
end

-- normaliza placa para comparar entidade, chave e storage sem confiar no cliente.
function U.normalizePlate(plate)
  if type(plate) ~= 'string' then return nil end
  local s = plate:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):upper()
  if s == '' or #s > 16 then return nil end
  return s
end


-- ============================================================
-- SERIALIZAÇÃO / INTEGRIDADE (F2 — server-only em runtime, shared na def)
-- ============================================================

-- copia profunda recursiva de uma tabela (sem metatables)
function U.deepcopy(t)
  if type(t) ~= 'table' then return t end
  local out = {}
  for k, v in pairs(t) do
    out[U.deepcopy(k)] = U.deepcopy(v)
  end
  return out
end

-- serialização canônica (JSON com chaves ordenadas) para fingerprint estável
function U.canonicalJson(t)
  if type(t) ~= 'table' then return json.encode(t) end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    if type(v) == 'table' then v = U.canonicalJson(v) else v = json.encode(v) end
    parts[#parts + 1] = json.encode(tostring(k)) .. ':' .. v
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

-- djb2 truncado a 8 hex — não criptográfico, usa apenas para detecção de drift
function U.checksum(s)
  local h = 5381
  for i = 1, #s do
    h = ((h * 33) ~ string.byte(s, i)) & 0xFFFFFFFF
  end
  return ('%08x'):format(h)
end

-- registra anomalia de deserialização sem crashar o resource.
-- Print autorizado: caminho de quarentena é emergência (logger pode não estar disponível).
-- (server-only em prática — não chamar no client)
function U.quarantine(char_id, context, reason)
  -- prefixo único facilita grep em logs de prod
  print(('[INV-QUARANTINE] char=%s ctx=%s reason=%s'):format( -- luacheck: ignore
    tostring(char_id), tostring(context), tostring(reason)))
end
