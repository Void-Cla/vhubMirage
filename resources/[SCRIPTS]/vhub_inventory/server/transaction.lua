---@diagnostic disable: undefined-global, lowercase-global

-- server/transaction.lua — primitivas CAS: slot-lock e op dedup (F3, gated).
-- slot-lock: mutex in-memory por (owner_ref, slot); evita mutações concorrentes no mesmo slot.
-- op dedup: verifica vhub_inv_ops antes de executar; persiste resultado para retry idempotente.
-- Op dedup requer thread (usa Citizen.Await via SQL); slot-lock é síncrono.
if GetConvar('inventory_vnext', '0') ~= '1' then return end

local M = {}; Inventory.Transaction = M

local _locks = {}   -- [key] = true — slot-locks in-memory


-- ============================================================
-- SLOT-LOCK (síncrono, in-memory)
-- ============================================================

-- adquire lock de slot; retorna chave ou nil se já bloqueado.
-- owner_ref = "player:<char_id>" | "container:<cid>"
function M.lockSlot(owner_ref, slot)
  local key = tostring(owner_ref) .. ':' .. tostring(slot)
  if _locks[key] then return nil end
  _locks[key] = true
  return key
end

-- libera lock de slot adquirido por lockSlot
function M.unlockSlot(key)
  if key then _locks[key] = nil end
end


-- ============================================================
-- OP DEDUP (assíncrono — usar dentro de CreateThread)
-- ============================================================

-- executa fn() com garantia de idempotência por (actor, session_id, request_id, action).
-- Retorna resultado cacheado se já processado, ou executa fn() e persiste.
-- payload_fp = fingerprint do payload (U.checksum(U.canonicalJson(payload)) recomendado).
-- REQUER contexto de thread (usa Citizen.Await via SQL.query/execute).
function M.guarded(actor, session_id, request_id, action, payload_fp, fn)
  local SQL = Inventory.SQL

  -- verifica dedup (hit = retorna resultado anterior sem reprocessar)
  local existing = SQL.query(
    'SELECT result FROM vhub_inv_ops WHERE actor=? AND session_id=? AND request_id=? AND action=? LIMIT 1',
    { actor, session_id, request_id, action }
  )
  if existing and existing[1] then
    return existing[1].result == 1
  end

  -- executa fn com proteção de erro
  local ok, result = pcall(fn)
  if not ok then
    Inventory.Utils.quarantine(actor, 'transaction.guarded', tostring(result))
    result = false
  end

  -- registra resultado (IGNORE para race condition de retry concorrente)
  local op_id = ('inv' .. tostring(GetGameTimer()):sub(-10) .. tostring(math.random(10000, 99999))):sub(1, 26)
  SQL.execute(
    [[INSERT IGNORE INTO vhub_inv_ops
      (op_id, actor, session_id, request_id, action, payload_fingerprint, result, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 24 HOUR))]],
    { op_id, actor, session_id, request_id, action, payload_fp or '', result and 1 or 0 }
  )

  return result
end
