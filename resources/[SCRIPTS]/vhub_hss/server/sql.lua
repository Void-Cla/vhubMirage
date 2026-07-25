-- server/sql.lua — fronteira SQL exclusiva do vHub HSS

VHubHSS_SQL = {}
local SQL = VHubHSS_SQL

local TIMEOUT_MS = 8000

local UPSERT = [[
    INSERT INTO `vhub_hss_state`
      (`char_id`, `food`, `water`, `energy`, `stress`, `blood`, `bleeding`, `pain`,
       `body_temp`, `consciousness`, `diseases`, `injuries`, `ped_state`,
       `customization_revision`, `revision`, `digest`)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, SHA2(?, 256))
    ON DUPLICATE KEY UPDATE
      `food` = IF(VALUES(`revision`) > `revision`, VALUES(`food`), `food`),
      `water` = IF(VALUES(`revision`) > `revision`, VALUES(`water`), `water`),
      `energy` = IF(VALUES(`revision`) > `revision`, VALUES(`energy`), `energy`),
      `stress` = IF(VALUES(`revision`) > `revision`, VALUES(`stress`), `stress`),
      `blood` = IF(VALUES(`revision`) > `revision`, VALUES(`blood`), `blood`),
      `bleeding` = IF(VALUES(`revision`) > `revision`, VALUES(`bleeding`), `bleeding`),
      `pain` = IF(VALUES(`revision`) > `revision`, VALUES(`pain`), `pain`),
      `body_temp` = IF(VALUES(`revision`) > `revision`, VALUES(`body_temp`), `body_temp`),
      `consciousness` = IF(VALUES(`revision`) > `revision`, VALUES(`consciousness`), `consciousness`),
      `diseases` = IF(VALUES(`revision`) > `revision`, VALUES(`diseases`), `diseases`),
      `injuries` = IF(VALUES(`revision`) > `revision`, VALUES(`injuries`), `injuries`),
      `ped_state` = IF(VALUES(`revision`) > `revision`, VALUES(`ped_state`), `ped_state`),
      `customization_revision` = GREATEST(
        `customization_revision`, VALUES(`customization_revision`)
      ),
      `digest` = IF(VALUES(`revision`) > `revision`, VALUES(`digest`), `digest`),
      `revision` = GREATEST(`revision`, VALUES(`revision`))
]]

local INSERT_IGNORE = [[
    INSERT IGNORE INTO `vhub_hss_state`
      (`char_id`, `food`, `water`, `energy`, `stress`, `blood`, `bleeding`, `pain`,
       `body_temp`, `consciousness`, `diseases`, `injuries`, `ped_state`,
       `customization_revision`, `revision`, `digest`)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, SHA2(?, 256))
]]


-- ============================================================
-- EXECUTOR
-- ============================================================

local function run_await(operation, cb, timeout_ms)
    local completed = false

    if timeout_ms then
        SetTimeout(timeout_ms, function()
            if completed then return end
            completed = true
            cb(false, 'sql_timeout')
        end)
    end

    Citizen.CreateThread(function()
        local ok, result = pcall(operation)
        if completed then return end
        completed = true
        cb(ok, ok and result or tostring(result))
    end)
end

local function params(char_id, bundle)
    local st = bundle.state
    return {
        char_id,
        st.food, st.water, st.energy, st.stress,
        st.blood, st.bleeding, st.pain, st.body_temp, st.consciousness,
        json.encode(st.diseases or {}),
        json.encode(st.injuries or {}),
        json.encode(bundle.profile or {}),
        bundle.customization_revision,
        bundle.revision,
        bundle.snapshot_json,
    }
end

local function save_await(char_id, bundle)
    MySQL.update.await(UPSERT, params(char_id, bundle))
    local row = MySQL.single.await(
        [[SELECT `revision`, `digest` = SHA2(?, 256) AS `digest_ok`
            FROM `vhub_hss_state` WHERE `char_id` = ?]],
        { bundle.snapshot_json, char_id }
    )
    if not row
        or tonumber(row.revision) ~= tonumber(bundle.revision)
        or tonumber(row.digest_ok) ~= 1 then
        error('revision_conflict')
    end
    return true
end

local function verify_columns()
    local rows = MySQL.query.await([[
        SELECT `COLUMN_NAME`
          FROM `information_schema`.`COLUMNS`
         WHERE `TABLE_SCHEMA` = DATABASE()
           AND `TABLE_NAME` = 'vhub_hss_state'
           AND `COLUMN_NAME` IN ('ped_state', 'customization_revision', 'revision', 'digest')
    ]], {}) or {}
    local found = {}
    for _, row in ipairs(rows) do found[row.COLUMN_NAME or row.column_name] = true end
    return found
end


-- ============================================================
-- SCHEMA / LOAD / SAVE
-- ============================================================

-- Aplica schema e migração v2 antes de liberar persistência.
function SQL.apply_schema(cb)
    local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
    if type(schema) ~= 'string' or schema == '' then
        cb(false, 'schema_missing')
        return
    end

    run_await(function()
        for statement in schema:gmatch('([^;]+);') do
            if statement:match('%S') then MySQL.query.await(statement, {}) end
        end

        local found = verify_columns()
        if not found.ped_state then
            MySQL.query.await('ALTER TABLE `vhub_hss_state` ADD COLUMN `ped_state` JSON NULL', {})
        end
        if not found.revision then
            MySQL.query.await(
                'ALTER TABLE `vhub_hss_state` ADD COLUMN `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0',
                {}
            )
        end
        if not found.customization_revision then
            MySQL.query.await(
                [[ALTER TABLE `vhub_hss_state`
                    ADD COLUMN `customization_revision` BIGINT UNSIGNED NOT NULL DEFAULT 0
                    AFTER `ped_state`]],
                {}
            )
        end
        if not found.digest then
            MySQL.query.await('ALTER TABLE `vhub_hss_state` ADD COLUMN `digest` CHAR(64) NULL', {})
        end

        found = verify_columns()
        if not found.ped_state or not found.customization_revision or not found.revision
            or not found.digest then
            error('schema_v2_incomplete')
        end
        MySQL.update.await(
            'INSERT IGNORE INTO `vhub_hss_schema_migrations` (`version`) VALUES (4)',
            {}
        )
        MySQL.update.await(
            'INSERT IGNORE INTO `vhub_hss_schema_migrations` (`version`) VALUES (2)',
            {}
        )
        local customization_ops_migrated = MySQL.scalar.await(
            'SELECT 1 FROM `vhub_hss_schema_migrations` WHERE `version` = 5 LIMIT 1',
            {}
        )
        if not customization_ops_migrated then
            MySQL.query.await([[
                ALTER TABLE `vhub_hss_customization_ops`
                  MODIFY COLUMN `state`
                    ENUM('pending', 'committed', 'rolled_back') NOT NULL DEFAULT 'pending'
            ]], {})
            MySQL.update.await(
                'INSERT INTO `vhub_hss_schema_migrations` (`version`) VALUES (5)',
                {}
            )
        end
        local precision_migrated = MySQL.scalar.await(
            'SELECT 1 FROM `vhub_hss_schema_migrations` WHERE `version` = 3 LIMIT 1',
            {}
        )
        if not precision_migrated then
            MySQL.query.await([[
                ALTER TABLE `vhub_hss_state`
                  MODIFY `food` DOUBLE NOT NULL DEFAULT 1.0,
                  MODIFY `water` DOUBLE NOT NULL DEFAULT 1.0,
                  MODIFY `energy` DOUBLE NOT NULL DEFAULT 1.0,
                  MODIFY `stress` DOUBLE NOT NULL DEFAULT 0.0,
                  MODIFY `blood` DOUBLE NOT NULL DEFAULT 1.0,
                  MODIFY `pain` DOUBLE NOT NULL DEFAULT 0.0,
                  MODIFY `body_temp` DOUBLE NOT NULL DEFAULT 37.0
            ]], {})
            MySQL.update.await('UPDATE `vhub_hss_state` SET `digest` = NULL', {})
            MySQL.update.await(
                'INSERT INTO `vhub_hss_schema_migrations` (`version`) VALUES (3)',
                {}
            )
        end
        return true
    end, cb, TIMEOUT_MS)
end

-- Retorna a linha persistida do personagem ou nil.
function SQL.load(char_id, cb)
    run_await(function()
        return MySQL.single.await(
            'SELECT * FROM `vhub_hss_state` WHERE `char_id` = ?',
            { char_id }
        )
    end, cb, TIMEOUT_MS)
end

-- Confirma se o outbox corresponde exatamente ao digest canônico persistido.
function SQL.matches(char_id, snapshot_json, cb)
    run_await(function()
        local row = MySQL.single.await(
            [[SELECT `digest` = SHA2(?, 256) AS `digest_ok`
                FROM `vhub_hss_state` WHERE `char_id` = ?]],
            { snapshot_json, char_id }
        )
        return row ~= nil and tonumber(row.digest_ok) == 1
    end, cb, TIMEOUT_MS)
end

-- Cria o snapshot inicial sem sobrescrever uma linha concorrente.
function SQL.insert_if_absent(char_id, bundle, cb)
    run_await(function()
        MySQL.update.await(INSERT_IGNORE, params(char_id, bundle))
        return MySQL.single.await(
            'SELECT * FROM `vhub_hss_state` WHERE `char_id` = ?',
            { char_id }
        )
    end, cb, TIMEOUT_MS)
end

-- Persiste somente revisão crescente e confirma revisão/digest antes do ACK.
function SQL.save(char_id, bundle, cb)
    run_await(function() return save_await(char_id, bundle) end, cb, TIMEOUT_MS)
end

-- Persiste e confirma sincronicamente apenas no flush terminal do resource.
function SQL.save_sync(char_id, bundle)
    local ok, result = pcall(save_await, char_id, bundle)
    return ok and result == true, ok and nil or tostring(result)
end


-- ============================================================
-- CUSTOMIZAÇÃO APV2
-- ============================================================

local function operation_row(operation_id, payload_json)
    return MySQL.single.await([[
        SELECT o.*,
               o.`digest` = SHA2(?, 256) AS `digest_ok`,
               s.`customization_revision` AS `stored_revision`,
               s.`revision` AS `stored_version`
          FROM `vhub_hss_customization_ops` o
          LEFT JOIN `vhub_hss_state` s ON s.`char_id` = o.`char_id`
         WHERE o.`operation_id` = ?
         LIMIT 1
    ]], { payload_json, operation_id })
end

local function customization_update_values(bundle)
    local st = bundle.state
    return {
        st.food,
        st.water,
        st.energy,
        st.stress,
        st.blood,
        st.bleeding,
        st.pain,
        st.body_temp,
        st.consciousness,
        json.encode(st.diseases or {}),
        json.encode(st.injuries or {}),
        json.encode(bundle.profile or {}),
        bundle.customization_revision,
        bundle.revision,
        bundle.snapshot_json,
    }
end

-- Consulta operação persistida e valida o digest do payload canônico.
function SQL.get_customization_operation(operation_id, payload_json, cb)
    run_await(function() return operation_row(operation_id, payload_json) end, cb, TIMEOUT_MS)
end

-- Consulta operação pelo token opaco de rollback.
function SQL.get_customization_rollback(rollback_token, cb)
    run_await(function()
        return MySQL.single.await([[
            SELECT o.*, s.`customization_revision` AS `stored_revision`,
                   s.`revision` AS `stored_version`
              FROM `vhub_hss_customization_ops` o
              LEFT JOIN `vhub_hss_state` s ON s.`char_id` = o.`char_id`
             WHERE o.`rollback_token` = ? LIMIT 1
        ]], { rollback_token })
    end, cb, TIMEOUT_MS)
end

-- Persiste operação e CAS de aparência na mesma transação.
function SQL.commit_customization(prepared, operation_id, payload_json, rollback_token, cb)
    run_await(function()
        local bundle = prepared.bundle
        local update_values = {
            operation_id,
            payload_json,
            prepared.before_revision,
            prepared.after_revision,
        }
        for _, value in ipairs(customization_update_values(bundle)) do
            update_values[#update_values + 1] = value
        end
        update_values[#update_values + 1] = prepared.char_id
        update_values[#update_values + 1] = prepared.before_revision
        local committed = MySQL.transaction.await({
            {
                query = [[
                    INSERT IGNORE INTO `vhub_hss_customization_ops`
                      (`operation_id`, `char_id`, `digest`, `before_customization`,
                       `after_customization`, `before_revision`, `after_revision`,
                       `rollback_token`, `state`)
                    SELECT ?, ?, SHA2(?, 256), ?, ?, ?, ?, ?, 'pending'
                      FROM `vhub_hss_state`
                     WHERE `char_id` = ? AND `customization_revision` = ?
                ]],
                values = {
                    operation_id,
                    prepared.char_id,
                    payload_json,
                    json.encode(prepared.before),
                    json.encode(prepared.after),
                    prepared.before_revision,
                    prepared.after_revision,
                    rollback_token,
                    prepared.char_id,
                    prepared.before_revision,
                },
            },
            {
                query = [[
                    UPDATE `vhub_hss_state` s
                    JOIN `vhub_hss_customization_ops` o
                      ON o.`operation_id` = ?
                     AND o.`char_id` = s.`char_id`
                     AND o.`digest` = SHA2(?, 256)
                     AND o.`before_revision` = ?
                     AND o.`after_revision` = ?
                     AND o.`state` = 'pending'
                       SET s.`food` = ?, s.`water` = ?, s.`energy` = ?, s.`stress` = ?,
                           s.`blood` = ?, s.`bleeding` = ?, s.`pain` = ?, s.`body_temp` = ?,
                           s.`consciousness` = ?, s.`diseases` = ?, s.`injuries` = ?,
                           s.`ped_state` = ?, s.`customization_revision` = ?,
                           s.`revision` = ?, s.`digest` = SHA2(?, 256)
                     WHERE s.`char_id` = ? AND s.`customization_revision` = ?
                ]],
                values = update_values,
            },
            {
                query = [[
                    UPDATE `vhub_hss_customization_ops` o
                    JOIN `vhub_hss_state` s ON s.`char_id` = o.`char_id`
                       SET o.`state` = 'committed'
                     WHERE o.`operation_id` = ?
                       AND o.`char_id` = ?
                       AND o.`digest` = SHA2(?, 256)
                       AND o.`state` = 'pending'
                       AND s.`customization_revision` = o.`after_revision`
                       AND s.`digest` = SHA2(?, 256)
                ]],
                values = {
                    operation_id,
                    prepared.char_id,
                    payload_json,
                    bundle.snapshot_json,
                },
            },
        })
        if committed ~= true then error('transaction_failed') end
        return operation_row(operation_id, payload_json)
    end, cb, TIMEOUT_MS)
end

-- Executa rollback one-shot com CAS na revisão criada pela operação original.
function SQL.rollback_customization(prepared, rollback_token, cb)
    run_await(function()
        local values = customization_update_values(prepared.bundle)
        local update_values = { rollback_token }
        for _, value in ipairs(values) do update_values[#update_values + 1] = value end
        update_values[#update_values + 1] = prepared.after_revision
        update_values[#update_values + 1] = rollback_token
        update_values[#update_values + 1] = prepared.char_id
        update_values[#update_values + 1] = prepared.before_revision
        MySQL.update.await([[
            UPDATE `vhub_hss_state` s
            JOIN `vhub_hss_customization_ops` o
              ON o.`rollback_token` = ?
             AND o.`char_id` = s.`char_id`
             AND o.`state` = 'committed'
               SET s.`food` = ?, s.`water` = ?, s.`energy` = ?, s.`stress` = ?,
                   s.`blood` = ?, s.`bleeding` = ?, s.`pain` = ?, s.`body_temp` = ?,
                   s.`consciousness` = ?, s.`diseases` = ?, s.`injuries` = ?,
                   s.`ped_state` = ?, s.`customization_revision` = ?,
                   s.`revision` = ?, s.`digest` = SHA2(?, 256),
                   o.`state` = 'rolled_back', o.`rollback_revision` = ?
             WHERE o.`rollback_token` = ?
               AND s.`char_id` = ?
               AND s.`customization_revision` = ?
        ]], update_values)
        return MySQL.single.await([[
            SELECT o.*, s.`customization_revision` AS `stored_revision`,
                   s.`revision` AS `stored_version`
              FROM `vhub_hss_customization_ops` o
              LEFT JOIN `vhub_hss_state` s ON s.`char_id` = o.`char_id`
             WHERE o.`rollback_token` = ? LIMIT 1
        ]], { rollback_token })
    end, cb, TIMEOUT_MS)
end

-- Retorna aparência persistida somente para IDs derivados no CORE.
function SQL.load_customizations(char_ids, cb)
    run_await(function()
        local ids = {}
        for index = 1, math.min(#char_ids, 3) do ids[index] = tonumber(char_ids[index]) end
        if #ids == 0 then return {} end
        local placeholders = {}
        for index = 1, #ids do placeholders[index] = '?' end
        return MySQL.query.await(([[
            SELECT `char_id`, `ped_state`, `customization_revision`
              FROM `vhub_hss_state`
             WHERE `char_id` IN (%s)
        ]]):format(table.concat(placeholders, ',')), ids) or {}
    end, cb, TIMEOUT_MS)
end
