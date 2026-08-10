-- sql.lua — persistência exclusiva de outfits e sagas do SIMS
---@diagnostic disable: undefined-global

VHubSimsSQL = VHubSimsSQL or {}

local SQL = VHubSimsSQL


-- ============================================================
-- DRIVER
-- ============================================================

local function await(method, statement, params)
  local deferred = promise.new()
  local settled = false

  local ok = pcall(function()
    exports.oxmysql[method](exports.oxmysql, statement, params or {}, function(result)
      if settled then return end
      settled = true
      deferred:resolve({ ok = true, result = result })
    end)
  end)

  if not ok and not settled then
    settled = true
    deferred:resolve({ ok = false })
  end

  local response = Citizen.Await(deferred)
  return response.ok, response.result
end

local function query(statement, params)
  local ok, result = await('query', statement, params)
  return ok, ok and (result or {}) or nil
end

local function execute(statement, params)
  return await('execute', statement, params)
end


-- ============================================================
-- SCHEMA
-- ============================================================

-- aplica o schema próprio de forma idempotente
function SQL.applySchema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if type(schema) ~= 'string' or schema == '' then return false, 'schema_missing' end

  for statement in schema:gmatch('([^;]+);') do
    if statement:match('%S') then
      local ok = execute(statement, {})
      if not ok then return false, 'schema_failed' end
    end
  end
  return true
end


-- ============================================================
-- SAGAS
-- ============================================================

-- retorna saga pelo request id
function SQL.getSagaByRequest(requestId)
  local ok, rows = query('SELECT * FROM vhub_sims_sagas WHERE request_id = ? LIMIT 1', { requestId })
  return ok and rows[1] or nil
end

-- retorna saga pelo personagem e sessão
function SQL.getSagaBySession(charId, sessionId)
  local ok, rows = query(
    'SELECT * FROM vhub_sims_sagas WHERE char_id = ? AND session_id = ? LIMIT 1',
    { charId, sessionId }
  )
  return ok and rows[1] or nil
end

-- retorna a última saga recuperável do personagem
function SQL.getRecoverableSaga(charId)
  local ok, rows = query([[
    SELECT * FROM vhub_sims_sagas
    WHERE char_id = ? AND state IN ('prepared','charged','customized','manual_reconcile')
    ORDER BY id DESC LIMIT 1
  ]], { charId })
  return ok and rows[1] or nil
end

-- encerra estágios de criação sem sessão efêmera após queda/restart
function SQL.closeStaleCreationStages(charId, requestId)
  local ok = execute([[
    UPDATE vhub_sims_sagas
    SET state = 'refunded', last_error = 'superseded'
    WHERE char_id = ? AND mode = 'creator' AND state = 'prepared'
      AND request_id NOT LIKE 'checkout:%' AND request_id <> ?
  ]], { charId, requestId })
  return ok == true
end

-- cria saga e devolve a linha canônica; colisão não sobrescreve payload
function SQL.createSaga(spec)
  local ok = execute([[
    INSERT IGNORE INTO vhub_sims_sagas
      (char_id, request_id, session_id, mode, state, operation_id, payload, digest, amount)
    VALUES (?, ?, ?, ?, 'prepared', ?, ?, ?, ?)
  ]], {
    spec.char_id, spec.request_id, spec.session_id, spec.mode, spec.operation_id,
    spec.payload, spec.digest, spec.amount or 0,
  })
  if not ok then return nil, 'storage' end

  local row = SQL.getSagaByRequest(spec.request_id)
  if not row then return nil, 'storage' end
  if tonumber(row.char_id) ~= tonumber(spec.char_id) or row.session_id ~= spec.session_id
    or row.digest ~= spec.digest then
    return nil, 'conflict'
  end
  return row
end

-- avança a saga somente a partir de estados esperados
function SQL.transitionSaga(id, expected, nextState, lastError)
  id = tonumber(id)
  if not id or id < 1 or type(expected) ~= 'table' or #expected == 0 then return false end
  local marks = {}
  local params = { nextState, lastError, id }
  for _, state in ipairs(expected) do
    marks[#marks + 1] = '?'
    params[#params + 1] = state
  end
  local statement = ('UPDATE vhub_sims_sagas SET state = ?, last_error = ? '
    .. 'WHERE id = ? AND state IN (%s)'):format(table.concat(marks, ','))
  local ok, result = execute(statement, params)
  if not ok then return false end
  local affected = type(result) == 'table' and tonumber(result.affectedRows) or tonumber(result)
  if affected == 1 then return true end
  if affected ~= 0 then return false end
  local readOk, rows = query('SELECT state FROM vhub_sims_sagas WHERE id = ? LIMIT 1', { id })
  return readOk and rows[1] and rows[1].state == nextState or false
end

-- lista lote limitado de sagas que exigem recuperação no boot
function SQL.listRecoverableSagas(afterId, limit)
  afterId = math.max(0, math.floor(tonumber(afterId) or 0))
  limit = math.max(1, math.min(32, math.floor(tonumber(limit) or 16)))
  local ok, rows = query(([=[
    SELECT * FROM vhub_sims_sagas
    WHERE id > ? AND state IN ('charged','customized','manual_reconcile')
    ORDER BY id ASC LIMIT %d
  ]=]):format(limit), { afterId })
  return ok and rows or nil
end


-- ============================================================
-- OUTFITS
-- ============================================================

-- lista outfits visíveis do personagem
function SQL.listOutfits(charId)
  local ok, rows = query([[
    SELECT id, label, outfit, group_name, created_at, updated_at
    FROM vhub_sims_outfits WHERE char_id = ? ORDER BY updated_at DESC, id DESC
  ]], { charId })
  return ok and rows or nil
end

-- retorna outfit pertencente ao personagem
function SQL.getOutfit(charId, outfitId)
  local ok, rows = query([[
    SELECT id, label, outfit, group_name
    FROM vhub_sims_outfits WHERE id = ? AND char_id = ? LIMIT 1
  ]], { outfitId, charId })
  return ok and rows[1] or nil
end

-- conta outfits próprios do personagem
function SQL.countOutfits(charId)
  local ok, rows = query('SELECT COUNT(*) AS total FROM vhub_sims_outfits WHERE char_id = ?', { charId })
  return ok and rows[1] and tonumber(rows[1].total) or nil
end

-- salva outfit próprio
function SQL.insertOutfit(charId, label, outfit)
  local ok, result = execute([[
    INSERT INTO vhub_sims_outfits (char_id, label, outfit) VALUES (?, ?, ?)
  ]], { charId, label, outfit })
  local affected = type(result) == 'table' and tonumber(result.affectedRows) or tonumber(result)
  return ok == true and affected == 1
end

-- renomeia outfit próprio (label já normalizado pelo chamador)
function SQL.renameOutfit(charId, outfitId, label)
  local ok, result = execute(
    'UPDATE vhub_sims_outfits SET label = ? WHERE id = ? AND char_id = ?',
    { label, outfitId, charId }
  )
  local affected = type(result) == 'table' and tonumber(result.affectedRows) or tonumber(result)
  return ok == true and affected == 1
end

-- remove outfit próprio
function SQL.deleteOutfit(charId, outfitId)
  local ok, result = execute('DELETE FROM vhub_sims_outfits WHERE id = ? AND char_id = ?',
    { outfitId, charId })
  local affected = type(result) == 'table' and tonumber(result.affectedRows) or tonumber(result)
  return ok == true and affected == 1
end
