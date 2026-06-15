---@diagnostic disable: undefined-global, lowercase-global

-- accounts.lua — credencial de acesso ao app LSPD do iPad (server-authoritative).
-- Login = char_id do policial + senha. A senha é guardada como HASH (SHA-256) com salt
-- por linha — o hashing é feito pelo MySQL (SHA2), sem lib de cripto em Lua e sem nunca
-- trafegar/persistir a senha em texto. must_change força a troca no primeiro acesso.
--
-- ATENÇÃO: todas as funções usam Citizen.Await (oxmysql) → chamar SEMPRE dentro de
-- Citizen.CreateThread (o ipadRelay já garante isso).

local cfg = VHubLspd.cfg

local Accounts = {}
VHubLspd.Accounts = Accounts


-- ============================================================
-- HELPERS
-- ============================================================

local function Log(level, fmt, ...) if VHubLspd.Log then VHubLspd.Log(level, fmt, ...) end end

math.randomseed(os.time() + GetGameTimer())

-- gera um salt hex de 32 caracteres (entropia por conta + defesa contra rainbow tables)
local function genSalt()
    local hex, t = '0123456789abcdef', {}
    for i = 1, 32 do local r = math.random(1, 16); t[i] = hex:sub(r, r) end
    return table.concat(t)
end

-- query síncrona (dentro de thread): retorna a 1ª linha ou nil
local function queryRow(sql, params)
    local p = promise.new()
    exports.oxmysql:query(sql, params, function(rows) p:resolve(rows and rows[1] or nil) end)
    return Citizen.Await(p)
end

-- execute síncrono (dentro de thread): retorna affectedRows
local function execute(sql, params)
    local p = promise.new()
    exports.oxmysql:execute(sql, params, function(affected) p:resolve(affected or 0) end)
    return Citizen.Await(p)
end

-- valida/sanitiza uma senha nova; retorna (senha_ok) ou (nil, motivo)
local function sanitizePass(raw)
    if type(raw) ~= 'string' then return nil, 'senha_invalida' end
    local s = raw:gsub('[%c]', '')
    if #s < 3 or #s > 32 then return nil, 'senha_tamanho' end
    return s
end


-- ============================================================
-- PROVISIONAMENTO
-- ============================================================

-- garante que a conta do char_id existe (cria com senha padrão + must_change na 1ª vez)
function Accounts.ensure(char_id)
    char_id = tonumber(char_id); if not char_id then return false end
    local salt = genSalt()
    -- INSERT IGNORE: idempotente — só cria se ainda não houver linha para o char_id
    execute(
        'INSERT IGNORE INTO vhub_lspd_accounts (char_id, pass_hash, salt, must_change) ' ..
        'VALUES (?, SHA2(CONCAT(?, ?), 256), ?, 1)',
        { char_id, salt, cfg.ipad.defaultPass, salt }
    )
    return true
end


-- ============================================================
-- VERIFICAÇÃO / TROCA
-- ============================================================

-- verifica a senha do char_id; retorna 'ok' | 'must_change' | 'bad'
function Accounts.verify(char_id, password)
    char_id = tonumber(char_id); if not char_id then return 'bad' end
    if type(password) ~= 'string' or password == '' then return 'bad' end

    Accounts.ensure(char_id)   -- garante a conta (1º acesso = senha padrão)

    local row = queryRow(
        'SELECT must_change, (pass_hash = SHA2(CONCAT(salt, ?), 256)) AS okpass ' ..
        'FROM vhub_lspd_accounts WHERE char_id = ? LIMIT 1',
        { password, char_id }
    )
    if not row then return 'bad' end

    -- oxmysql pode devolver a comparação como 1/0 OU como boolean — aceita ambos
    local okpass = (row.okpass == true) or (tonumber(row.okpass) == 1)
    if not okpass then return 'bad' end

    local mustChange = (row.must_change == true) or (tonumber(row.must_change) == 1)
    return mustChange and 'must_change' or 'ok'
end


-- troca a senha do char_id (limpa must_change); retorna (true) ou (false, motivo)
function Accounts.setPassword(char_id, newPass)
    char_id = tonumber(char_id); if not char_id then return false, 'char_invalido' end

    local pass, err = sanitizePass(newPass)
    if not pass then return false, err end

    local salt = genSalt()
    local affected = execute(
        'UPDATE vhub_lspd_accounts SET pass_hash = SHA2(CONCAT(?, ?), 256), salt = ?, ' ..
        'must_change = 0 WHERE char_id = ?',
        { salt, pass, salt, char_id }
    )
    if affected and affected > 0 then
        Log('info', 'senha trocada para char_id %s', tostring(char_id))
        return true
    end
    return false, 'conta_inexistente'
end
