---@diagnostic disable: undefined-global, lowercase-global

-- server/state.lua — kernel de estado VRAM do inventário (F2, gated por inventory_vnext).
-- Escritor único de persistência (L-13). Retorna early se vnext desativado.
if GetConvar('inventory_vnext', '0') ~= '1' then return end

local M = {}; Inventory.State = M

local SQL      = nil   -- lazy-ref para evitar ordem de boot circular
local U        = Inventory.Utils

-- ============================================================
-- CONSTANTES
-- ============================================================

local PAYLOAD_CAP  = 60 * 1024   -- 60 KB — hard cap antes de encode
local RETRY_MAX    = 5
local RETRY_BASE   = 500          -- ms
local STATES       = { IDLE = 'idle', LOADING = 'loading', READY = 'ready', DRAINING = 'draining' }

-- ============================================================
-- VRAM OWNERS
-- ============================================================
-- owner = {
--   id            : int (char_id),
--   state         : table (slots, hotbar) — única cópia autorizada em RAM,
--   revision      : int  — incrementa a cada mutação confirmada,
--   persisted_rev : int  — última revision ack pelo SQL,
--   generation    : int  — invalida callbacks de carga anterior,
--   loading       : promise|nil — singleflight,
--   in_flight     : bool — flush em progresso,
--   dirty         : bool — true se revision > persisted_rev,
--   retries       : int,
--   poisoned      : bool — bloqueia mutações; estado legível,
--   drain_cbs     : {fn} — fila de callbacks esperando drain,
-- }

local _owners = {}   -- [char_id] = owner


-- ============================================================
-- HELPERS INTERNOS
-- ============================================================

local function get_sql()
  if not SQL then SQL = Inventory.SQL end
  return SQL
end

-- cria owner vazio na primeira carga (nunca exposto sem load() completo)
local function new_owner(char_id)
  return {
    id           = char_id,
    state        = { slots = {}, hotbar = {} },
    revision     = 0,
    persisted_rev = 0,
    generation   = 0,
    loading      = nil,
    in_flight    = false,
    dirty        = false,
    retries      = 0,
    poisoned     = false,
    drain_cbs    = {},
  }
end

-- ============================================================
-- FLUSH INTERNO
-- ============================================================

local function do_flush(char_id)
  local owner = _owners[char_id]
  if not owner or owner.in_flight or owner.poisoned or not owner.dirty then return end

  -- snapshot imutável para o flush (mutation continua incrementando revision)
  local snap_rev = owner.revision
  local snap     = U.deepcopy(owner.state)

  -- hard cap de payload
  local encoded = U.canonicalJson(snap)
  if #encoded > PAYLOAD_CAP then
    U.quarantine(char_id, 'do_flush', ('payload %d bytes > cap %d'):format(#encoded, PAYLOAD_CAP))
    owner.poisoned = true
    return
  end

  owner.in_flight = true

  CreateThread(function()
    local ok, err = pcall(get_sql().savePlayerRevision, get_sql(),
      char_id, snap.slots, snap.hotbar, snap_rev)

    if not ok then
      owner.retries = (owner.retries or 0) + 1
      if owner.retries >= RETRY_MAX then
        U.quarantine(char_id, 'do_flush:deadletter',
          ('max retries atingido: %s'):format(tostring(err)))
        owner.poisoned = true
      else
        -- backoff com jitter simples
        local delay = RETRY_BASE * (2 ^ (owner.retries - 1)) + math.random(0, 100)
        Wait(delay)
      end
      owner.in_flight = false
      return
    end

    owner.retries = 0
    owner.in_flight = false
    owner.persisted_rev = snap_rev

    -- ACK gated: limpa dirty somente se não houve nova mutação durante o flush
    if owner.revision == snap_rev then
      owner.dirty = false
    end

    -- drain: notifica callbacks (playerDropped esperando flush final)
    if owner.state == STATES.DRAINING or #owner.drain_cbs > 0 then
      local cbs = owner.drain_cbs
      owner.drain_cbs = {}
      for _, cb in ipairs(cbs) do
        local ok2, err2 = pcall(cb)
        if not ok2 then
          U.quarantine(char_id, 'do_flush:drain_cb', tostring(err2))
        end
      end
    end
  end)
end


-- ============================================================
-- API PÚBLICA
-- ============================================================

-- carrega o personagem (singleflight); chama cb(slots, hotbar) ao terminar.
-- Seguro chamar múltiplas vezes (o mesmo load é compartilhado).
function M.load(char_id, cb)
  local owner = _owners[char_id]

  -- já carregado: entrega imediatamente
  if owner and owner.state and not owner.loading then
    if cb then cb(owner.state.slots, owner.state.hotbar) end
    return
  end

  -- cria owner e inicia carga
  if not owner then
    owner = new_owner(char_id)
    owner.generation = 1
    _owners[char_id] = owner
  end

  -- singleflight: cola no promise existente
  if owner.loading then
    if cb then
      -- guarda geração atual para detectar stale
      local gen = owner.generation
      local p = owner.loading
      CreateThread(function()
        Citizen.Await(p)
        -- geração pode ter mudado se unload/reload ocorreu
        if cb and _owners[char_id] and _owners[char_id].generation == gen then
          cb(_owners[char_id].state.slots, _owners[char_id].state.hotbar)
        end
      end)
    end
    return
  end

  -- inicia carga
  local gen = owner.generation
  local p   = promise.new()
  owner.loading = p

  CreateThread(function()
    local slots, hotbar, revision = get_sql():loadPlayerRevision(char_id)

    -- geração pode ter mudado durante a espera SQL (unload ocorreu)
    local cur = _owners[char_id]
    if not cur or cur.generation ~= gen then
      p:resolve(false)
      return
    end

    if slots then
      cur.state         = { slots = slots, hotbar = hotbar or {} }
      cur.revision      = revision or 0
      cur.persisted_rev = revision or 0
    end
    cur.loading = nil
    -- cb ANTES de p:resolve: garante que _sess do chamador está pronto
    -- antes de qualquer singleflight waiter acordar
    if cb then cb(cur.state.slots, cur.state.hotbar) end
    p:resolve(true)
  end)
end

-- retorna cópia profunda do estado atual (ou nil se não carregado)
function M.snapshot(char_id)
  local owner = _owners[char_id]
  if not owner or owner.loading then return nil end
  return U.deepcopy(owner.state)
end

-- true se owner carregado e pronto
function M.isLoaded(char_id)
  local owner = _owners[char_id]
  return owner ~= nil and owner.loading == nil
end

-- marca como sujo (precisa de flush)
function M.markDirty(char_id)
  local owner = _owners[char_id]
  if owner then owner.dirty = true end
end

-- incrementa revision + marca dirty; retorna nova revision ou nil se não carregado/envenenado
function M.bumpRevision(char_id)
  local owner = _owners[char_id]
  if not owner or owner.poisoned then return nil end
  owner.revision = owner.revision + 1
  owner.dirty    = true
  return owner.revision
end

-- dispara flush imediato se idle e sujo
function M.flush(char_id)
  local owner = _owners[char_id]
  if not owner or not owner.dirty then return end
  do_flush(char_id)
end

-- percorre todos os owners e flush os sujos (onResourceStop)
function M.flushAll()
  for char_id in pairs(_owners) do
    M.flush(char_id)
  end
end

-- aguarda flush pendente e chama cb(); usado no playerDropped para não perder dado
function M.drain(char_id, cb)
  local owner = _owners[char_id]
  if not owner then
    if cb then cb() end
    return
  end

  if not owner.dirty and not owner.in_flight then
    if cb then cb() end
    return
  end

  -- enfileira callback e dispara flush se ocioso
  if cb then owner.drain_cbs[#owner.drain_cbs + 1] = cb end
  if not owner.in_flight then do_flush(char_id) end
end

-- remove owner da VRAM (bump geração invalida callbacks antigos)
function M.unload(char_id)
  local owner = _owners[char_id]
  if owner then owner.generation = owner.generation + 1 end
  _owners[char_id] = nil
end

-- aplica mutação direta ao estado em VRAM (L-13: só o State escreve)
-- slots deve ser a tabela completa de slots (cópia profunda feita aqui)
function M.applySlots(char_id, slots, hotbar)
  local owner = _owners[char_id]
  if not owner or owner.poisoned then return false end
  owner.state.slots  = U.deepcopy(slots)
  if hotbar ~= nil then owner.state.hotbar = U.deepcopy(hotbar) end
  return true
end
