-- server/sql.lua — vhub_groups
-- Wrapper oxmysql + queries preparadas. Resource externo: NAO usa vHub.State
-- (FiveM serializa tabelas em exports e modificacoes em self._prepared nao
-- persistem cross-resource — decisao #8 do contexto.md).

VHubGroupsSQL = { ready = false }
local S = VHubGroupsSQL

-- ── Helpers async → sincrono via Citizen.Await ───────────────────────────────

-- Executa SELECT; retorna lista de linhas (vazia em falha). Loga em caso de erro.
function S.query(sql, params)
  local p = promise.new()
  exports.oxmysql:query(sql, params or {}, function(rows)
    p:resolve(rows or {})
  end)
  return Citizen.Await(p)
end

-- Executa INSERT/UPDATE/DELETE; retorna affectedRows. Erros sao logados pelo driver.
function S.execute(sql, params)
  local p = promise.new()
  exports.oxmysql:execute(sql, params or {}, function(result)
    p:resolve(result or 0)
  end)
  return Citizen.Await(p)
end

-- Executa schema (DDL multi-statement); ignora resultado.
function S.execute_raw(sql)
  local p = promise.new()
  exports.oxmysql:execute(sql, {}, function() p:resolve(true) end)
  return Citizen.Await(p)
end

-- ── SQL canonico (queries usadas pelo dominio) ───────────────────────────────

-- Carrega todos os grupos ativos (nao expirados) do char_id
function S.fetch_groups(char_id)
  return S.query([[
    SELECT group_id, level, added_by, added_at, expires_at, reason
    FROM vh_groups
    WHERE char_id = ?
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
  ]], { char_id })
end

-- Upsert (insert or update). Atualiza level/expires_at/reason quando ja existe.
function S.upsert_group(char_id, group_id, level, added_by, expires_unix, reason)
  -- expires_unix: nil = sem expiracao, > 0 = unix timestamp
  local expires_sql = nil
  if expires_unix and tonumber(expires_unix) and tonumber(expires_unix) > 0 then
    expires_sql = os.date('!%Y-%m-%d %H:%M:%S', tonumber(expires_unix))
  end

  return S.execute([[
    INSERT INTO vh_groups (char_id, group_id, level, added_by, expires_at, reason)
    VALUES (?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      level      = VALUES(level),
      added_by   = VALUES(added_by),
      expires_at = VALUES(expires_at),
      reason     = VALUES(reason)
  ]], { char_id, group_id, level, added_by or 0, expires_sql, tostring(reason or '') })
end

-- Remove grupo de um personagem
function S.delete_group(char_id, group_id)
  return S.execute(
    "DELETE FROM vh_groups WHERE char_id = ? AND group_id = ?",
    { char_id, group_id })
end

-- Remove TODOS os grupos com mesmo gtype do personagem (exclusividade job/gang)
function S.delete_groups_in(char_id, group_ids)
  if type(group_ids) ~= 'table' or #group_ids == 0 then return 0 end
  -- Constroi IN(?, ?, ?...) — necessario pois oxmysql nao expande arrays
  local placeholders = {}
  for i = 1, #group_ids do placeholders[i] = '?' end
  local sql = "DELETE FROM vh_groups WHERE char_id = ? AND group_id IN ("
              .. table.concat(placeholders, ',') .. ")"
  local params = { char_id }
  for i = 1, #group_ids do params[#params + 1] = group_ids[i] end
  return S.execute(sql, params)
end

-- Cron: remove grupos com expires_at vencido. Retorna affectedRows.
function S.delete_expired()
  return S.execute(
    "DELETE FROM vh_groups WHERE expires_at IS NOT NULL AND expires_at <= CURRENT_TIMESTAMP")
end

-- Lista todos os char_ids que tem um grupo X com nivel >= min_level (offline + online)
function S.list_chars_in_group(group_id, min_level)
  return S.query([[
    SELECT char_id, level, added_by, added_at, expires_at
    FROM vh_groups
    WHERE group_id = ?
      AND level >= ?
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
    ORDER BY level DESC, added_at ASC
    LIMIT 500
  ]], { group_id, tonumber(min_level) or 1 })
end

-- ── Audit log ────────────────────────────────────────────────────────────────

-- Append em vh_groups_audit. Fire-and-forget: nao bloqueia chamador.
function S.audit_insert(actor, target, action, group_id, level, reason)
  exports.oxmysql:execute([[
    INSERT INTO vh_groups_audit (actor_char_id, target_char_id, action, group_id, level, reason)
    VALUES (?, ?, ?, ?, ?, ?)
  ]], {
    tonumber(actor)  or 0,
    tonumber(target) or 0,
    tostring(action  or 'unknown'),
    tostring(group_id or ''),
    tonumber(level)  or 0,
    tostring(reason  or ''),
  }, function() end)
end

-- Retorna ultimas N entradas de audit, com filtros opcionais
function S.audit_fetch(filters, limit)
  filters = type(filters) == 'table' and filters or {}
  local lim = math.min(math.max(tonumber(limit) or 100, 1), 500)

  local where = {}
  local params = {}
  if tonumber(filters.target_char_id) then
    where[#where + 1] = 'target_char_id = ?'
    params[#params + 1] = tonumber(filters.target_char_id)
  end
  if tonumber(filters.actor_char_id) then
    where[#where + 1] = 'actor_char_id = ?'
    params[#params + 1] = tonumber(filters.actor_char_id)
  end
  if type(filters.action) == 'string' and filters.action ~= '' then
    where[#where + 1] = 'action = ?'
    params[#params + 1] = filters.action
  end
  if type(filters.group_id) == 'string' and filters.group_id ~= '' then
    where[#where + 1] = 'group_id = ?'
    params[#params + 1] = filters.group_id
  end

  local where_sql = #where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or ''
  params[#params + 1] = lim

  return S.query([[
    SELECT id, actor_char_id, target_char_id, action, group_id, level, reason,
           UNIX_TIMESTAMP(created_at) AS created_unix
    FROM vh_groups_audit ]] .. where_sql .. [[
    ORDER BY id DESC
    LIMIT ?
  ]], params)
end

-- ── Schema application (idempotente, aplicado em onResourceStart) ────────────

function S.apply_schema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if type(schema) ~= 'string' or schema == '' then
    return false, 'schema_file_missing'
  end
  S.execute_raw(schema)
  S.ready = true
  return true
end
