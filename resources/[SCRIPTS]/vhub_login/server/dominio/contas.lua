-- server/dominio/contas.lua — escritor único da conta de acesso Mirage.
-- Contatos ficam cifrados; buscas usam digest com pepper fora do banco.

VHubLogin = VHubLogin or {}

local C = {}; VHubLogin.Contas = C
local CFG = VHubLogin.Config

local PEPPER_KVP = "login_security_pepper_v1"
local MIGRATION_VERSION = 1
local _pepper


-- ============================================================
-- NORMALIZAÇÃO E VALIDAÇÃO
-- ============================================================

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function usernameNormalize(value)
  if type(value) ~= "string" then return nil end
  local username = trim(value)
  if #username < CFG.username_min or #username > CFG.username_max then return nil end
  if not username:match("^[%w_]+$") then return nil end
  return username
end

local function passwordLoginOK(value)
  return type(value) == "string"
    and #value >= CFG.password_legacy_min
    and #value <= CFG.password_max
    and not value:find("[%z\1-\31\127]")
end

local function passwordCreateOK(value)
  return type(value) == "string"
    and #value >= CFG.password_min
    and #value <= CFG.password_max
    and not value:find("[%z\1-\31\127]")
end

local function emailNormalize(value)
  if type(value) ~= "string" then return nil end
  local email = trim(value):lower()
  if #email < 5 or #email > CFG.email_max or email:find("%s") then return nil end
  if not email:match("^[%w%.%+_%-]+@[%w%-]+[%w%.%-]*%.[%a][%a]+$") then return nil end
  return email
end

local function whatsappNormalize(value)
  if type(value) ~= "string" then return nil end
  if value:find("[^%d%s%+%-%(%)]") then return nil end
  local digits = value:gsub("%D", "")
  if #digits < CFG.whatsapp_min or #digits > CFG.whatsapp_max then return nil end
  return digits
end

local function contactNormalize(value)
  if type(value) ~= "string" then return nil, nil end
  if value:find("@", 1, true) then return "email", emailNormalize(value) end
  return "whatsapp", whatsappNormalize(value)
end

local function secret(scope)
  if not _pepper then return nil end
  return scope .. ":" .. _pepper
end


-- ============================================================
-- SCHEMA E SEGREDO DA INSTALAÇÃO
-- ============================================================

local MIGRATION_COLUMNS = {
  { "hash_version", "ALTER TABLE login_accounts ADD COLUMN hash_version SMALLINT UNSIGNED NOT NULL DEFAULT 1 AFTER salt" },
  { "email_cipher", "ALTER TABLE login_accounts ADD COLUMN email_cipher VARBINARY(512) NULL AFTER hash_version" },
  { "email_lookup", "ALTER TABLE login_accounts ADD COLUMN email_lookup BINARY(32) NULL AFTER email_cipher" },
  { "whatsapp_cipher", "ALTER TABLE login_accounts ADD COLUMN whatsapp_cipher VARBINARY(256) NULL AFTER email_lookup" },
  { "whatsapp_lookup", "ALTER TABLE login_accounts ADD COLUMN whatsapp_lookup BINARY(32) NULL AFTER whatsapp_cipher" },
  { "terms_version", "ALTER TABLE login_accounts ADD COLUMN terms_version VARCHAR(32) NULL AFTER whatsapp_lookup" },
  { "terms_accepted_at", "ALTER TABLE login_accounts ADD COLUMN terms_accepted_at DATETIME(3) NULL AFTER terms_version" },
  { "age_18", "ALTER TABLE login_accounts ADD COLUMN age_18 TINYINT(1) NULL AFTER terms_accepted_at" },
  { "last_ip_digest", "ALTER TABLE login_accounts ADD COLUMN last_ip_digest BINARY(32) NULL AFTER age_18" },
}

local function schemaColumns()
  local rows = MySQL.query.await(
    "SELECT COLUMN_NAME FROM information_schema.COLUMNS " ..
    "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_accounts'", {}) or {}
  local found = {}
  for _, row in ipairs(rows) do found[tostring(row.COLUMN_NAME or row.column_name)] = true end
  return found
end

local function schemaIndexes()
  local rows = MySQL.query.await("SHOW INDEX FROM login_accounts", {}) or {}
  local found = {}
  for _, row in ipairs(rows) do found[tostring(row.Key_name or row.key_name)] = true end
  return found
end

-- Migra e valida o schema antes de liberar qualquer autenticação.
function C.migrarSchema()
  local applied = MySQL.scalar.await(
    "SELECT 1 FROM login_account_schema_migrations WHERE version = ? LIMIT 1",
    { MIGRATION_VERSION })

  if not applied then
    local columns = schemaColumns()
    for _, migration in ipairs(MIGRATION_COLUMNS) do
      if not columns[migration[1]] then MySQL.query.await(migration[2], {}) end
    end

    MySQL.query.await(
      "ALTER TABLE login_accounts MODIFY COLUMN pass_hash VARCHAR(255) NOT NULL", {})

    local indexes = schemaIndexes()
    if not indexes.uq_email_lookup then
      MySQL.query.await(
        "ALTER TABLE login_accounts ADD UNIQUE KEY uq_email_lookup (email_lookup)", {})
    end
    if not indexes.uq_whatsapp_lookup then
      MySQL.query.await(
        "ALTER TABLE login_accounts ADD UNIQUE KEY uq_whatsapp_lookup (whatsapp_lookup)", {})
    end

    MySQL.insert.await(
      "INSERT IGNORE INTO login_account_schema_migrations (version) VALUES (?)",
      { MIGRATION_VERSION })
  end

  local columns = schemaColumns()
  local indexes = schemaIndexes()
  for _, migration in ipairs(MIGRATION_COLUMNS) do
    if not columns[migration[1]] then return false, "schema_incompleto" end
  end
  if not indexes.uq_email_lookup or not indexes.uq_whatsapp_lookup then
    return false, "schema_incompleto"
  end
  return true
end

-- Inicializa o pepper server-only e o fixa no KVP no primeiro boot.
function C.prepararSeguranca()
  local configured = trim(GetConvar(CFG.pepper_convar, ""))
  local persisted = GetResourceKvpString(PEPPER_KVP)

  if persisted and #persisted >= 64 then
    if configured ~= "" and configured ~= persisted then
      return false, "pepper_divergente"
    end
    _pepper = persisted
    return true
  end

  local generated = configured
  if generated == "" then
    local serverKey = GetConvar("sv_licenseKey", "")
    if #serverKey < 16 then return false, "semente_seguranca_ausente" end
    local row = MySQL.single.await(
      "SELECT SHA2(CONCAT('vhub_login:v1:', ?), 256) AS pepper",
      { serverKey })
    generated = row and tostring(row.pepper or "") or ""
  end
  if #generated < 64 then return false, "pepper_invalido" end

  local ok = pcall(SetResourceKvp, PEPPER_KVP, generated)
  if not ok then return false, "pepper_nao_persistido" end
  _pepper = generated
  return true
end


-- ============================================================
-- MUTATIONS E QUERIES DE CONTA
-- ============================================================

-- Registra conta completa em um único INSERT; UNIQUE decide conflitos.
function C.registrar(user_id, data, endpoint)
  if not user_id or type(data) ~= "table" or not _pepper then
    return false, "cadastro_indisponivel"
  end

  local username = usernameNormalize(data.username)
  local email = emailNormalize(data.email)
  local whatsapp = whatsappNormalize(data.whatsapp)
  if not username then return false, "username_invalido" end
  if not passwordCreateOK(data.password) then return false, "senha_invalida" end
  if data.password ~= data.password_confirmation then return false, "senha_confirmacao" end
  if not email then return false, "email_invalido" end
  if not whatsapp then return false, "whatsapp_invalido" end
  if data.terms_accepted ~= true or data.age_18 ~= true then return false, "termos_obrigatorios" end
  if data.terms_version ~= CFG.terms_version then return false, "termos_desatualizados" end

  local piiKey = secret("pii")
  local contactKey = secret("contact")
  local passwordKey = secret("password")
  local ipKey = secret("ip")
  local ip = type(endpoint) == "string" and endpoint or ""

  local ok, inserted = pcall(function()
    return MySQL.insert.await([[
      INSERT INTO login_accounts
        (user_id, username, pass_hash, salt, hash_version,
         email_cipher, email_lookup, whatsapp_cipher, whatsapp_lookup,
         terms_version, terms_accepted_at, age_18, last_ip_digest)
      SELECT ?, ?, SHA2(CONCAT(g.salt, ?, ?), 256), g.salt, 2,
        AES_ENCRYPT(?, ?), UNHEX(SHA2(CONCAT(?, ?), 256)),
        AES_ENCRYPT(?, ?), UNHEX(SHA2(CONCAT(?, ?), 256)),
        ?, CURRENT_TIMESTAMP(3), 1,
        IF(? = '', NULL, UNHEX(SHA2(CONCAT(?, ?), 256)))
      FROM (
        SELECT LEFT(SHA2(CONCAT(UUID(), UUID(), ?, CURRENT_TIMESTAMP(6), RAND()), 256), 32) AS salt
      ) AS g
    ]], {
      user_id, username, data.password, passwordKey,
      email, piiKey, contactKey, email,
      whatsapp, piiKey, contactKey, whatsapp,
      CFG.terms_version, ip, ipKey, ip, secret("salt"),
    })
  end)
  if not ok or not inserted then return false, "cadastro_indisponivel" end
  return true
end

-- Autentica somente a conta vinculada ao UID e atualiza telemetria mínima.
function C.autenticar(user_id, usernameRaw, password, endpoint)
  local username = usernameNormalize(usernameRaw)
  if not user_id or not username or not passwordLoginOK(password) or not _pepper then
    return nil, "credencial_invalida"
  end

  local passwordKey = secret("password")
  local account = MySQL.single.await([[
    SELECT account_id, user_id, username, status, hash_version
      FROM login_accounts
     WHERE username = ?
       AND (
         (hash_version = 1 AND pass_hash = SHA2(CONCAT(salt, ?), 256)) OR
         (hash_version >= 2 AND pass_hash = SHA2(CONCAT(salt, ?, ?), 256))
       )
     LIMIT 1
  ]], { username, password, password, passwordKey })

  if not account or tonumber(account.status) ~= 1 then return nil, "credencial_invalida" end
  if tonumber(account.user_id) ~= tonumber(user_id) then return nil, "credencial_invalida" end

  if tonumber(account.hash_version) == 1 then
    local upgraded = MySQL.update.await([[
      UPDATE login_accounts AS a
      CROSS JOIN (
        SELECT LEFT(SHA2(CONCAT(UUID(), UUID(), ?, CURRENT_TIMESTAMP(6), RAND()), 256), 32) AS salt
      ) AS g
         SET a.pass_hash = SHA2(CONCAT(g.salt, ?, ?), 256),
             a.salt = g.salt,
             a.hash_version = 2
       WHERE a.account_id = ? AND a.user_id = ? AND a.hash_version = 1
    ]], { secret("salt"), password, passwordKey, account.account_id, user_id })
    if tonumber(upgraded) ~= 1 then return nil, "falha_db" end
    account.hash_version = 2
  end

  local ip = type(endpoint) == "string" and endpoint or ""
  local telemetryOK = pcall(function()
    MySQL.update.await([[
      UPDATE login_accounts
         SET last_login = NOW(),
             last_ip_digest = IF(? = '', NULL, UNHEX(SHA2(CONCAT(?, ?), 256)))
       WHERE account_id = ? AND user_id = ?
    ]], { ip, secret("ip"), ip, account.account_id, user_id })
  end)
  if not telemetryOK then return nil, "falha_db" end
  return account
end

-- Redefine a senha atomicamente apenas quando contato e UID atuais coincidem.
function C.recuperar(user_id, contactRaw, password, confirmation, endpoint)
  if not user_id or not _pepper then return false, "recuperacao_indisponivel" end
  if not passwordCreateOK(password) then return false, "senha_invalida" end
  if password ~= confirmation then return false, "senha_confirmacao" end

  local kind, contact = contactNormalize(contactRaw)
  if not contact then return false, "contato_invalido" end

  local column = kind == "email" and "email_lookup" or "whatsapp_lookup"
  local ip = type(endpoint) == "string" and endpoint or ""
  local ok, updated = pcall(function()
    return MySQL.update.await(([[
      UPDATE login_accounts AS a
      CROSS JOIN (
        SELECT LEFT(SHA2(CONCAT(UUID(), UUID(), ?, CURRENT_TIMESTAMP(6), RAND()), 256), 32) AS salt
      ) AS g
         SET a.pass_hash = SHA2(CONCAT(g.salt, ?, ?), 256),
             a.salt = g.salt,
             a.hash_version = 2,
             a.last_ip_digest = IF(? = '', NULL, UNHEX(SHA2(CONCAT(?, ?), 256)))
       WHERE a.user_id = ? AND a.status = 1
         AND a.%s = UNHEX(SHA2(CONCAT(?, ?), 256))
    ]]):format(column), {
      secret("salt"), password, secret("password"),
      ip, secret("ip"), ip,
      user_id, secret("contact"), contact,
    })
  end)
  if not ok then return false, "falha_db" end
  return true, tonumber(updated) == 1
end


-- ============================================================
-- TESTE CONTROLADO (somente vhub_test_mode=1)
-- ============================================================

-- Executa round-trip completo usando linha sentinela e cleanup obrigatório.
function C.testarPersistencia()
  if GetConvar("vhub_test_mode", "0") ~= "1" or not _pepper then return false end

  local uid = 4294967294
  local username = "vh_login_test"
  local email = "login-test@mirage.invalid"
  local whatsapp = "5511000000000"
  local oldPassword = "Teste@123"
  local newPassword = "Teste@456"
  local owned = false

  local function cleanup()
    if not owned then return end
    pcall(function()
      MySQL.query.await(
        "DELETE FROM login_accounts WHERE user_id = ? AND username = ?",
        { uid, username })
    end)
    owned = false
  end

  local ran, passed = pcall(function()
    local collision = MySQL.scalar.await(
      "SELECT 1 FROM login_accounts WHERE user_id = ? OR username = ? LIMIT 1",
      { uid, username })
    if collision then return false end

    local migrated1 = C.migrarSchema()
    local migrated2 = C.migrarSchema()
    if not migrated1 or not migrated2 then return false end

    local registered = C.registrar(uid, {
      username = username,
      password = oldPassword,
      password_confirmation = oldPassword,
      email = email,
      whatsapp = whatsapp,
      terms_accepted = true,
      age_18 = true,
      terms_version = CFG.terms_version,
    }, "127.0.0.1")
    if not registered then return false end
    owned = true

    local stored = MySQL.single.await([[
      SELECT CONVERT(AES_DECRYPT(email_cipher, ?) USING utf8mb4) AS email,
             CONVERT(AES_DECRYPT(whatsapp_cipher, ?) USING utf8mb4) AS whatsapp,
             OCTET_LENGTH(email_lookup) AS email_digest_len,
             OCTET_LENGTH(whatsapp_lookup) AS whatsapp_digest_len,
             OCTET_LENGTH(last_ip_digest) AS ip_digest_len,
             terms_version, age_18
        FROM login_accounts WHERE user_id = ? LIMIT 1
    ]], { secret("pii"), secret("pii"), uid })
    if not stored
      or stored.email ~= email
      or stored.whatsapp ~= whatsapp
      or tonumber(stored.email_digest_len) ~= 32
      or tonumber(stored.whatsapp_digest_len) ~= 32
      or tonumber(stored.ip_digest_len) ~= 32
      or stored.terms_version ~= CFG.terms_version
      or tonumber(stored.age_18) ~= 1 then
      return false
    end

    if not C.autenticar(uid, username, oldPassword, "127.0.0.1") then return false end

    local legacySalt = "0123456789abcdef0123456789abcdef"
    MySQL.update.await([[
      UPDATE login_accounts
         SET salt = ?, pass_hash = SHA2(CONCAT(?, ?), 256), hash_version = 1
       WHERE user_id = ?
    ]], { legacySalt, legacySalt, oldPassword, uid })
    if not C.autenticar(uid, username, oldPassword, "127.0.0.1") then return false end
    local upgraded = MySQL.scalar.await(
      "SELECT hash_version FROM login_accounts WHERE user_id = ?", { uid })
    if tonumber(upgraded) ~= 2 then return false end

    local missOK, missMatched = C.recuperar(
      uid, "ausente@mirage.invalid", newPassword, newPassword, "127.0.0.2")
    if not missOK or missMatched then return false end
    if not C.autenticar(uid, username, oldPassword, "127.0.0.2") then return false end

    local hitOK, hitMatched = C.recuperar(
      uid, email, newPassword, newPassword, "127.0.0.3")
    if not hitOK or not hitMatched then return false end
    if C.autenticar(uid, username, oldPassword, "127.0.0.3") then return false end
    if not C.autenticar(uid, username, newPassword, "127.0.0.3") then return false end
    return true
  end)
  cleanup()
  return ran and passed == true
end


return C
