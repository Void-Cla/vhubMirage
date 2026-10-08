---@diagnostic disable: undefined-global, lowercase-global

local cfg = VHubLspd.cfg
local Accounts = {}
VHubLspd.Accounts = Accounts

local HASH_VERSION_SCRYPT = 2
local schemaReady = false

local function Log(level, fmt, ...) if VHubLspd.Log then VHubLspd.Log(level, fmt, ...) end end

local function queryRow(sql, params)
    local p = promise.new()
    exports.oxmysql:query(sql, params, function(rows) p:resolve(rows and rows[1] or nil) end)
    return Citizen.Await(p)
end

local function execute(sql, params)
    local p = promise.new()
    exports.oxmysql:execute(sql, params, function(affected) p:resolve(affected or 0) end)
    return Citizen.Await(p)
end

local function pepper()
    local value = GetConvar('vhub_login_pepper', '')
    if #value < 64 then return nil end
    return 'vhub_lspd:v1:' .. value
end

local function prepareSchema()
    if schemaReady then return true end
    local hash = queryRow("SHOW COLUMNS FROM vhub_lspd_accounts LIKE 'hash_version'")
    if not hash then
        execute('ALTER TABLE vhub_lspd_accounts ADD COLUMN hash_version SMALLINT UNSIGNED NOT NULL DEFAULT 1 AFTER salt')
    end
    local pass = queryRow("SHOW COLUMNS FROM vhub_lspd_accounts LIKE 'pass_hash'")
    if not pass or not tostring(pass.Type):lower():match('varchar') then
        execute('ALTER TABLE vhub_lspd_accounts MODIFY COLUMN pass_hash VARCHAR(255) NOT NULL')
    end
    schemaReady = queryRow("SHOW COLUMNS FROM vhub_lspd_accounts LIKE 'hash_version'") ~= nil
    return schemaReady
end

local function sanitizePass(raw)
    if type(raw) ~= 'string' then return nil, 'senha_invalida' end
    local s = raw:gsub('[%c]', '')
    if #s < 3 or #s > 32 then return nil, 'senha_tamanho' end
    return s
end

function Accounts.ensure(char_id)
    char_id = tonumber(char_id)
    if not char_id or not prepareSchema() then return false end
    local key = pepper()
    if not key or type(VHubScrypt) ~= 'table' then return false end
    local hash = VHubScrypt.hash(cfg.ipad.defaultPass, key)
    if not hash then return false end
    execute('INSERT IGNORE INTO vhub_lspd_accounts (char_id, pass_hash, salt, hash_version, must_change) VALUES (?, ?, \'\', ?, 1)', { char_id, hash, HASH_VERSION_SCRYPT })
    return true
end

function Accounts.verify(char_id, password)
    char_id = tonumber(char_id)
    if not char_id or type(password) ~= 'string' or password == '' then return 'bad' end
    if not Accounts.ensure(char_id) then return 'bad' end
    local row = queryRow('SELECT pass_hash, salt, hash_version, must_change FROM vhub_lspd_accounts WHERE char_id = ? LIMIT 1', { char_id })
    if not row then return 'bad' end
    local version = tonumber(row.hash_version) or 1
    local valid, rehash = false, false
    if version >= HASH_VERSION_SCRYPT then
        local key = pepper()
        if not key then return 'bad' end
        valid, rehash = VHubScrypt.verify(password, key, row.pass_hash)
    else
        local result = queryRow('SELECT (pass_hash = SHA2(CONCAT(salt, ?), 256)) AS okpass FROM vhub_lspd_accounts WHERE char_id = ? LIMIT 1', { password, char_id })
        valid = result and ((result.okpass == true) or tonumber(result.okpass) == 1) or false
        rehash = valid
    end
    if not valid then return 'bad' end
    if rehash then
        local hash = VHubScrypt.hash(password, pepper())
        if not hash then return 'bad' end
        execute('UPDATE vhub_lspd_accounts SET pass_hash = ?, salt = \'\', hash_version = ? WHERE char_id = ? AND pass_hash = ?', { hash, HASH_VERSION_SCRYPT, char_id, row.pass_hash })
    end
    local mustChange = (row.must_change == true) or (tonumber(row.must_change) == 1)
    return mustChange and 'must_change' or 'ok'
end

function Accounts.setPassword(char_id, newPass)
    char_id = tonumber(char_id)
    if not char_id or not prepareSchema() then return false, 'char_invalido' end
    local pass, err = sanitizePass(newPass)
    if not pass then return false, err end
    local key = pepper()
    if not key then return false, 'segredo_indisponivel' end
    local hash = VHubScrypt.hash(pass, key)
    if not hash then return false, 'hash_indisponivel' end
    local affected = execute('UPDATE vhub_lspd_accounts SET pass_hash = ?, salt = \'\', hash_version = ?, must_change = 0 WHERE char_id = ?', { hash, HASH_VERSION_SCRYPT, char_id })
    if affected and affected > 0 then
        Log('info', 'senha LSPD trocada para char_id %s', tostring(char_id))
        return true
    end
    return false, 'conta_inexistente'
end

function Accounts.testarCriptografia()
    if GetConvar('vhub_test_mode', '0') ~= '1' then return false, 'modo_teste_desligado' end
    local fresh, legacy = 4294967200, 4294967201
    local defaultPass, changedPass, legacyPass = cfg.ipad.defaultPass, 'TesteLspd@456', 'TesteLspd@789'
    pcall(function() execute('DELETE FROM vhub_lspd_accounts WHERE char_id IN (?, ?)', { fresh, legacy }) end)
    local ok, result = pcall(function()
        if not Accounts.ensure(fresh) or Accounts.verify(fresh, defaultPass) ~= 'must_change' then return false end
        if not Accounts.setPassword(fresh, changedPass) or Accounts.verify(fresh, changedPass) ~= 'ok' then return false end
        execute('INSERT INTO vhub_lspd_accounts (char_id, pass_hash, salt, hash_version, must_change) VALUES (?, SHA2(CONCAT(?, ?), 256), ?, 1, 0)', { legacy, 'a1b2c3d4e5f60708', legacyPass, 'a1b2c3d4e5f60708' })
        if Accounts.verify(legacy, legacyPass) ~= 'ok' then return false end
        local migrated = queryRow('SELECT hash_version, pass_hash FROM vhub_lspd_accounts WHERE char_id = ? LIMIT 1', { legacy })
        return migrated and tonumber(migrated.hash_version) == HASH_VERSION_SCRYPT and tostring(migrated.pass_hash):sub(1, 8) == '$scrypt$'
    end)
    pcall(function() execute('DELETE FROM vhub_lspd_accounts WHERE char_id IN (?, ?)', { fresh, legacy }) end)
    return ok and result == true, ok and nil or tostring(result)
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Citizen.CreateThread(function()
        if not prepareSchema() then Log('error', 'migração de credenciais LSPD indisponível') end
    end)
end)

RegisterCommand('vhub_lspd_crypto_test', function(source)
    if source ~= 0 then return end
    Citizen.CreateThread(function()
        local ok, err = Accounts.testarCriptografia()
        print(('[vhub_lspdtool] crypto_test=%s%s'):format(tostring(ok), err and (' err=' .. err) or ''))
    end)
end, true)
