---@diagnostic disable: undefined-global, lowercase-global, assign-type-mismatch

-- server/backpack.lua — mochila do jogador (server-authoritative).
--
-- VERDADE: cache VRAM por jogador ONLINE (`_sess[src]`). Persistencia duravel em
-- `vhub_inv_player` via write-through (debounce + flush triplo). Liberado em
-- playerDropped (nao infla a RAM com offline). Peso e SEMPRE derivado, nunca salvo.
--
-- Toda mutacao: valida -> planeja (sem mutar) -> aplica -> delta -> marca dirty.

-- Modulo = Inventory.Bag (NAO Inventory.Backpack, que e a tabela de CONFIG/settings).
local M = {}; Inventory.Bag = M

local U   = Inventory.Utils
local Cat = Inventory.Catalog
local E   = VHubInvE

local _sess = {}     -- [src] = { char_id, slots = { [i]={id,amount,meta} }, dirty, saving }


-- ============================================================
-- AJUSTES DERIVADOS
-- ============================================================

local function maxWeight() return Inventory.Backpack and Inventory.Backpack.max_weight or 40.0 end
local function slotCount() return Inventory.Backpack and Inventory.Backpack.slots or 30 end


-- ============================================================
-- DELTA (envia so o que mudou — nunca a tabela inteira)
-- ============================================================

-- envia diff de slots para a NUI (lista de fio via helper compartilhado — DRY)
local function pushDelta(src, changes)
  TriggerClientEvent(E.DELTA, src, { scope = 'backpack', items = U.wireList(changes) })
end


-- ============================================================
-- PERSISTENCIA (write-through + debounce + flush)
-- ============================================================

-- grava agora (assincrono) se estiver sujo
function M.flush(src)
  local s = _sess[src]; if not s or not s.dirty then return end
  s.dirty = false
  local cid, slots, hb = s.char_id, s.slots, s.hotbar
  CreateThread(function() Inventory.SQL:savePlayer(cid, slots, hb) end)
end

-- agenda um unico save com debounce; coalesce mutacoes em rajada
local function scheduleSave(src)
  local s = _sess[src]; if not s or s.saving then return end
  s.saving = true
  SetTimeout(Inventory.Save.debounce_ms or 3000, function()
    local cur = _sess[src]
    if cur then cur.saving = false; M.flush(src) end
  end)
end

-- marca sujo e agenda persistencia
function M.markDirty(src)
  local s = _sess[src]; if not s then return end
  s.dirty = true
  scheduleSave(src)
end


-- ============================================================
-- LIFECYCLE DE SESSAO
-- ============================================================

-- normaliza a hotbar em array fixo de 5 (index 1-5; false = vazio).
-- Array fixo evita ambiguidade de chave do json (string vs number ao recarregar).
local function normHotbar(hb)
  local out = { false, false, false, false, false }
  if type(hb) == 'table' then
    for i = 1, 5 do
      local v = hb[i] or hb[tostring(i)]
      if type(v) == 'string' then out[i] = v end
    end
  end
  return out
end

-- carrega a mochila do personagem para o cache (chamar dentro de thread — usa Await)
function M.load(src, char_id)
  -- TROCA DE PERSONAGEM na MESMA sessao (mesmo user, outro char): faz flush do
  -- anterior ANTES de trocar. Sem isso, dados de um character vazariam/perder-se-iam
  -- para outro char do mesmo user_id. Inventario e SEMPRE por char_id (L-04).
  local prev = _sess[src]
  if prev and prev.char_id ~= char_id and prev.dirty then
    Inventory.SQL:savePlayer(prev.char_id, prev.slots, prev.hotbar)
  end

  local slots, hotbar = Inventory.SQL:loadPlayer(char_id)
  _sess[src] = {
    char_id = char_id, slots = slots or {}, hotbar = normHotbar(hotbar),
    dirty = false, saving = false,
  }
  return _sess[src].slots
end

-- libera a sessao; faz flush final se houver dado sujo (preserva o cliente)
function M.unload(src)
  local s = _sess[src]; if not s then return end
  if s.dirty then
    local cid, slots, hb = s.char_id, s.slots, s.hotbar
    CreateThread(function() Inventory.SQL:savePlayer(cid, slots, hb) end)
  end
  _sess[src] = nil
end

-- flush de todas as sessoes sujas (onResourceStop — flush triplo #3)
function M.flushAll()
  for _, s in pairs(_sess) do
    if s.dirty then Inventory.SQL:savePlayer(s.char_id, s.slots, s.hotbar) end
  end
end


-- ============================================================
-- LEITURA (read-only, O(1)/O(n) no cache; sem Await)
-- ============================================================

-- char_id (id do personagem) da sessao ativa, ou nil
function M.charId(src)
  local s = _sess[src]; return s and s.char_id or nil
end

-- entry de um slot (ou nil)
function M.peek(src, slot)
  local s = _sess[src]; return s and s.slots[slot] or nil
end

-- peso atual (derivado)
function M.weight(src)
  local s = _sess[src]; return s and U.calcWeight(s.slots) or 0
end

-- snapshot (mapa de slots) para EXPORTS de outros resources
function M.snapshot(src)
  local s = _sess[src]; if not s then return nil end
  return { slots = s.slots, weight = U.calcWeight(s.slots), max = maxWeight(), size = slotCount() }
end

-- snapshot em formato de fio (lista de itens) para abrir a NUI.
-- Chave de veiculo ganha meta.veiculo (dossie do PRONTUARIO) em COPIA — a meta
-- real do slot nunca muda (sem copia stale, L-04); leitura RAM-only no conce
-- apos o 1o hit e abrir inventario nao e hot path. Requer thread (Await no miss).
function M.wireSnapshot(src)
  local s = _sess[src]; if not s then return nil end
  local items = {}
  for slot, e in pairs(s.slots) do
    local meta = e.meta
    if e.id == 'veh_key' and meta and meta.plate then
      local ok, d = pcall(function() return exports.vhub_conce:getVehicleDossier(meta.plate) end)
      if ok and type(d) == 'table' then
        local m = {}
        for k, v in pairs(meta) do m[k] = v end
        m.veiculo = d
        meta = m
      end
    end
    items[#items + 1] = { slot = slot, id = e.id, amount = e.amount, meta = meta }
  end
  return { items = items, weight = U.calcWeight(s.slots), max = maxWeight(), size = slotCount() }
end

-- quantidade total de um item na mochila
function M.amount(src, id)
  local s = _sess[src]; if not s then return 0 end
  local n = 0
  for _, e in pairs(s.slots) do if e.id == id then n = n + e.amount end end
  return n
end

-- tem ao menos `qty`?
function M.has(src, id, qty)
  return M.amount(src, id) >= (qty or 1)
end

-- cabe `amount` de `id` sem estourar o peso maximo?
function M.canFit(src, id, amount)
  local s = _sess[src]; if not s then return false end
  local def = U.itemDef(id); if not def then return false end
  return U.calcWeight(s.slots) + (def.peso or 0) * amount <= maxWeight()
end


-- ============================================================
-- HOTBAR (atalhos 1-5)
-- ============================================================

-- lista de fio dos binds ocupados ({slot,id}) para a NUI
function M.hotbarWire(src)
  local s = _sess[src]; if not s then return {} end
  local list = {}
  for i = 1, 5 do
    if type(s.hotbar[i]) == 'string' then list[#list + 1] = { slot = i, id = s.hotbar[i] } end
  end
  return list
end

-- envia os binds da hotbar para a NUI
function M.pushHotbar(src)
  TriggerClientEvent(E.HOTBAR, src, M.hotbarWire(src))
end

-- item vinculado ao slot n (1-5) da hotbar, ou nil
function M.getBind(src, n)
  local s = _sess[src]; if not s then return nil end
  local v = s.hotbar[n]
  return (type(v) == 'string') and v or nil
end

-- vincula (id) ou limpa (id=nil) o slot n da hotbar; persiste e re-envia binds
function M.setBind(src, n, id)
  local s = _sess[src]; if not s then return false end
  n = U.validSlot(n, 5); if not n then return false end
  if id ~= nil and not Cat.exists(id) then return false end
  s.hotbar[n] = id or false
  M.markDirty(src)
  M.pushHotbar(src)
  return true
end

-- primeiro slot da mochila que contem `id` (para usar via hotbar)
function M.findItemSlot(src, id)
  local s = _sess[src]; if not s then return nil end
  for slot, e in pairs(s.slots) do if e.id == id then return slot end end
  return nil
end


-- ============================================================
-- PLANEJAMENTO (calcula mudanca SEM mutar — base do tudo-ou-nada)
-- ============================================================

-- planeja adicionar `amount` de `id`; retorna changes{ [slot]=entry } ou nil,err.
-- Nao muta. Respeita stacking, teto de pilha e slots livres.
local function planAdd(slots, id, amount, meta)
  local def = U.itemDef(id); if not def then return nil, 'item' end
  local size = slotCount()
  local changes = {}
  local remaining = amount

  local function nextEmpty()
    for i = 1, size do
      if not slots[i] and not changes[i] then return i end
    end
    return nil
  end

  if def.stack and not meta then
    local cap = def.max or 999
    -- 1) completa pilhas existentes
    for i, e in pairs(slots) do
      if remaining <= 0 then break end
      if e.id == id and e.amount < cap then
        local add = math.min(cap - e.amount, remaining)
        changes[i] = { id = id, amount = e.amount + add, meta = nil }
        remaining = remaining - add
      end
    end
    -- 2) abre novas pilhas
    while remaining > 0 do
      local empty = nextEmpty(); if not empty then return nil, 'full' end
      local add = math.min(cap, remaining)
      changes[empty] = { id = id, amount = add, meta = nil }
      remaining = remaining - add
    end
  else
    -- nao empilhavel (ou com meta): 1 slot por unidade, serial proprio
    for _ = 1, amount do
      local empty = nextEmpty(); if not empty then return nil, 'full' end
      changes[empty] = Cat.makeEntry(id, 1, meta)
    end
  end

  return changes
end

-- aplica um changes{ [slot]=entry|false } no cache
local function applyChanges(s, changes)
  for slot, entry in pairs(changes) do
    if entry == false then s.slots[slot] = nil else s.slots[slot] = entry end
  end
end


-- ============================================================
-- MUTACOES (validadas, atomicas no cache, com delta)
-- ============================================================

-- adiciona item (stack/empty). Valida peso e espaco ANTES de mutar (tudo-ou-nada).
function M.give(src, id, amount, meta)
  local s = _sess[src]; if not s then return false, 'no_session' end
  amount = U.validQty(amount); if not amount then return false, 'qty' end
  local def = U.itemDef(id); if not def then return false, 'item' end

  if U.calcWeight(s.slots) + def.peso * amount > maxWeight() then return false, 'weight' end

  local changes, err = planAdd(s.slots, id, amount, meta)
  if not changes then return false, err end

  applyChanges(s, changes)
  M.markDirty(src); pushDelta(src, changes)
  return true
end

-- remove `amount` de `id` (varre slots). Para compat de exports (take-by-id).
function M.take(src, id, amount)
  local s = _sess[src]; if not s then return false, 'no_session' end
  amount = U.validQty(amount); if not amount then return false, 'qty' end
  if M.amount(src, id) < amount then return false, 'insufficient' end

  local changes, remaining = {}, amount
  for i, e in pairs(s.slots) do
    if remaining <= 0 then break end
    if e.id == id then
      local rem = math.min(e.amount, remaining)
      local left = e.amount - rem
      changes[i] = (left > 0) and { id = id, amount = left, meta = e.meta } or false
      remaining = remaining - rem
    end
  end

  applyChanges(s, changes)
  M.markDirty(src); pushDelta(src, changes)
  return true
end

-- remove de um slot especifico (usado por uso de item e por transfer)
function M.takeFromSlot(src, slot, amount)
  local s = _sess[src]; if not s then return false end
  local e = s.slots[slot]; if not e then return false end
  amount = U.validQty(amount, e.amount); if not amount then return false end

  local changes = {}
  local left = e.amount - amount
  if left > 0 then e.amount = left; changes[slot] = U.copyEntry(e)
  else s.slots[slot] = nil; changes[slot] = false end

  M.markDirty(src); pushDelta(src, changes)
  return true
end

-- coloca em um slot especifico (reembolso de uso / transfer). Merge se mesmo id.
function M.giveToSlot(src, slot, id, amount, meta)
  local s = _sess[src]; if not s then return false end
  if not Cat.exists(id) then return false end

  local e = s.slots[slot]
  local changes = {}
  if not e then
    s.slots[slot] = { id = id, amount = amount, meta = meta }
    changes[slot] = U.copyEntry(s.slots[slot])
  elseif e.id == id and U.isStackable(id) then
    e.amount = e.amount + amount; changes[slot] = U.copyEntry(e)
  else
    return false
  end

  M.markDirty(src); pushDelta(src, changes)
  return true
end

-- mover/split/merge/swap DENTRO da mochila (intencao do drag-and-drop da NUI)
function M.move(src, from, to, qty)
  local s = _sess[src]; if not s then return false, 'no_session' end
  local size = slotCount()
  from = U.validSlot(from, size); to = U.validSlot(to, size)
  if not from or not to or from == to then return false, 'slot' end

  local a = s.slots[from]; if not a then return false, 'empty' end
  qty = U.validQty(qty, a.amount); if not qty then return false, 'qty' end

  local b = s.slots[to]
  local changes = {}

  if not b then
    -- destino vazio: move tudo ou faz split (so empilhavel)
    if qty >= a.amount then
      s.slots[to] = a; s.slots[from] = nil
    else
      if not U.isStackable(a.id) then return false, 'nosplit' end
      s.slots[to] = { id = a.id, amount = qty, meta = nil }
      a.amount = a.amount - qty
    end
    changes[from] = U.copyEntry(s.slots[from]) or false
    changes[to]   = U.copyEntry(s.slots[to])

  elseif b.id == a.id and U.isStackable(a.id) then
    -- merge respeitando teto
    local room = U.stackMax(a.id) - b.amount
    local mv = math.min(room, qty)
    if mv <= 0 then return false, 'full' end
    b.amount = b.amount + mv
    if mv >= a.amount then s.slots[from] = nil else a.amount = a.amount - mv end
    changes[from] = U.copyEntry(s.slots[from]) or false
    changes[to]   = U.copyEntry(b)

  else
    -- itens diferentes: troca (swap)
    s.slots[from] = b; s.slots[to] = a
    changes[from] = U.copyEntry(b); changes[to] = U.copyEntry(a)
  end

  M.markDirty(src); pushDelta(src, changes)
  return true
end


-- ============================================================
-- ROLLBACK (reenvia estado autoritativo dos slots tocados)
-- ============================================================

-- reenvia o estado AUTORITATIVO dos slots tocados (lista de fio) + razao PT-BR.
-- Reverte a UI otimista: o que o servidor manda aqui e a verdade.
function M.rollback(src, list, reason)
  local s = _sess[src]; if not s then return end
  local items = {}
  for _, slot in ipairs(list or {}) do
    local e = s.slots[slot]
    if e then items[#items + 1] = { slot = slot, id = e.id, amount = e.amount, meta = e.meta }
    else      items[#items + 1] = { slot = slot, clear = true } end
  end
  TriggerClientEvent(E.ROLLBACK, src, { scope = 'backpack', items = items, reason = reason or 'erro' })
end
