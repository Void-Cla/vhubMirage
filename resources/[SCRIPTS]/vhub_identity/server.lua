-- server.lua — identidade autoritativa e operações idempotentes por personagem

local _ready = false


-- ============================================================
-- SQL / LOG
-- ============================================================

local function log(level, message, meta)
    pcall(function() exports.vhub:log(level, 'identity', message, meta) end)
end

local function apply_schema()
    local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
    if type(schema) ~= 'string' or schema == '' then return false end
    local ok = pcall(function()
        for statement in schema:gmatch('([^;]+);') do
            if statement:match('%S') then MySQL.query.await(statement, {}) end
        end
    end)
    return ok
end

local function get_identity(char_id)
    return MySQL.single.await([[
        SELECT `firstname`, `lastname`, `age`, `registration`, `phone`
          FROM `vh_identity` WHERE `char_id` = ? LIMIT 1
    ]], { char_id })
end

local function copy_identity(identity)
    if type(identity) ~= 'table' then return nil end
    return {
        firstname = identity.firstname,
        lastname = identity.lastname,
        age = tonumber(identity.age),
        registration = identity.registration,
        phone = identity.phone,
    }
end


-- ============================================================
-- NORMALIZAÇÃO / GERAÇÃO
-- ============================================================

local function stable_encode(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then return ('%.17g'):format(value) end
    if kind == 'string' then return json.encode(value) end
    if kind ~= 'table' then return 'null' end
    local keys = {}
    for key in pairs(value) do
        if type(key) == 'string' then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local items = {}
    for index, key in ipairs(keys) do
        items[index] = json.encode(key) .. ':' .. stable_encode(value[key])
    end
    return '{' .. table.concat(items, ',') .. '}'
end

local function sanitize_name(value)
    if type(value) ~= 'string' then return nil end
    local trimmed = value:match('^%s*(.-)%s*$')
    if #trimmed < 2 or #trimmed > 50 or trimmed:find('[^%a%sÀ-ÿ%-]') then return nil end
    return trimmed
end

local function sanitize_identity(data)
    if type(data) ~= 'table' then return nil end
    for key in pairs(data) do
        if key ~= 'firstname' and key ~= 'lastname' and key ~= 'age' then return nil end
    end
    local firstname = sanitize_name(data.firstname)
    local lastname = sanitize_name(data.lastname)
    local age = tonumber(data.age)
    if not firstname or not lastname or not age or age % 1 ~= 0 or age < 16 or age > 120 then
        return nil
    end
    return { firstname = firstname, lastname = lastname, age = math.floor(age) }
end

local function valid_operation_id(value)
    return type(value) == 'string'
        and #value >= 8
        and #value <= 96
        and value:match('^[a-zA-Z0-9:_%-]+$') ~= nil
end

local function decode_identity(value)
    if type(value) == 'table' then return copy_identity(value) end
    local ok, decoded = pcall(json.decode, value or '{}')
    return ok and copy_identity(decoded) or nil
end

local function resolve_online(src)
    src = tonumber(src)
    if not src or src < 1 or not GetPlayerName(src) then return nil end
    local ok, char_id = pcall(function() return exports.vhub:getCharacterId(src) end)
    if not ok or not tonumber(char_id) then return nil end
    return math.floor(tonumber(char_id))
end


-- ============================================================
-- LIFECYCLE / CARGA
-- ============================================================

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Citizen.CreateThread(function()
        for _ = 1, 50 do
            local ok = pcall(function() return exports.vhub:getCharacterId(0) end)
            if ok then break end
            Citizen.Wait(200)
        end
        if not apply_schema() then
            log('error', 'Schema de identidade indisponível.')
            return
        end
        _ready = true
        log('info', 'Identidade inicializada.')
    end)
end)

AddEventHandler('vHub:characterLoad', function(user)
    if not _ready or type(user) ~= 'table' then return end
    local src, char_id = tonumber(user.source), tonumber(user.char_id)
    if not src or not char_id then return end
    Citizen.CreateThread(function()
        local identity = get_identity(char_id)
        -- identidade ausente = personagem novo aguardando SIMS; não gerar dado falso
        if identity and GetPlayerName(src) then
            TriggerClientEvent('vhub_identity:load', src, copy_identity(identity))
        end
    end)
end)

AddEventHandler('vHub:playerSpawn', function(user)
    if not _ready or type(user) ~= 'table' then return end
    local src, char_id = tonumber(user.source), tonumber(user.char_id)
    if not src or not char_id then return end
    Citizen.CreateThread(function()
        local identity = get_identity(char_id)
        if identity and GetPlayerName(src) then
            TriggerClientEvent('vhub_identity:load', src, copy_identity(identity))
        end
    end)
end)


-- ============================================================
-- EVENTOS LEGADOS VALIDADOS
-- ============================================================

RegisterNetEvent('vhub_identity:get', function()
    local src = source
    local char_id = _ready and resolve_online(src) or nil
    if not char_id then return end
    Citizen.CreateThread(function()
        local identity = get_identity(char_id)
        if identity and GetPlayerName(src) then
            TriggerClientEvent('vhub_identity:load', src, copy_identity(identity))
        end
    end)
end)


-- ============================================================
-- EXPORTS ADR #74
-- ============================================================

-- Persiste nome/idade idempotentes; registro e telefone são preservados no SQL.
exports('setIdentity', function(src, data, operation_id)
    if GetInvokingResource() ~= 'vhub_sims' then return { ok = false, err = 'forbidden' } end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return { ok = false, err = 'offline' } end
    local clean = sanitize_identity(data)
    if not clean or not valid_operation_id(operation_id) then
        return { ok = false, err = 'invalid_identity' }
    end
    if not _ready then return { ok = false, err = 'storage' } end
    local char_id = resolve_online(src)
    if not char_id then return { ok = false, err = 'offline' } end
    local payload_json = stable_encode(clean)
    local registration = ('VH%010d'):format(char_id)
    local phone = ('55%010d'):format(char_id)

    local read_ok, existing = pcall(function()
        return MySQL.single.await([[
            SELECT *, `digest` = SHA2(?, 256) AS `digest_ok`
              FROM `vh_identity_operations` WHERE `operation_id` = ? LIMIT 1
        ]], { payload_json, operation_id })
    end)
    if not read_ok then return { ok = false, err = 'storage' } end
    if existing then
        if tonumber(existing.char_id) ~= char_id or tonumber(existing.digest_ok) ~= 1 then
            return { ok = false, err = 'conflict' }
        end
        local replay_identity = decode_identity(existing.result_identity)
        if existing.state ~= 'committed' or not replay_identity then
            return { ok = false, err = 'storage' }
        end
        local current_ok, current_identity = pcall(get_identity, char_id)
        current_identity = current_ok and copy_identity(current_identity) or nil
        if current_identity
            and current_identity.firstname == replay_identity.firstname
            and current_identity.lastname == replay_identity.lastname
            and current_identity.age == replay_identity.age
            and current_identity.registration == replay_identity.registration
            and current_identity.phone == replay_identity.phone then
            TriggerClientEvent('vhub_identity:load', src, current_identity)
        end
        return { ok = true, identity = replay_identity, replayed = true }
    end

    local ok, transaction_result = pcall(function()
        return MySQL.transaction.await({
            {
                query = [[
                    INSERT IGNORE INTO `vh_identity`
                      (`char_id`, `firstname`, `lastname`, `age`, `registration`, `phone`)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]],
                values = {
                    char_id,
                    clean.firstname,
                    clean.lastname,
                    clean.age,
                    registration,
                    phone,
                },
            },
            {
                query = [[
                    INSERT IGNORE INTO `vh_identity_operations`
                      (`operation_id`, `char_id`, `digest`, `state`)
                    SELECT ?, ?, SHA2(?, 256), 'pending'
                      FROM `vh_identity` WHERE `char_id` = ?
                ]],
                values = { operation_id, char_id, payload_json, char_id },
            },
            {
                query = [[
                    UPDATE `vh_identity` i
                    JOIN `vh_identity_operations` o
                      ON o.`operation_id` = ?
                     AND o.`char_id` = i.`char_id`
                     AND o.`digest` = SHA2(?, 256)
                     AND o.`state` = 'pending'
                       SET i.`firstname` = ?, i.`lastname` = ?, i.`age` = ?
                     WHERE i.`char_id` = ?
                ]],
                values = {
                    operation_id,
                    payload_json,
                    clean.firstname,
                    clean.lastname,
                    clean.age,
                    char_id,
                },
            },
            {
                query = [[
                    UPDATE `vh_identity_operations` o
                    JOIN `vh_identity` i ON i.`char_id` = o.`char_id`
                       SET o.`result_identity` = JSON_OBJECT(
                             'firstname', i.`firstname`, 'lastname', i.`lastname`, 'age', i.`age`,
                             'registration', i.`registration`, 'phone', i.`phone`
                           ),
                           o.`state` = 'committed'
                     WHERE o.`operation_id` = ?
                       AND o.`char_id` = ?
                       AND o.`digest` = SHA2(?, 256)
                       AND o.`state` = 'pending'
                ]],
                values = { operation_id, char_id, payload_json },
            },
        })
    end)
    if not ok or transaction_result ~= true then return { ok = false, err = 'storage' } end

    local operation_ok, operation = pcall(function()
        return MySQL.single.await([[
            SELECT *, `digest` = SHA2(?, 256) AS `digest_ok`
              FROM `vh_identity_operations` WHERE `operation_id` = ? LIMIT 1
        ]], { payload_json, operation_id })
    end)
    if not operation_ok or not operation then return { ok = false, err = 'storage' } end
    if tonumber(operation.char_id) ~= char_id or tonumber(operation.digest_ok) ~= 1 then
        return { ok = false, err = 'conflict' }
    end
    if operation.state ~= 'committed' then return { ok = false, err = 'storage' } end

    local identity_ok, identity = pcall(get_identity, char_id)
    local expected = decode_identity(operation.result_identity)
    if not identity_ok or not identity or not expected
        or identity.firstname ~= expected.firstname
        or identity.lastname ~= expected.lastname
        or tonumber(identity.age) ~= expected.age
        or identity.registration ~= expected.registration
        or identity.phone ~= expected.phone then
        return { ok = false, err = 'storage' }
    end
    identity = copy_identity(identity)
    TriggerClientEvent('vhub_identity:load', src, identity)
    return { ok = true, identity = copy_identity(identity), replayed = false }
end)

-- Retorna resumos públicos dos IDs canônicos derivados no CORE.
exports('getCharacterSummaries', function(src)
    if GetInvokingResource() ~= 'vhub_login' then return { ok = false, err = 'forbidden' } end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return { ok = false, err = 'offline' } end
    if not _ready then return { ok = false, err = 'storage' } end
    local called, response = pcall(function() return exports.vhub:getCharacterIds(src) end)
    if not called or type(response) ~= 'table' or response.ok ~= true or type(response.items) ~= 'table' then
        local error_code = type(response) == 'table' and response.err or nil
        return { ok = false, err = error_code == 'offline' and 'offline' or 'storage' }
    end

    local ids = {}
    for index = 1, math.min(#response.items, 3) do
        local char_id = tonumber(response.items[index])
        if char_id and char_id > 0 then ids[#ids + 1] = math.floor(char_id) end
    end
    if #ids == 0 then return { ok = true, items = {} } end
    local placeholders = {}
    for index = 1, #ids do placeholders[index] = '?' end
    local ok_rows, rows = pcall(function()
        return MySQL.query.await(([[
            SELECT `char_id`, `firstname`, `lastname`, `age`
              FROM `vh_identity` WHERE `char_id` IN (%s)
        ]]):format(table.concat(placeholders, ',')), ids)
    end)
    if not ok_rows or type(rows) ~= 'table' then return { ok = false, err = 'storage' } end

    local by_id = {}
    for _, row in ipairs(rows) do by_id[tonumber(row.char_id)] = row end
    local items = {}
    for _, char_id in ipairs(ids) do
        local row = by_id[char_id]
        if row then
            items[#items + 1] = {
                char_id = char_id,
                firstname = row.firstname,
                lastname = row.lastname,
                age = tonumber(row.age),
            }
        end
    end
    return { ok = true, items = items }
end)


-- ============================================================
-- EXPORTS LEGADOS DE LEITURA
-- ============================================================

exports('getIdentity', function(src)
    local char_id = _ready and resolve_online(src) or nil
    return char_id and copy_identity(get_identity(char_id)) or nil
end)

exports('getFullName', function(src)
    local char_id = _ready and resolve_online(src) or nil
    local identity = char_id and get_identity(char_id) or nil
    return identity and (identity.firstname .. ' ' .. identity.lastname) or 'Desconhecido'
end)

exports('getCharByRegistration', function(registration)
    if not _ready or type(registration) ~= 'string' then return nil end
    return tonumber(MySQL.scalar.await(
        'SELECT `char_id` FROM `vh_identity` WHERE `registration` = ? LIMIT 1',
        { registration }
    ))
end)

exports('getCharByPhone', function(phone)
    if not _ready or type(phone) ~= 'string' then return nil end
    return tonumber(MySQL.scalar.await(
        'SELECT `char_id` FROM `vh_identity` WHERE `phone` = ? LIMIT 1',
        { phone }
    ))
end)
