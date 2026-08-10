-- server/sql.lua - persistencia exclusiva do dominio de outdoors

VHubOutdoors = VHubOutdoors or {}

local CFG = VHubOutdoors.cfg
local M = {}
VHubOutdoors.SQL = M

local function ox()
  return exports.oxmysql
end

local function await_response(starter)
  local pending = promise.new()
  local finished = false
  local function resolve(value)
    if finished then return end
    finished = true
    pending:resolve(value)
  end
  Citizen.SetTimeout(CFG.limits.sql_timeout_ms, function()
    resolve({ ok = false, timeout = true })
  end)
  local started = pcall(starter, resolve)
  if not started then resolve({ ok = false }) end
  return Citizen.Await(pending)
end

local function await_query(statement, parameters)
  local response = await_response(function(resolve)
    ox():query(statement, parameters or {}, function(rows)
      resolve({ ok = type(rows) == 'table', value = rows })
    end)
  end)
  if not response.ok then error('sql_query_failed') end
  return response.value
end

local function await_execute(statement, parameters)
  local response = await_response(function(resolve)
    ox():execute(statement, parameters or {}, function(affected)
      resolve({ ok = affected ~= nil, value = tonumber(affected) or 0 })
    end)
  end)
  if not response.ok then error('sql_execute_failed') end
  return response.value
end

local function await_scalar(statement, parameters)
  local response = await_response(function(resolve)
    ox():scalar(statement, parameters or {}, function(value)
      resolve({ ok = value ~= nil, value = value })
    end)
  end)
  if not response.ok then error('sql_scalar_failed') end
  return response.value
end

local function await_transaction(queries)
  local pending = promise.new()
  local started = pcall(function()
    ox():transaction(queries, function(ok)
      pending:resolve(ok == true)
    end)
  end)
  if not started then return false end
  return Citizen.Await(pending)
end

local function state_json(alias, active_expression, deleted_by, delete_reason)
  return ([[
    JSON_OBJECT(
      'id', %s.id,
      'title', %s.title,
      'media_type', %s.media_type,
      'media_url', %s.media_url,
      'youtube_id', %s.youtube_id,
      'size', %s.size,
      'volume', %s.volume,
      'controller_char_id', %s.controller_char_id,
      'top_left', JSON_OBJECT('x', %s.top_left_x, 'y', %s.top_left_y, 'z', %s.top_left_z),
      'bottom_right', JSON_OBJECT(
        'x', %s.bottom_right_x, 'y', %s.bottom_right_y, 'z', %s.bottom_right_z
      ),
      'active', %s,
      'deleted_by', %s,
      'delete_reason', %s
    )
  ]]):format(
    alias, alias, alias, alias, alias, alias, alias, alias,
    alias, alias, alias,
    alias, alias, alias,
    active_expression, deleted_by, delete_reason
  )
end

local ITEM_COLUMNS = [[
  `id`, `operation_id`, `title`, `media_type`, `media_url`, `youtube_id`, `size`,
  `volume`,
  `controller_char_id`, `controller_key`,
  `top_left_x`, `top_left_y`, `top_left_z`,
  `bottom_right_x`, `bottom_right_y`, `bottom_right_z`,
  `created_by`, `created_by_name`, `active`,
  `deleted_by`, `delete_reason`, `deleted_at`, `created_at`, `updated_at`
]]

-- Aplica o schema idempotente do resource.
function M.initSchema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if type(schema) ~= 'string' or schema == '' then return false end
  for statement in schema:gmatch('([^;]+);') do
    if statement:match('%S') then await_execute(statement, {}) end
  end

  local size_column = tonumber(await_scalar([[
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_items'
      AND column_name = 'size'
  ]], {}))
  if size_column == 0 then
    await_execute([[
      ALTER TABLE `vhub_outdoors_items`
      ADD COLUMN `size` ENUM('small', 'medium', 'large') NULL AFTER `youtube_id`
    ]], {})
  end

  local size_metadata = await_query([[
    SELECT `DATA_TYPE` AS `data_type`, `COLUMN_TYPE` AS `column_type`,
      `IS_NULLABLE` AS `is_nullable`
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_items'
      AND column_name = 'size'
    LIMIT 1
  ]], {})[1]
  if not size_metadata
      or tostring(size_metadata.data_type):lower() ~= 'enum'
      or tostring(size_metadata.column_type):lower()
        ~= "enum('small','medium','large')"
      or tostring(size_metadata.is_nullable):upper() ~= 'YES' then
    return false
  end

  local volume_column = tonumber(await_scalar([[
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_items'
      AND column_name = 'volume'
  ]], {}))
  if volume_column == 0 then
    await_execute([[
      ALTER TABLE `vhub_outdoors_items`
      ADD COLUMN `volume` DECIMAL(4,3) NOT NULL DEFAULT 0.450 AFTER `size`
    ]], {})
  end
  local volume_metadata = await_query([[
    SELECT `DATA_TYPE` AS `data_type`, `COLUMN_TYPE` AS `column_type`,
      `IS_NULLABLE` AS `is_nullable`, `COLUMN_DEFAULT` AS `column_default`
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_items'
      AND column_name = 'volume'
    LIMIT 1
  ]], {})[1]
  if not volume_metadata
      or tostring(volume_metadata.data_type):lower() ~= 'decimal'
      or tostring(volume_metadata.column_type):lower() ~= 'decimal(4,3)'
      or tostring(volume_metadata.is_nullable):upper() ~= 'NO'
      or math.abs((tonumber(volume_metadata.column_default) or -1) - 0.45) > 0.0001 then
    return false
  end

  local controller_char_column = tonumber(await_scalar([[
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_items'
      AND column_name = 'controller_char_id'
  ]], {}))
  if controller_char_column == 0 then
    await_execute([[
      ALTER TABLE `vhub_outdoors_items`
      ADD COLUMN `controller_char_id` INT UNSIGNED NULL AFTER `volume`,
      ADD KEY `idx_vhub_outdoors_controller` (`controller_char_id`)
    ]], {})
  end

  local controller_key_column = tonumber(await_scalar([[
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_items'
      AND column_name = 'controller_key'
  ]], {}))
  if controller_key_column == 0 then
    await_execute([[
      ALTER TABLE `vhub_outdoors_items`
      ADD COLUMN `controller_key` CHAR(32) NULL AFTER `controller_char_id`
    ]], {})
  end
  local controller_metadata = await_query([[
    SELECT `COLUMN_NAME` AS `column_name`, `DATA_TYPE` AS `data_type`,
      `COLUMN_TYPE` AS `column_type`,
      `IS_NULLABLE` AS `is_nullable`
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_items'
      AND column_name IN ('controller_char_id', 'controller_key')
  ]], {})
  local controller_columns = {}
  for _, column in ipairs(controller_metadata) do
    controller_columns[column.column_name] = column
  end
  local char_column = controller_columns.controller_char_id
  local key_column = controller_columns.controller_key
  if not char_column or tostring(char_column.data_type):lower() ~= 'int'
      or not tostring(char_column.column_type):lower():find('unsigned', 1, true)
      or tostring(char_column.is_nullable):upper() ~= 'YES'
      or not key_column or tostring(key_column.column_type):lower() ~= 'char(32)'
      or tostring(key_column.is_nullable):upper() ~= 'YES' then
    return false
  end

  local action_metadata = await_query([[
    SELECT `COLUMN_TYPE` AS `column_type`
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_audit'
      AND column_name = 'action'
    LIMIT 1
  ]], {})[1]
  if not action_metadata
      or tostring(action_metadata.column_type):lower()
        ~= "enum('create','update','delete')" then
    await_execute([[
      ALTER TABLE `vhub_outdoors_audit`
      MODIFY COLUMN `action` ENUM('create', 'update', 'delete') NOT NULL
    ]], {})
  end

  local columns = tonumber(await_scalar([[
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND (
      (
        table_name = 'vhub_outdoors_items'
        AND column_name IN (
          'id', 'operation_id', 'title', 'media_type', 'media_url', 'youtube_id', 'size',
          'volume',
          'controller_char_id', 'controller_key',
          'top_left_x', 'top_left_y', 'top_left_z',
          'bottom_right_x', 'bottom_right_y', 'bottom_right_z',
          'created_by', 'created_by_name', 'active', 'deleted_by', 'delete_reason',
          'deleted_at', 'created_at', 'updated_at'
        )
      ) OR (
        table_name = 'vhub_outdoors_audit'
        AND column_name IN (
          'id', 'operation_id', 'outdoor_id', 'action', 'actor_id',
          'actor_name', 'reason', 'before_state', 'after_state', 'created_at'
        )
      )
    )
  ]], {}))
  local active_grant_column = tonumber(await_scalar([[
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_remote_grants'
      AND column_name = 'active_outdoor_id'
  ]], {}))
  if active_grant_column == 0 then
    await_execute([[
      ALTER TABLE `vhub_outdoors_remote_grants`
      ADD COLUMN `active_outdoor_id` INT UNSIGNED GENERATED ALWAYS AS (
        CASE WHEN `status` = 'active' THEN `outdoor_id` ELSE NULL END
      ) STORED AFTER `status`
    ]], {})
  end
  local grant_status_type = await_query([[
    SELECT `COLUMN_TYPE` AS `column_type`
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_remote_grants'
      AND column_name = 'status'
    LIMIT 1
  ]], {})[1]
  if not grant_status_type
      or tostring(grant_status_type.column_type):lower()
        ~= "enum('pending','activating','active','revoked','cancelled')" then
    await_execute([[
      ALTER TABLE `vhub_outdoors_remote_grants`
      MODIFY COLUMN `status`
        ENUM('pending', 'activating', 'active', 'revoked', 'cancelled')
        NOT NULL DEFAULT 'pending'
    ]], {})
  end
  local grant_columns = tonumber(await_scalar([[
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_remote_grants'
      AND column_name IN (
        'operation_id', 'outdoor_id', 'char_id', 'access_key',
        'status', 'active_outdoor_id', 'created_by', 'created_at', 'updated_at'
      )
  ]], {}))
  local grant_metadata = await_query([[
    SELECT `COLUMN_NAME` AS `column_name`, `COLUMN_TYPE` AS `column_type`,
      `IS_NULLABLE` AS `is_nullable`, `EXTRA` AS `extra`
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_remote_grants'
      AND column_name IN ('access_key', 'status', 'active_outdoor_id')
  ]], {})
  local grant_fields = {}
  for _, column in ipairs(grant_metadata) do
    grant_fields[column.column_name] = column
  end
  local grant_key = grant_fields.access_key
  local grant_status = grant_fields.status
  local grant_active = grant_fields.active_outdoor_id
  return columns == 34
    and grant_columns == 9
    and grant_key ~= nil
    and tostring(grant_key.column_type):lower() == 'char(32)'
    and tostring(grant_key.is_nullable):upper() == 'NO'
    and grant_status ~= nil
    and tostring(grant_status.column_type):lower()
      == "enum('pending','activating','active','revoked','cancelled')"
    and tostring(grant_status.is_nullable):upper() == 'NO'
    and grant_active ~= nil
    and tostring(grant_active.column_type):lower():find('unsigned', 1, true) ~= nil
    and tostring(grant_active.is_nullable):upper() == 'YES'
    and tostring(grant_active.extra):lower():find('stored generated', 1, true) ~= nil
end

-- Cria a unicidade de grant ativo depois da reconciliacao de dados legados.
function M.ensureRemoteGrantUniqueness()
  local index_count = tonumber(await_scalar([[
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'vhub_outdoors_remote_grants'
      AND index_name = 'uq_vhub_outdoors_remote_active'
      AND non_unique = 0
  ]], {}))
  if index_count == 0 then
    await_execute([[
      ALTER TABLE `vhub_outdoors_remote_grants`
      ADD UNIQUE KEY `uq_vhub_outdoors_remote_active` (`active_outdoor_id`)
    ]], {})
  end
  return true
end

-- Retorna os outdoors ativos limitados pelo contrato de performance.
function M.listActive(limit)
  return await_query(([[
    SELECT %s FROM `vhub_outdoors_items`
    WHERE `active` = 1 ORDER BY `id` ASC LIMIT ?
  ]]):format(ITEM_COLUMNS), { limit + 1 })
end

-- Retorna um outdoor pela operacao idempotente de criacao.
function M.findByOperation(operation_id)
  local rows = await_query([[
    SELECT i.*, a.id AS `audit_id`
    FROM `vhub_outdoors_items` i
    INNER JOIN `vhub_outdoors_audit` a
      ON a.operation_id = i.operation_id AND a.action = 'create'
    WHERE i.operation_id = ? LIMIT 1
  ]], { operation_id })
  return rows[1]
end

-- Retorna a revisao global derivada do log autoritativo.
function M.revision()
  return assert(tonumber(await_scalar(
    'SELECT COALESCE(MAX(`id`), 0) FROM `vhub_outdoors_audit`', {}
  )), 'invalid_revision')
end

local function remote_grant(operation_id)
  return await_query([[
    SELECT `operation_id`, `outdoor_id`, `char_id`, `access_key`, `status`, `created_by`
    FROM `vhub_outdoors_remote_grants`
    WHERE `operation_id` = ? LIMIT 1
  ]], { operation_id })[1]
end

-- Registra a intencao duravel antes de cruzar a fronteira do inventario.
function M.beginRemoteGrant(data)
  local existing = remote_grant(data.operation_id)
  if existing then
    local matches = tonumber(existing.outdoor_id) == data.outdoor_id
      and tonumber(existing.char_id) == data.char_id
      and existing.access_key == data.access_key
      and tonumber(existing.created_by) == data.created_by
    return matches and existing or nil, matches and true or 'conflict'
  end
  local committed = await_transaction({
    {
      query = [[
        INSERT INTO `vhub_outdoors_remote_grants` (
          `operation_id`, `outdoor_id`, `char_id`, `access_key`, `created_by`
        )
        SELECT ?, i.id, ?, ?, ?
        FROM `vhub_outdoors_items` i
        WHERE i.id = ? AND i.active = 1
      ]],
      values = {
        data.operation_id, data.char_id, data.access_key,
        data.created_by, data.outdoor_id,
      },
    },
  })
  if not committed then return nil, 'storage' end
  local created = remote_grant(data.operation_id)
  if not created then return nil, 'not_found' end
  return created, false
end

-- Busca journal de concessao pela capacidade apresentada pelo item.
function M.findRemoteGrant(outdoor_id, char_id, access_key)
  return await_query([[
    SELECT `operation_id`, `outdoor_id`, `char_id`, `access_key`, `status`, `created_by`
    FROM `vhub_outdoors_remote_grants`
    WHERE `outdoor_id` = ? AND `char_id` = ? AND `access_key` = ?
    LIMIT 1
  ]], { outdoor_id, char_id, access_key })[1]
end

-- Lista concessoes que podem exigir entrega ou reconciliacao do item.
function M.listRecoverableRemoteGrants(char_id)
  return await_query([[
    SELECT g.`operation_id`, g.`outdoor_id`, g.`char_id`, g.`access_key`,
      g.`status`, g.`created_by`
    FROM `vhub_outdoors_remote_grants` g
    INNER JOIN `vhub_outdoors_items` i
      ON i.id = g.outdoor_id AND i.active = 1
    WHERE g.char_id = ? AND g.status IN ('pending', 'active')
    ORDER BY g.created_at ASC
    LIMIT 32
  ]], { char_id })
end

-- Cancela uma concessao que ainda nao alcancou o commit canonico.
function M.setRemoteGrantStatus(operation_id, status)
  if status ~= 'cancelled' then return false end
  local existing = remote_grant(operation_id)
  if not existing then return false end
  if existing.status == status then return true end
  if existing.status ~= 'pending' then return false end
  if not await_transaction({
    {
      query = [[
        UPDATE `vhub_outdoors_remote_grants`
        SET `status` = 'cancelled'
        WHERE `operation_id` = ? AND `status` = 'pending'
      ]],
      values = { operation_id },
    },
  }) then return false end
  local current = remote_grant(operation_id)
  return current ~= nil and current.status == status
end

-- Normaliza journals legados contra o controlador canonico.
function M.reconcileRemoteGrants()
  return await_transaction({
    {
      query = [[
        UPDATE `vhub_outdoors_remote_grants` g
        INNER JOIN `vhub_outdoors_items` i ON i.id = g.outdoor_id
        SET g.status = 'revoked'
        WHERE g.status IN ('active', 'activating')
          AND (
            i.active <> 1
            OR i.controller_char_id <> g.char_id
            OR i.controller_key <> g.access_key
            OR i.controller_char_id IS NULL
            OR i.controller_key IS NULL
          )
      ]],
      values = {},
    },
    {
      query = [[
        UPDATE `vhub_outdoors_remote_grants` g
        INNER JOIN `vhub_outdoors_items` i
          ON i.id = g.outdoor_id
          AND i.active = 1
          AND i.controller_char_id = g.char_id
          AND i.controller_key = g.access_key
        SET g.status = 'active'
        WHERE g.status IN ('pending', 'activating')
      ]],
      values = {},
    },
  })
end

-- Ativa journal, controlador canonico e auditoria na mesma transacao.
function M.activateRemoteGrant(outdoor_id, char_id, access_key, operation_id, precommit)
  local replay = M.findAudit(operation_id)
  if replay then
    if tonumber(replay.outdoor_id) ~= outdoor_id
        or replay.action ~= 'update'
        or replay.reason ~= 'Ativacao de controle remoto' then
      return nil, 'conflict'
    end
    local rows = await_query([[
      SELECT i.*, a.id AS `audit_id`
      FROM `vhub_outdoors_items` i
      INNER JOIN `vhub_outdoors_audit` a
        ON a.operation_id = ? AND a.outdoor_id = i.id AND a.action = 'update'
      INNER JOIN `vhub_outdoors_remote_grants` g
        ON g.operation_id = ? AND g.outdoor_id = i.id AND g.status = 'active'
      WHERE i.id = ? AND i.active = 1
        AND i.controller_char_id = ? AND i.controller_key = ?
        AND g.char_id = ? AND g.access_key = ?
      LIMIT 1
    ]], {
      operation_id, operation_id, outdoor_id,
      char_id, access_key, char_id, access_key,
    })
    if precommit then
      local allowed, error_code = precommit()
      if not allowed then return nil, error_code or 'forbidden' end
    end
    return rows[1], rows[1] and true or 'conflict'
  end

  if precommit then
    local allowed, error_code = precommit()
    if not allowed then return nil, error_code or 'forbidden' end
  end
  local after_expression = state_json('i', 'i.active', 'i.deleted_by', 'i.delete_reason')
  local queries = {
    {
      query = [[
        UPDATE `vhub_outdoors_items` i
        INNER JOIN `vhub_outdoors_remote_grants` current_grant
          ON current_grant.operation_id = ?
          AND current_grant.outdoor_id = i.id
          AND current_grant.char_id = ?
          AND current_grant.access_key = ?
          AND current_grant.status = 'pending'
        SET i.controller_char_id = current_grant.char_id,
            i.controller_key = current_grant.access_key,
            current_grant.status = 'activating'
        WHERE i.id = ? AND i.active = 1
      ]],
      values = { operation_id, char_id, access_key, outdoor_id },
    },
    {
      query = [[
        UPDATE `vhub_outdoors_remote_grants` old_grant
        INNER JOIN `vhub_outdoors_remote_grants` current_grant
          ON current_grant.operation_id = ?
          AND current_grant.outdoor_id = old_grant.outdoor_id
          AND current_grant.status = 'activating'
        INNER JOIN `vhub_outdoors_items` i
          ON i.id = current_grant.outdoor_id
          AND i.active = 1
          AND i.controller_char_id = current_grant.char_id
          AND i.controller_key = current_grant.access_key
        SET old_grant.status = 'revoked'
        WHERE old_grant.operation_id <> current_grant.operation_id
          AND old_grant.status IN ('active', 'pending', 'activating')
      ]],
      values = { operation_id },
    },
    {
      query = [[
        UPDATE `vhub_outdoors_remote_grants` current_grant
        INNER JOIN `vhub_outdoors_items` i
          ON i.id = current_grant.outdoor_id
          AND i.active = 1
          AND i.controller_char_id = current_grant.char_id
          AND i.controller_key = current_grant.access_key
        SET current_grant.status = 'active'
        WHERE current_grant.operation_id = ?
          AND current_grant.status = 'activating'
      ]],
      values = { operation_id },
    },
    {
      query = ([[
        INSERT INTO `vhub_outdoors_audit` (
          `operation_id`, `outdoor_id`, `action`, `actor_id`, `actor_name`,
          `reason`, `before_state`, `after_state`
        )
        SELECT ?, i.id, 'update', g.created_by, 'Sistema de controle',
          'Ativacao de controle remoto', NULL, %s
        FROM `vhub_outdoors_items` i
        INNER JOIN `vhub_outdoors_remote_grants` g
          ON g.operation_id = ?
          AND g.outdoor_id = i.id
          AND g.status = 'active'
          AND g.char_id = ?
          AND g.access_key = ?
        WHERE i.id = ? AND i.active = 1
          AND i.controller_char_id = ? AND i.controller_key = ?
      ]]):format(after_expression),
      values = {
        operation_id, operation_id, char_id, access_key,
        outdoor_id, char_id, access_key,
      },
    },
  }
  local committed = await_transaction(queries)
  if not committed then return nil, 'storage' end

  local rows = await_query([[
    SELECT i.*, a.id AS `audit_id`
    FROM `vhub_outdoors_items` i
    INNER JOIN `vhub_outdoors_audit` a
      ON a.operation_id = ? AND a.outdoor_id = i.id AND a.action = 'update'
    INNER JOIN `vhub_outdoors_remote_grants` g
      ON g.operation_id = ? AND g.outdoor_id = i.id AND g.status = 'active'
    WHERE i.id = ? AND i.active = 1
      AND i.controller_char_id = ? AND i.controller_key = ?
      AND g.char_id = ? AND g.access_key = ?
    LIMIT 1
  ]], {
    operation_id, operation_id, outdoor_id,
    char_id, access_key, char_id, access_key,
  })
  return rows[1], rows[1] and false or 'conflict'
end

-- Cria outdoor e auditoria na mesma transacao.
function M.create(data, allow_insert, known_absent)
  if not known_absent then
    local existing = M.findByOperation(data.operation_id)
    if existing then return existing, true end
  end
  if not allow_insert then return nil, 'limit' end

  local after_json = state_json('i', '1', 'NULL', 'NULL')
  local queries = {
    {
      query = [[
        INSERT INTO `vhub_outdoors_items` (
          `operation_id`, `title`, `media_type`, `media_url`, `youtube_id`, `size`,
          `volume`,
          `top_left_x`, `top_left_y`, `top_left_z`,
          `bottom_right_x`, `bottom_right_y`, `bottom_right_z`,
          `created_by`, `created_by_name`
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ]],
      values = {
        data.operation_id, data.title, data.media_type, data.media_url,
        data.youtube_id, data.size, data.volume,
        data.top_left.x, data.top_left.y, data.top_left.z,
        data.bottom_right.x, data.bottom_right.y, data.bottom_right.z,
        data.actor_id, data.actor_name,
      },
    },
    {
      query = ([[
        INSERT INTO `vhub_outdoors_audit` (
          `operation_id`, `outdoor_id`, `action`, `actor_id`, `actor_name`,
          `reason`, `before_state`, `after_state`
        )
        SELECT ?, i.id, 'create', ?, ?, ?, NULL, %s
        FROM `vhub_outdoors_items` i WHERE i.operation_id = ?
      ]]):format(after_json),
      values = {
        data.operation_id, data.actor_id, data.actor_name,
        data.reason, data.operation_id,
      },
    },
  }
  if type(data.remote_grant) == 'table' then
    queries[#queries + 1] = {
      query = [[
        INSERT INTO `vhub_outdoors_remote_grants` (
          `operation_id`, `outdoor_id`, `char_id`, `access_key`, `created_by`
        )
        SELECT ?, i.id, ?, ?, ?
        FROM `vhub_outdoors_items` i
        WHERE i.operation_id = ?
      ]],
      values = {
        data.remote_grant.operation_id,
        data.remote_grant.char_id,
        data.remote_grant.access_key,
        data.remote_grant.created_by,
        data.operation_id,
      },
    }
  end
  local committed = await_transaction(queries)
  if not committed then return nil, 'storage' end
  local created = M.findByOperation(data.operation_id)
  if not created then return nil, 'storage' end
  return created, false
end

local function updated_row_matches(row, data)
  local function near(left, right)
    return math.abs((tonumber(left) or 0) - (tonumber(right) or 0)) <= 0.0001
  end
  return type(row) == 'table'
    and tonumber(row.id) == data.id
    and row.title == data.title
    and row.media_type == data.media_type
    and row.media_url == data.media_url
    and (row.youtube_id or nil) == (data.youtube_id or nil)
    and (row.size or nil) == (data.size or nil)
    and near(row.volume, data.volume)
    and (tonumber(row.controller_char_id) or nil) == data.controller_char_id
    and (row.controller_key or nil) == data.controller_key
    and near(row.top_left_x, data.top_left.x)
    and near(row.top_left_y, data.top_left.y)
    and near(row.top_left_z, data.top_left.z)
    and near(row.bottom_right_x, data.bottom_right.x)
    and near(row.bottom_right_y, data.bottom_right.y)
    and near(row.bottom_right_z, data.bottom_right.z)
end

-- Atualiza estado mutavel e auditoria na mesma transacao.
function M.update(data, actor, operation_id, reason, precommit)
  local replay = M.findAudit(operation_id)
  if replay then
    local matches = tonumber(replay.outdoor_id) == data.id
      and replay.action == 'update'
      and tonumber(replay.actor_id) == actor.id
      and replay.reason == reason
    if not matches then return nil, 'conflict' end
    local rows = await_query((([[
      SELECT %s FROM `vhub_outdoors_items`
      WHERE `id` = ? AND `active` = 1 LIMIT 1
    ]]):format(ITEM_COLUMNS)), { data.id })
    if not rows[1] then return nil, 'not_found' end
    rows[1].audit_id = replay.id
    if not updated_row_matches(rows[1], data) then return nil, 'conflict' end
    return rows[1], true
  end

  local before_expression = state_json('i', 'i.active', 'i.deleted_by', 'i.delete_reason')
  local current = await_query((([[
    SELECT %s, %s AS `before_state`
    FROM `vhub_outdoors_items` i
    WHERE i.id = ? AND i.active = 1 LIMIT 1
  ]]):format(ITEM_COLUMNS, before_expression)), { data.id })[1]
  if not current then return nil, 'not_found' end

  local before_state = type(current.before_state) == 'table'
    and json.encode(current.before_state)
    or current.before_state
  if type(before_state) ~= 'string' or before_state == '' then
    return nil, 'storage'
  end
  local after_state = json.encode({
    id = data.id,
    title = data.title,
    media_type = data.media_type,
    media_url = data.media_url,
    youtube_id = data.youtube_id,
    size = data.size,
    volume = data.volume,
    controller_char_id = data.controller_char_id,
    top_left = data.top_left,
    bottom_right = data.bottom_right,
    active = 1,
  })
  if precommit then
    local allowed, error_code = precommit()
    if not allowed then return nil, error_code or 'forbidden' end
  end
  local committed = await_transaction({
    {
      query = ([[
        INSERT INTO `vhub_outdoors_audit` (
          `operation_id`, `outdoor_id`, `action`, `actor_id`, `actor_name`,
          `reason`, `before_state`, `after_state`
        )
        SELECT ?, i.id, 'update', ?, ?, ?, %s, ?
        FROM `vhub_outdoors_items` i
        WHERE i.id = ? AND i.active = 1
      ]]):format(before_expression),
      values = {
        operation_id, actor.id, actor.name, reason, after_state, data.id,
      },
    },
    {
      query = [[
        UPDATE `vhub_outdoors_items` i
        JOIN `vhub_outdoors_audit` a
          ON a.operation_id = ? AND a.outdoor_id = i.id AND a.action = 'update'
        SET i.media_type = ?,
            i.media_url = ?,
            i.youtube_id = ?,
            i.volume = ?,
            i.controller_char_id = ?,
            i.controller_key = ?,
            i.top_left_x = ?,
            i.top_left_y = ?,
            i.top_left_z = ?,
            i.bottom_right_x = ?,
            i.bottom_right_y = ?,
            i.bottom_right_z = ?
        WHERE i.id = ? AND i.active = 1
      ]],
      values = {
        operation_id,
        data.media_type, data.media_url, data.youtube_id, data.volume,
        data.controller_char_id, data.controller_key,
        data.top_left.x, data.top_left.y, data.top_left.z,
        data.bottom_right.x, data.bottom_right.y, data.bottom_right.z,
        data.id,
      },
    },
  })
  if not committed then return nil, 'storage' end
  local rows = await_query((([[
    SELECT i.*, a.id AS `audit_id`
    FROM `vhub_outdoors_items` i
    INNER JOIN `vhub_outdoors_audit` a
      ON a.operation_id = ? AND a.outdoor_id = i.id AND a.action = 'update'
    WHERE i.id = ? AND i.active = 1 LIMIT 1
  ]])), { operation_id, data.id })
  if not rows[1] then return nil, 'not_found' end
  if not updated_row_matches(rows[1], data) then return nil, 'conflict' end
  return rows[1], false
end

-- Busca uma auditoria pelo identificador idempotente.
function M.findAudit(operation_id)
  local rows = await_query([[
    SELECT `id`, `operation_id`, `outdoor_id`, `action`, `actor_id`, `reason`
    FROM `vhub_outdoors_audit` WHERE `operation_id` = ? LIMIT 1
  ]], { operation_id })
  return rows[1]
end

-- Desativa outdoor e registra before/after atomicamente.
function M.softDelete(id, actor, operation_id, reason, precommit)
  local replay = M.findAudit(operation_id)
  if replay then
    local matches = tonumber(replay.outdoor_id) == id
      and replay.action == 'delete'
      and tonumber(replay.actor_id) == actor.id
      and replay.reason == reason
    return matches, matches and true or 'conflict',
      matches and tonumber(replay.id) or nil
  end

  local active = await_query([[
    SELECT `id` FROM `vhub_outdoors_items`
    WHERE `id` = ? AND `active` = 1 LIMIT 1
  ]], { id })
  if not active[1] then return false, 'not_found' end

  if precommit then
    local allowed, error_code = precommit()
    if not allowed then return false, error_code or 'forbidden' end
  end
  local before_json = state_json('i', 'i.active', 'i.deleted_by', 'i.delete_reason')
  local after_json = state_json('i', '0', '?', '?')
  local committed = await_transaction({
    {
      query = ([[
        INSERT INTO `vhub_outdoors_audit` (
          `operation_id`, `outdoor_id`, `action`, `actor_id`, `actor_name`,
          `reason`, `before_state`, `after_state`
        )
        SELECT ?, i.id, 'delete', ?, ?, ?, %s, %s
        FROM `vhub_outdoors_items` i
        WHERE i.id = ? AND i.active = 1
      ]]):format(before_json, after_json),
      values = {
        operation_id, actor.id, actor.name, reason,
        actor.id, reason, id,
      },
    },
    {
      query = [[
        UPDATE `vhub_outdoors_items` i
        JOIN `vhub_outdoors_audit` a
          ON a.operation_id = ? AND a.outdoor_id = i.id AND a.action = 'delete'
        SET i.active = 0,
            i.deleted_by = ?,
            i.delete_reason = ?,
            i.deleted_at = NOW()
        WHERE i.id = ? AND i.active = 1
      ]],
      values = { operation_id, actor.id, reason, id },
    },
  })
  if not committed then return false, 'storage' end
  local audit = M.findAudit(operation_id)
  if not audit or audit.action ~= 'delete'
      or tonumber(audit.outdoor_id) ~= id then
    return false, 'not_found'
  end
  return true, false, tonumber(audit.id)
end
