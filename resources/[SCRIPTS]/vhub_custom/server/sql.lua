-- server/sql.lua — persistência atômica do ledger de operações do vhub_custom
---@diagnostic disable: undefined-global

VHubCustom.SQL = { ready = false }
local SQL = VHubCustom.SQL

local function encode(value)
  local ok, encoded = pcall(json.encode, value == nil and {} or value)
  if not ok or type(encoded) ~= 'string' or #encoded > 8192 then return nil end
  return encoded
end

local function ensureColumn(columnName, definition)
  local exists = MySQL.scalar.await([[
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'vh_custom_operations' AND COLUMN_NAME = ?
  ]], { columnName })
  if tonumber(exists) and tonumber(exists) > 0 then return true end
  MySQL.query.await(('ALTER TABLE vh_custom_operations ADD COLUMN `%s` %s')
    :format(columnName, definition))
  return true
end

local function migratePendingGuards()
  local migrationError
  local called, committed = pcall(MySQL.startTransaction, function(query)
    local pending = query([[
      SELECT plate, operation_id
      FROM vh_custom_operations
      WHERE state IN ('prepared','charged')
      ORDER BY plate, operation_id
      LIMIT 10001
      FOR UPDATE
    ]])
    if pending and #pending > 10000 then migrationError = 'legacy_pending_overflow'; return false end
    local seen = {}
    for _, row in ipairs(pending or {}) do
      if seen[row.plate] then
        migrationError = 'legacy_pending_conflict:' .. tostring(row.plate)
        return false
      end
      seen[row.plate] = true
    end
    query([[
      INSERT IGNORE INTO vh_custom_operation_guards (plate, operation_id)
      SELECT plate, operation_id FROM vh_custom_operations
      WHERE state IN ('prepared','charged')
    ]])
    local mismatch = query([[
      SELECT o.plate
      FROM vh_custom_operations o
      LEFT JOIN vh_custom_operation_guards g
        ON g.plate = o.plate AND g.operation_id = o.operation_id
      WHERE o.state IN ('prepared','charged') AND g.operation_id IS NULL
      LIMIT 1
      FOR UPDATE
    ]])
    if mismatch and mismatch[1] then
      migrationError = 'legacy_guard_mismatch:' .. tostring(mismatch[1].plate)
      return false
    end
    return true
  end)
  if not called or committed ~= true then error(migrationError or 'legacy_guard_storage') end
end

-- aplica o schema idempotente do ledger de saga.
function SQL.applySchema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if type(schema) ~= 'string' or schema == '' then return false, 'schema_missing' end
  local called, err = pcall(function()
    MySQL.query.await(schema)
    ensureColumn('claim_token', 'VARCHAR(32) NULL AFTER `state`')
    ensureColumn('claim_until', 'TIMESTAMP NULL AFTER `claim_token`')
    migratePendingGuards()
  end)
  SQL.ready = called
  return called, called and nil or tostring(err or 'storage')
end

-- cria ou recupera uma operação pela chave única de request.
function SQL.prepare(data)
  if not SQL.ready then return nil, 'storage' end
  local payloadJson, beforeJson, afterJson = encode(data.payload), encode(data.before), encode(data.after)
  if not payloadJson or not beforeJson or not afterJson then return nil, 'invalid_payload' end
  local outcome = { err = 'storage' }
  local called, committed = pcall(MySQL.startTransaction, function(query)
    query([[
      INSERT IGNORE INTO vh_custom_operation_guards (plate, operation_id)
      VALUES (?, ?)
    ]], { data.plate, data.operation_id })
    local guards = query([[
      SELECT operation_id FROM vh_custom_operation_guards WHERE plate = ? FOR UPDATE
    ]], { data.plate })
    local guard = guards and guards[1]
    if not guard then return false end
    if tostring(guard.operation_id) ~= data.operation_id then
      local guardedRows = query([[
        SELECT state FROM vh_custom_operations WHERE operation_id = ? FOR UPDATE
      ]], { guard.operation_id })
      local guarded = guardedRows and guardedRows[1]
      if guarded and guarded.state ~= 'applied' and guarded.state ~= 'refunded' then
        outcome = { err = 'busy' }
        return false
      end
      query([[
        UPDATE vh_custom_operation_guards SET operation_id = ?
        WHERE plate = ? AND operation_id = ?
      ]], { data.operation_id, data.plate, guard.operation_id })
    end

    query([[
      INSERT IGNORE INTO vh_custom_operations
        (operation_id, request_key, source_id, char_id, plate, model_hash, domain, action,
         semantic_digest, amount, payload_json, before_json, after_json, state)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'prepared')
    ]], { data.operation_id, data.request_key, data.source_id, data.char_id, data.plate, data.model_hash,
      data.domain, data.action, data.semantic_digest, data.amount, payloadJson, beforeJson, afterJson })

    local rows = query([[
      SELECT operation_id, request_key, source_id, char_id, plate, model_hash, domain, action,
             semantic_digest, amount, payload_json, before_json, after_json, state,
             claim_token, UNIX_TIMESTAMP(claim_until) AS claim_until
      FROM vh_custom_operations
      WHERE char_id = ? AND request_key = ?
      FOR UPDATE
    ]], { data.char_id, data.request_key })
    local row = rows and rows[1]
    if not row or tostring(row.operation_id) ~= data.operation_id
        or tostring(row.semantic_digest) ~= data.semantic_digest
        or tostring(row.plate) ~= data.plate or tostring(row.domain) ~= data.domain
        or tostring(row.action) ~= data.action or tonumber(row.model_hash) ~= data.model_hash then
      outcome = { err = 'conflict' }
      return false
    end
    if row.state == 'applied' or row.state == 'refunded' then
      query('DELETE FROM vh_custom_operation_guards WHERE plate = ? AND operation_id = ?',
        { data.plate, data.operation_id })
    end
    outcome = row
    return true
  end)
  if not called or committed ~= true then return nil, outcome.err end
  return outcome
end

-- adquire lease CAS exclusiva para handler ou recovery.
function SQL.claim(operationId, claimToken)
  if not SQL.ready or type(claimToken) ~= 'string' then return false end
  local changed = MySQL.update.await([[
    UPDATE vh_custom_operations
    SET claim_token = ?, claim_until = DATE_ADD(NOW(), INTERVAL 300 SECOND)
    WHERE operation_id = ? AND state IN ('prepared','charged')
      AND (claim_token IS NULL OR claim_until < NOW() OR claim_token = ?)
  ]], { claimToken, operationId, claimToken })
  return tonumber(changed) ~= nil and tonumber(changed) > 0
end

-- libera lease sem liberar o guard durável da placa.
function SQL.releaseClaim(operationId, claimToken)
  local changed = MySQL.update.await([[
    UPDATE vh_custom_operations SET claim_token = NULL, claim_until = NULL
    WHERE operation_id = ? AND claim_token = ? AND state IN ('prepared','charged')
  ]], { operationId, claimToken })
  return tonumber(changed) ~= nil and tonumber(changed) > 0
end

-- confirma a etapa financeira, inclusive para custo zero.
function SQL.markCharged(operationId, claimToken)
  local changed = MySQL.update.await([[
    UPDATE vh_custom_operations
    SET state = 'charged', claim_until = DATE_ADD(NOW(), INTERVAL 300 SECOND)
    WHERE operation_id = ? AND claim_token = ? AND state IN ('prepared','charged')
  ]], { operationId, claimToken })
  return tonumber(changed) ~= nil and tonumber(changed) > 0
end

local function terminalTransition(operationId, claimToken, targetState)
  local outcome = false
  local called, committed = pcall(MySQL.startTransaction, function(query)
    local refs = query([[
      SELECT plate FROM vh_custom_operations WHERE operation_id = ? LIMIT 1
    ]], { operationId })
    local ref = refs and refs[1]
    if not ref then return false end
    query([[
      SELECT operation_id FROM vh_custom_operation_guards WHERE plate = ? FOR UPDATE
    ]], { ref.plate })
    local rows = query([[
      SELECT plate, state, claim_token FROM vh_custom_operations
      WHERE operation_id = ? FOR UPDATE
    ]], { operationId })
    local row = rows and rows[1]
    if not row then return false end
    if row.state == targetState then
      query('DELETE FROM vh_custom_operation_guards WHERE plate = ? AND operation_id = ?',
        { row.plate, operationId })
      outcome = true
      return true
    end
    local allowed = targetState == 'applied' and row.state == 'charged'
      or targetState == 'refunded' and (row.state == 'prepared' or row.state == 'charged')
    if not allowed or tostring(row.claim_token or '') ~= claimToken then return false end
    local changed = query([[
      UPDATE vh_custom_operations
      SET state = ?, claim_token = NULL, claim_until = NULL
      WHERE operation_id = ? AND claim_token = ? AND state = ?
    ]], { targetState, operationId, claimToken, row.state })
    if not changed or tonumber(changed.affectedRows) ~= 1 then return false end
    query('DELETE FROM vh_custom_operation_guards WHERE plate = ? AND operation_id = ?',
      { row.plate, operationId })
    outcome = true
    return true
  end)
  return called and committed == true and outcome == true
end

-- encerra a saga depois da mutação autoritativa.
function SQL.markApplied(operationId, claimToken)
  return terminalTransition(operationId, claimToken, 'applied')
end

-- encerra a saga compensada sem permitir reaplicação futura.
function SQL.markRefunded(operationId, claimToken)
  return terminalTransition(operationId, claimToken, 'refunded')
end

-- retorna lote limitado de operações abandonadas para reconciliação.
function SQL.recoverable(beforeUnix, limit)
  if not SQL.ready then return {} end
  return MySQL.query.await([[
    SELECT operation_id, request_key, source_id, char_id, plate, model_hash, domain, action,
           semantic_digest, amount, payload_json, before_json, after_json, state
    FROM vh_custom_operations
    WHERE state IN ('prepared','charged') AND updated_at < FROM_UNIXTIME(?)
      AND (claim_token IS NULL OR claim_until < NOW())
    ORDER BY updated_at ASC
    LIMIT ?
  ]], { beforeUnix, math.min(math.max(tonumber(limit) or 20, 1), 50) }) or {}
end

return SQL
