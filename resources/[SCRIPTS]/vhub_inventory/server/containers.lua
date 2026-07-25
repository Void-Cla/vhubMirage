---@diagnostic disable: undefined-global, lowercase-global

-- server/containers.lua — baús (server-authoritative): fixos, facção e porta-malas.
--
-- VERDADE: cache VRAM por container ABERTO (`_cache[cid]`), liberado quando ninguem
-- mais ve (nao infla RAM). Persistencia em vhub_inv_containers (write-through debounce
-- + flush triplo). Concorrencia: mutex `_locks[cid]` (300ms). Acesso: open-guard
-- `_open[src]` (so muta o bau que o servidor autorizou abrir). Anti-spoof de entidade.

local M = {}; Inventory.Containers = M

local U        = Inventory.Utils
local Backpack = Inventory.Bag
local E        = VHubInvE

local _cache   = {}   -- [cid] = { kind, label, slots, capacity, size, dirty, saving }
local _loading = {}   -- [cid] = promise  — singleflight de carga simultânea
local _open    = {}   -- [src] = cid (open-guard)
local _leases  = {}   -- [src] = desc autorizado + _ent (trunk); revalidado a cada mutação
local _locks   = {}   -- [cid] = token (mutex sem lease temporal)
local _viewers = {}   -- [cid] = { [src]=true }


-- ============================================================
-- MENSAGENS DE ERRO (PT-BR)
-- ============================================================

local ERR = {
  desc='Ação inválida', inexistente='Baú não encontrado', longe='Você está longe demais',
  sem_permissao='Sem permissão', veiculo='Veículo inválido', placa='Veículo sem placa',
  sem_chave='Você não tem a chave deste veículo', kind='Tipo inválido',
}
local function errMsg(e) return ERR[e] or 'Falha ao abrir o baú' end


-- ============================================================
-- MUTEX / OPEN-GUARD / VIEWERS
-- ============================================================

-- adquire o mutex do container; false se ja travado
function M.lock(cid)
  if _locks[cid] then return nil end
  local token = tostring(GetGameTimer()) .. ':' .. tostring(math.random(100000, 999999))
  _locks[cid] = token
  return token
end
function M.unlock(cid, token) if _locks[cid] == token then _locks[cid] = nil end end

-- container que o servidor autorizou este jogador a abrir (ou nil)
function M.openedBy(src) return _open[src] end

-- revalida o baú aberto contra posição, permissão, entidade, bucket e chave atuais.
function M.validateOpen(src, cid)
  if not cid or _open[src] ~= cid then return false, 'fechado' end
  local lease = _leases[src]
  if type(lease) ~= 'table' then return false, 'fechado' end
  local r, err = M.resolve(src, lease)
  if not r or r.cid ~= cid then return false, err or 'fechado' end
  return true
end

local function addViewer(cid, src) _viewers[cid] = _viewers[cid] or {}; _viewers[cid][src] = true end
local function removeViewer(cid, src) if _viewers[cid] then _viewers[cid][src] = nil end end


-- ============================================================
-- DELTA (a todos os viewers do baú — sync multi-jogador)
-- ============================================================

local function pushDelta(cid, changes)
  local v = _viewers[cid]; if not v then return end
  local items = U.wireList(changes)
  for src in pairs(v) do
    TriggerClientEvent(E.CONTAINER_DELTA, src, { cid = cid, items = items })
  end
end

-- reenvia o estado AUTORITATIVO de slots especificos a UM viewer
function M.resend(src, cid, slotList)
  local c = _cache[cid]; if not c then return end
  local changes = {}
  for _, slot in ipairs(slotList or {}) do changes[slot] = c.slots[slot] or false end
  TriggerClientEvent(E.CONTAINER_DELTA, src, { cid = cid, items = U.wireList(changes) })
end


-- ============================================================
-- PERSISTENCIA (write-through + debounce + flush triplo)
-- ============================================================

function M.flush(cid)
  local c = _cache[cid]; if not c or not c.dirty then return end
  c.dirty = false
  CreateThread(function() Inventory.SQL:saveContainer(cid, c.kind, nil, c.slots, c.capacity) end)
end

local function scheduleSave(cid)
  local c = _cache[cid]; if not c or c.saving then return end
  c.saving = true
  SetTimeout(Inventory.Save.debounce_ms or 3000, function()
    local cur = _cache[cid]; if cur then cur.saving = false; M.flush(cid) end
  end)
end

function M.markDirty(cid)
  local c = _cache[cid]; if not c then return end
  c.dirty = true; scheduleSave(cid)
end

-- flush de todos os baús sujos (onResourceStop — flush triplo #3)
function M.flushAll()
  for cid, c in pairs(_cache) do
    if c.dirty then Inventory.SQL:saveContainer(cid, c.kind, nil, c.slots, c.capacity) end
  end
end


-- ============================================================
-- LEITURA
-- ============================================================

function M.peek(cid, slot)  local c = _cache[cid]; return c and c.slots[slot] or nil end
function M.weight(cid)      local c = _cache[cid]; return c and U.calcWeight(c.slots) or 0 end
function M.capacity(cid)    local c = _cache[cid]; return c and c.capacity or 0 end
function M.size(cid)        local c = _cache[cid]; return c and c.size or 0 end

-- snapshot de fio do baú para a NUI
function M.wireSnapshot(cid)
  local c = _cache[cid]; if not c then return nil end
  local items = {}
  for slot, e in pairs(c.slots) do
    local copy = U.copyEntry(e)
    items[#items + 1] = { slot = slot, id = copy.id, amount = copy.amount, meta = copy.meta }
  end
  return {
    cid = cid, kind = c.kind, label = c.label, items = items,
    weight = U.calcWeight(c.slots), capacity = c.capacity, size = c.size,
  }
end


-- ============================================================
-- MUTACOES DE SLOT (chamadas pelo transfer, sob mutex)
-- ============================================================

-- remove de um slot do baú; retorna ok
function M.takeFromSlot(cid, slot, qty)
  local c = _cache[cid]; if not c then return false end
  local e = c.slots[slot]; if not e then return false end
  qty = U.validQty(qty, e.amount); if not qty then return false end

  local changes = {}
  local left = e.amount - qty
  if left > 0 then e.amount = left; changes[slot] = U.copyEntry(e)
  else c.slots[slot] = nil; changes[slot] = false end

  M.markDirty(cid); pushDelta(cid, changes)
  return true
end

-- coloca em um slot do baú (merge se mesmo id empilhavel); retorna ok
function M.giveToSlot(cid, slot, id, qty, meta)
  local c = _cache[cid]; if not c then return false end
  qty = U.validQty(qty); if not qty then return false end
  slot = U.validSlot(slot, c.size); if not slot then return false end
  if U.isStackable(id) then
    if meta ~= nil and qty ~= 1 then return false end
    if meta == nil and qty > U.stackMax(id) then return false end
  elseif qty ~= 1 then
    return false
  end
  local e = c.slots[slot]
  local changes = {}
  if not e then
    local entry = Inventory.Catalog.makeEntry(id, qty, meta); if not entry then return false end
    c.slots[slot] = entry
    changes[slot] = U.copyEntry(c.slots[slot])
  elseif e.id == id and U.isStackable(id) then
    if e.meta or meta then return false end
    if e.amount + qty > U.stackMax(id) then return false end
    e.amount = e.amount + qty; changes[slot] = U.copyEntry(e)
  else
    return false
  end
  M.markDirty(cid); pushDelta(cid, changes)
  return true
end

-- escolhe slot de destino para id/qty: slot pedido (se valido) > stack existente > 1o vazio
function M.findDest(cid, id, qty, prefer, meta)
  local c = _cache[cid]; if not c then return nil end
  prefer = U.validSlot(prefer, c.size)               -- nunca confiar em slot fora de faixa
  if prefer then
    local e = c.slots[prefer]
    if not e then return prefer end
    if meta ~= nil then return nil end
    if e.id == id and U.isStackable(id) and (e.amount + qty) <= U.stackMax(id) then return prefer end
  end
  if meta ~= nil then return U.firstEmpty(c.slots, c.size) end
  local st = U.findStack(c.slots, id, qty); if st then return st end
  return U.firstEmpty(c.slots, c.size)
end


-- ============================================================
-- PERMISSAO / ACESSO
-- ============================================================

-- permissao de grupo (vhub_groups, soft dep)
local function hasPerm(src, perm)
  if not perm then return true end
  local ok, res = pcall(function() return exports.vhub_groups:hasPermission(src, perm) end)
  return ok and res == true
end

-- registro do veiculo no conce (fonte canonica de placa/posse), ou nil
local function garageVehicle(plate)
  local ok, veh = pcall(function() return exports.vhub_conce:getVehicle(plate) end)
  return (ok and veh) or nil
end

-- acesso a chave fisica pertence ao vhub_conce:canOperate.

-- acesso ao porta-malas: contrato canonico exclusivo do conce.
local function trunkAccess(src, plate)
  local ok, allowed = pcall(function() return exports.vhub_conce:canOperate(src, plate) end)
  return ok and allowed == true
end

-- capacidade pelo TIPO do registro do garage (NAO GetVehicleClass server-side)
local function trunkCapacity(veh)
  local cap = Inventory.Trunk.base_capacity or 40.0
  if veh and veh.vtype and Inventory.Trunk.vtype_mult[veh.vtype] then
    cap = cap * Inventory.Trunk.vtype_mult[veh.vtype]
  end
  return cap
end

-- valida o porta-malas server-side: entidade, tipo, vida, placa, bucket e distancia.
-- Coordenada NUNCA vem do cliente — so o netId, que o servidor resolve.
-- Regra efetiva: falha fecha; placa vem da entidade server-side.
local function resolveTrunkEntity(src, netId)
  if type(netId) ~= 'number' or netId % 1 ~= 0 or netId < 1 then return nil, 'veiculo' end

  local ok, ent = pcall(NetworkGetEntityFromNetworkId, netId)
  if not ok or not ent or ent == 0 or not DoesEntityExist(ent) then return nil, 'veiculo' end
  if GetEntityType(ent) ~= 2 then return nil, 'veiculo' end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 or GetEntityHealth(ped) <= 101 then return nil, 'longe' end

  local okPlate, rawPlate = pcall(GetVehicleNumberPlateText, ent)
  local plate = okPlate and U.normalizePlate(rawPlate) or nil
  if not plate then return nil, 'placa' end

  local okVPos, vpos = pcall(GetEntityCoords, ent)
  local okPPos, ppos = pcall(GetEntityCoords, ped)
  if not okVPos or not okPPos or not vpos or not ppos then return nil, 'longe' end
  if #(ppos - vpos) > (Inventory.Trunk.range or 2.5) then return nil, 'longe' end

  local okPB, pBucket = pcall(GetPlayerRoutingBucket, src)
  local okEB, eBucket = pcall(GetEntityRoutingBucket, ent)
  if not okPB or not okEB or pBucket ~= eBucket then return nil, 'longe' end

  return { ent = ent, plate = plate, netId = netId }, nil
end


-- ============================================================
-- RESOLVER PEDIDO DE ABERTURA (proximidade + permissao + anti-spoof)
-- ============================================================

-- retorna { cid, kind, capacity, size, label } ou nil, err
function M.resolve(src, desc)
  if type(desc) ~= 'table' then return nil, 'desc' end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil, 'desc' end
  local ppos = GetEntityCoords(ped)

  -- BAU FIXO / FACCAO ----------------------------------------
  if desc.kind == 'static' or desc.kind == 'faction' then
    local pool = (desc.kind == 'static') and Inventory.Chests.static or Inventory.Chests.faction
    local key  = desc.name or desc.group
    local c    = pool and key and pool[key]
    if not c then return nil, 'inexistente' end
    if #(ppos - vector3(c.coords.x, c.coords.y, c.coords.z)) > (c.range or 2.5) then return nil, 'longe' end
    if c.permission and not hasPerm(src, c.permission) then return nil, 'sem_permissao' end
    return { cid = desc.kind .. ':' .. key, kind = desc.kind,
             capacity = c.capacity or 100, size = c.size or 50, label = c.label or key,
             lease = { kind = desc.kind, name = desc.kind == 'static' and key or nil,
                       group = desc.kind == 'faction' and key or nil } }

  elseif desc.kind == 'trunk' then
    local t, terr = resolveTrunkEntity(src, desc.netId)
    if not t then return nil, terr end
    local plate = t.plate
    local veh = garageVehicle(plate)
    if not veh then return nil, 'veiculo' end
    if Inventory.Trunk.require_access and not trunkAccess(src, plate) then return nil, 'sem_chave' end
    return { cid = 'trunk:' .. plate, kind = 'trunk',
             capacity = trunkCapacity(veh), size = Inventory.Trunk.size or 40,
             label = 'Porta-malas ' .. plate,
             lease = { kind = 'trunk', netId = t.netId } }
  end

  return nil, 'kind'
end


-- ============================================================
-- LIFECYCLE (carregar / abrir / fechar)
-- ============================================================

-- carrega o baú no cache (singleflight por cid — usa Await; chamar em thread)
function M.load(cid, kind, capacity, size, label)
  if _cache[cid] then return _cache[cid] end

  -- singleflight: aguarda carga em progresso sem duplicar SQL
  if _loading[cid] then
    Citizen.Await(_loading[cid])
    return _cache[cid]
  end

  local p = promise.new()
  _loading[cid] = p

  local row = Inventory.SQL:loadContainer(cid)
  if not _cache[cid] then    -- recheck após await (race improvável mas possível)
    _cache[cid] = {
      kind = kind, label = label,
      slots = (row and row.slots) or {},
      capacity = capacity, size = size,
      dirty = false, saving = false,
    }
  end

  _loading[cid] = nil
  p:resolve(true)
  return _cache[cid]
end

-- fecha todos os viewers de porta-malas cuja entidade foi removida (entityRemoved)
function M.forceCloseTrunkEntity(entity)
  for src, _ in pairs(_open) do
    local lease = _leases[src]
    if lease and lease._ent == entity then
      M.close(src)
      TriggerClientEvent(E.CONTAINER_CLOSE, src)
    end
  end
end

-- pedido de abertura vindo do cliente (valida -> carrega -> abre -> snapshot)
function M.requestOpen(src, desc)
  if _open[src] then return end          -- ja tem baú aberto/abrindo (fecha race de duplo-open)
  local r, err = M.resolve(src, desc)
  if not r then TriggerClientEvent(E.NOTIFY, src, errMsg(err)); return end

  -- para trunk: captura handle da entidade para detectar remoção posterior (entityRemoved)
  if r.kind == 'trunk' and r.lease and r.lease.netId then
    local ok, ent = pcall(NetworkGetEntityFromNetworkId, r.lease.netId)
    if ok and ent and ent ~= 0 and DoesEntityExist(ent) then
      r.lease._ent = ent
    end
  end

  -- reserva SINCRONA antes do load assincrono (impede 2 OPEN concorrentes)
  _open[src] = r.cid
  _leases[src] = r.lease
  addViewer(r.cid, src)

  CreateThread(function()
    M.load(r.cid, r.kind, r.capacity, r.size, r.label)
    TriggerClientEvent(E.CONTAINER_OPEN, src, {
      container = M.wireSnapshot(r.cid),
      backpack  = Backpack.wireSnapshot(src),
    })
  end)
end

-- fecha o baú do jogador; libera memoria quando ninguem mais ve
function M.close(src)
  local cid = _open[src]; if not cid then return end
  _open[src] = nil
  _leases[src] = nil
  removeViewer(cid, src)

  local v = _viewers[cid]
  if not v or next(v) == nil then
    _viewers[cid] = nil
    M.flush(cid)                              -- flush triplo #2 (ultimo viewer saiu)
    if _cache[cid] and not _cache[cid].dirty then _cache[cid] = nil end  -- libera RAM
  end
end
