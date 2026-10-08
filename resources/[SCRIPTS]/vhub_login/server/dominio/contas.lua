-- server/dominio/contas.lua — escritor único da conta de acesso Mirage.
-- Contatos ficam cifrados; buscas usam digest com pepper fora do banco.

VHubLogin = VHubLogin or {}

local C = {}; VHubLogin.Contas = C
local CFG = VHubLogin.Config

local PEPPER_KVP = "login_security_pepper_v1"
local MIGRATION_VERSION = 4
local HASH_VERSION_SCRYPT = 3
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
  { "last_seen_at", "ALTER TABLE login_accounts ADD COLUMN last_seen_at DATETIME NULL AFTER last_login" },
}

-- Migração v3: coluna identifier_digest na tabela de ban (ADR #89 — ban por FiveM native IDs).
local BAN_MIGRATION_V3 = {
  { "identifier_digest",
    "ALTER TABLE login_ban_vectors ADD COLUMN identifier_digest BINARY(32) NULL AFTER whatsapp_lookup" },
  { "idx_ban_identifier",
    "ALTER TABLE login_ban_vectors ADD KEY idx_ban_identifier (identifier_digest)" },
}

-- Garante a tabela de vetores de banimento (ADR #86/#89).
local BAN_TABLE_SQL = [[
  CREATE TABLE IF NOT EXISTS login_ban_vectors (
    id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    account_id        INT UNSIGNED    NULL,
    ip_digest         BINARY(32)      NULL,
    email_lookup      BINARY(32)      NULL,
    whatsapp_lookup   BINARY(32)      NULL,
    identifier_digest BINARY(32)      NULL,
    banned_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    banned_by         VARCHAR(64)     NOT NULL,
    reason            VARCHAR(255)    NOT NULL,
    expires_at        DATETIME        NULL,
    PRIMARY KEY (id),
    KEY idx_ban_ip           (ip_digest),
    KEY idx_ban_email        (email_lookup),
    KEY idx_ban_whatsapp     (whatsapp_lookup),
    KEY idx_ban_identifier   (identifier_digest),
    CONSTRAINT fk_ban_account FOREIGN KEY (account_id)
      REFERENCES login_accounts(account_id) ON DELETE SET NULL ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local function schemaColumns(table_name)
  local rows = MySQL.query.await(
    "SELECT COLUMN_NAME FROM information_schema.COLUMNS " ..
    "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?", { table_name }) or {}
  local found = {}
  for _, row in ipairs(rows) do found[tostring(row.COLUMN_NAME or row.column_name)] = true end
  return found
end

local function schemaIndexes(table_name)
  local ok, rows = pcall(function()
    return MySQL.query.await("SHOW INDEX FROM `" .. table_name .. "`", {}) or {}
  end)
  local found = {}
  if ok then
    for _, row in ipairs(rows) do found[tostring(row.Key_name or row.key_name)] = true end
  end
  return found
end

-- Migra e valida o schema antes de liberar qualquer autenticação.
function C.migrarSchema()
  local applied = MySQL.scalar.await(
    "SELECT 1 FROM login_account_schema_migrations WHERE version = ? LIMIT 1",
    { MIGRATION_VERSION })

  if not applied then
    local columns = schemaColumns("login_accounts")
    for _, migration in ipairs(MIGRATION_COLUMNS) do
      if not columns[migration[1]] then MySQL.query.await(migration[2], {}) end
    end

    MySQL.query.await(
      "ALTER TABLE login_accounts MODIFY COLUMN pass_hash VARCHAR(255) NOT NULL", {})

    local indexes = schemaIndexes("login_accounts")
    if not indexes.uq_email_lookup then
      MySQL.query.await(
        "ALTER TABLE login_accounts ADD UNIQUE KEY uq_email_lookup (email_lookup)", {})
    end
    if not indexes.uq_whatsapp_lookup then
      MySQL.query.await(
        "ALTER TABLE login_accounts ADD UNIQUE KEY uq_whatsapp_lookup (whatsapp_lookup)", {})
    end

    -- Garante a tabela de ban (cria se não existe) e aplica colunas novas (v3).
    pcall(function() MySQL.query.await(BAN_TABLE_SQL, {}) end)
    local banCols = schemaColumns("login_ban_vectors")
    local banIdx  = schemaIndexes("login_ban_vectors")
    for _, m in ipairs(BAN_MIGRATION_V3) do
      if not banCols[m[1]] and not banIdx[m[1]] then
        pcall(function() MySQL.query.await(m[2], {}) end)
      end
    end

    MySQL.insert.await(
      "INSERT IGNORE INTO login_account_schema_migrations (version) VALUES (?)",
      { MIGRATION_VERSION })
  end

  local columns = schemaColumns("login_accounts")
  local indexes = schemaIndexes("login_accounts")
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

  if configured == "" then return false, "pepper_configurado_ausente" end
  if #configured < 64 or type(VHubScrypt) ~= "table" then
    return false, "seguranca_indisponivel"
  end

  local ok = pcall(SetResourceKvp, PEPPER_KVP, configured)
  if not ok then return false, "pepper_nao_persistido" end
  _pepper = configured
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
  local passHash = VHubScrypt.hash(data.password, passwordKey)
  if not passHash then return false, "cadastro_indisponivel" end

  local ok, inserted = pcall(function()
    return MySQL.insert.await([[
      INSERT INTO login_accounts
        (user_id, username, pass_hash, salt, hash_version,
         email_cipher, email_lookup, whatsapp_cipher, whatsapp_lookup,
         terms_version, terms_accepted_at, age_18, last_ip_digest)
      VALUES (?, ?, ?, '', ?,
        AES_ENCRYPT(?, ?), UNHEX(SHA2(CONCAT(?, ?), 256)),
        AES_ENCRYPT(?, ?), UNHEX(SHA2(CONCAT(?, ?), 256)),
        ?, CURRENT_TIMESTAMP(3), 1,
        IF(? = '', NULL, UNHEX(SHA2(CONCAT(?, ?), 256))))
    ]], {
      user_id, username, passHash, HASH_VERSION_SCRYPT,
      email, piiKey, contactKey, email,
      whatsapp, piiKey, contactKey, whatsapp,
      CFG.terms_version, ip, ipKey, ip,
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
  local queryOK, account = pcall(function()
    return MySQL.single.await([[
      SELECT account_id, user_id, username, status, hash_version, pass_hash, salt,
             HEX(email_lookup) AS email_lookup, HEX(whatsapp_lookup) AS whatsapp_lookup
        FROM login_accounts WHERE username = ? LIMIT 1
    ]], { username })
  end)
  if not queryOK then return nil, "falha_db" end

  if not account or tonumber(account.status) ~= 1
      or tonumber(account.user_id) ~= tonumber(user_id) then
    VHubScrypt.hash(password, passwordKey)
    return nil, "credencial_invalida"
  end

  local version = tonumber(account.hash_version) or 0
  local valid, rehash = false, false
  if version >= HASH_VERSION_SCRYPT then
    local verifyError
    valid, rehash, verifyError = VHubScrypt.verify(password, passwordKey, account.pass_hash)
    if verifyError and verifyError ~= "senha_incorreta" then return nil, "falha_hash" end
  elseif version == 1 or version == 2 then
    local legacyOK, legacyMatch = pcall(function()
      return MySQL.scalar.await([[
        SELECT (
          (hash_version = 1 AND pass_hash = SHA2(CONCAT(salt, ?), 256)) OR
          (hash_version = 2 AND pass_hash = SHA2(CONCAT(salt, ?, ?), 256))
        )
          FROM login_accounts
         WHERE account_id = ? AND user_id = ? AND hash_version = ?
         LIMIT 1
      ]], { password, password, passwordKey, account.account_id, user_id, version })
    end)
    if not legacyOK then return nil, "falha_db" end
    valid = legacyMatch == true or tonumber(legacyMatch) == 1
    if not valid then VHubScrypt.hash(password, passwordKey) end
    rehash = valid
  else
    VHubScrypt.hash(password, passwordKey)
    return nil, "falha_hash"
  end

  if not valid then return nil, "credencial_invalida" end

  if rehash then
    local newHash = VHubScrypt.hash(password, passwordKey)
    if not newHash then return nil, "falha_hash" end
    local upgradeOK, upgraded = pcall(function()
      return MySQL.update.await([[
        UPDATE login_accounts
           SET pass_hash = ?, salt = '', hash_version = ?
         WHERE account_id = ? AND user_id = ? AND pass_hash = ? AND hash_version = ?
      ]], {
        newHash, HASH_VERSION_SCRYPT, account.account_id, user_id,
        account.pass_hash, version,
      })
    end)
    if not upgradeOK then return nil, "falha_db" end
    if tonumber(upgraded) ~= 1 then
      local current = MySQL.single.await(
        "SELECT pass_hash, hash_version FROM login_accounts WHERE account_id = ? AND user_id = ?",
        { account.account_id, user_id })
      if not current or tonumber(current.hash_version) < HASH_VERSION_SCRYPT then
        return nil, "falha_db"
      end
      local currentValid = VHubScrypt.verify(password, passwordKey, current.pass_hash)
      if not currentValid then return nil, "credencial_invalida" end
    end
    account.hash_version = HASH_VERSION_SCRYPT
  end

  local ip = type(endpoint) == "string" and endpoint or ""
  local telemetryOK = pcall(function()
    MySQL.update.await([[
      UPDATE login_accounts
         SET last_login    = NOW(),
             last_seen_at  = NOW(),
             last_ip_digest = IF(? = '', NULL, UNHEX(SHA2(CONCAT(?, ?), 256)))
       WHERE account_id = ? AND user_id = ?
    ]], { ip, secret("ip"), ip, account.account_id, user_id })
  end)
  if not telemetryOK then return nil, "falha_db" end
  account.pass_hash = nil
  account.salt = nil
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
  local passHash = VHubScrypt.hash(password, secret("password"))
  if not passHash then return false, "recuperacao_indisponivel" end
  local ok, updated = pcall(function()
    return MySQL.update.await(([[
      UPDATE login_accounts AS a
         SET a.pass_hash = ?,
             a.salt = '',
             a.hash_version = ?,
             a.last_ip_digest = IF(? = '', NULL, UNHEX(SHA2(CONCAT(?, ?), 256)))
       WHERE a.user_id = ? AND a.status = 1
         AND a.%s = UNHEX(SHA2(CONCAT(?, ?), 256))
    ]]):format(column), {
      passHash, HASH_VERSION_SCRYPT,
      ip, secret("ip"), ip,
      user_id, secret("contact"), contact,
    })
  end)
  if not ok then return false, "falha_db" end
  return true, tonumber(updated) == 1
end


-- ============================================================
-- BAN MULTI-VETOR (ADR #86/#89)
-- ============================================================

-- Extrai mapa de identifiers FiveM nativos do player conectado (server-side, pre-auth).
-- Usa GetPlayerIdentifierByType por tipo — mais eficiente que iterar GetPlayerIdentifiers.
-- Prioridade de confiança (2026): fivem > license2/license > discord > steam.
-- xbl/live removidos pela CFX em 27/04/2026 — não são coletados.
-- Retorna:
--   ids = { fivem=str, license=str, discord=str, steam=str } (valor = raw "tipo:valor")
--   hwToken = string bruta do token hardware-0 (server-specific fingerprint) ou nil
function C.extrairIdentifiers(src)
  local ids = {}

  -- fivem: é o mais confiável (conta Cfx.re com email verificado + 2FA desde jun 2024)
  local fivemRaw = GetPlayerIdentifierByType(src, "fivem")
  if fivemRaw then ids.fivem = fivemRaw end

  -- license2 prioritário sobre license: para jogadores Steam, license2 é o hash ROS puro
  local licRaw = GetPlayerIdentifierByType(src, "license2")
               or GetPlayerIdentifierByType(src, "license")
  if licRaw then ids.license = licRaw end

  local discRaw = GetPlayerIdentifierByType(src, "discord")
  if discRaw then ids.discord = discRaw end

  local steamRaw = GetPlayerIdentifierByType(src, "steam")
  if steamRaw then ids.steam = steamRaw end

  -- Hardware token índice 0: mais estável (server-specific, só muda com HW real).
  -- rawget(_G) evita warning do LSP; pcall protege builds que não exponham a nativa.
  local hwToken
  local nativeToken = rawget(_G, "GetPlayerToken")
  if nativeToken then
    local ok, tok = pcall(nativeToken, src, 0)
    if ok and type(tok) == "string" and #tok > 4 then hwToken = tok end
  end

  return ids, hwToken
end

-- Verifica se algum dos vetores recebidos está ativo na tabela de ban.
-- ip: string "addr:port" de GetPlayerEndpoint ou nil;
-- email_lookup/whatsapp_lookup: BINARY(32) já materializados ou nil;
-- identifiers: tabela { fivem=str, license=str, ... } ou nil;
-- hardware_token: string bruta do GetPlayerToken ou nil.
-- hw-token usa scope "hwtoken" (distinto de "identifier") — vetores de confiança separados.
function C.verificarBan(ip, email_lookup, whatsapp_lookup, identifiers, hardware_token)
  if not _pepper then return false end

  -- Scope separado para hw-token (server-specific fingerprint) vs identifiers de rede.
  local id_key = secret("identifier")
  local hw_key = secret("hwtoken")

  -- params e cláusulas em ordem: IP, email, whatsapp, identifiers, hw-token.
  local params   = {}
  local clauses  = {}

  -- IP: só inclui cláusula se há IP não-vazio (evita digest("") dar match em ban velho).
  local ip_str = (type(ip) == "string" and ip ~= "") and ip or nil
  if ip_str then
    clauses[#clauses + 1] =
      "(ip_digest IS NOT NULL AND ip_digest = UNHEX(SHA2(CONCAT(?, ?), 256)))"
    params[#params + 1] = ip_str
    params[#params + 1] = secret("ip")
  end

  -- Email e whatsapp: digests HEX (de HEX(email_lookup) em C.autenticar). Comparação via
  -- UNHEX(?) — NUNCA ligar binário cru como parâmetro (oxmysql serializa BINARY como tabela →
  -- SQL malformado → throw). Guarda de tipo/tamanho: só string hexadecimal de 64 chars entra.
  local function hex_ok(v) return type(v) == "string" and v:match("^%x+$") ~= nil and #v <= 64 end
  if hex_ok(email_lookup) then
    clauses[#clauses + 1] = "(email_lookup IS NOT NULL AND email_lookup = UNHEX(?))"
    params[#params + 1]   = email_lookup
  end
  if hex_ok(whatsapp_lookup) then
    clauses[#clauses + 1] = "(whatsapp_lookup IS NOT NULL AND whatsapp_lookup = UNHEX(?))"
    params[#params + 1]   = whatsapp_lookup
  end

  -- Identifiers FiveM nativos: fivem:, license:, license2:, discord:, steam:.
  if type(identifiers) == "table" and id_key then
    for _, v in pairs(identifiers) do
      if type(v) == "string" and #v > 0 then
        clauses[#clauses + 1] =
          "(identifier_digest IS NOT NULL AND identifier_digest = UNHEX(SHA2(CONCAT(?, ?), 256)))"
        params[#params + 1] = v
        params[#params + 1] = id_key
      end
    end
  end

  -- Hardware token: scope "hwtoken" (distinto de "identifier" — contenção P2 ADR #89).
  if type(hardware_token) == "string" and #hardware_token > 0 and hw_key then
    clauses[#clauses + 1] =
      "(identifier_digest IS NOT NULL AND identifier_digest = UNHEX(SHA2(CONCAT(?, ?), 256)))"
    params[#params + 1] = hardware_token
    params[#params + 1] = hw_key
  end

  if #clauses == 0 then return false end

  -- Consulta protegida (L-07/R7): uma falha de infra da verificação de ban NÃO pode derrubar
  -- o login inteiro (era o que acontecia — throw não capturado colapsava a autenticação).
  local queryOK, row = pcall(function()
    return MySQL.single.await(
      "SELECT id, reason FROM login_ban_vectors"
      .. " WHERE (expires_at IS NULL OR expires_at > NOW())"
      .. " AND (" .. table.concat(clauses, " OR ") .. ") LIMIT 1",
      params)
  end)
  if not queryOK or not row then return false end
  return true, row.reason
end

-- Registra ban multi-vetor. Insere uma linha por vetor discreto para indexação eficiente.
-- ip: string; email_lookup/whatsapp_lookup: BINARY(32); identifiers/hardware_token opcionais.
-- expires_at: string ISO ou nil (permanente).
function C.registrarBan(account_id, ip, email_lookup, whatsapp_lookup, banned_by, reason, expires_at, identifiers, hardware_token)
  if not _pepper then return false, "seguranca_indisponivel" end
  if type(banned_by) ~= "string" or #banned_by == 0 then return false, "admin_invalido" end
  if type(reason) ~= "string" or #reason == 0 then return false, "motivo_invalido" end

  local ip_bin = (type(ip) == "string" and ip ~= "") and ip or nil

  -- Identifiers de rede (scope "identifier") e hardware token (scope "hwtoken") separados
  -- para evitar colisão de digest entre vetores de confiança diferentes (contenção P2 ADR #89).
  local id_raws = {}
  if type(identifiers) == "table" then
    for _, v in pairs(identifiers) do
      if type(v) == "string" and #v > 0 then id_raws[#id_raws + 1] = v end
    end
  end
  local hw_raw = (type(hardware_token) == "string" and #hardware_token > 0)
    and hardware_token or nil

  if not ip_bin and not email_lookup and not whatsapp_lookup
     and #id_raws == 0 and not hw_raw then
    return false, "sem_vetor"
  end

  local id_key = secret("identifier")
  local hw_key = secret("hwtoken")
  local acc_id = tonumber(account_id) or nil
  local exp    = expires_at or nil
  local last_id

  -- email_lookup/whatsapp_lookup chegam como HEX (de HEX(email_lookup) em C.autenticar); grava via
  -- UNHEX. Sentinela '' (não nil) evita buraco no array de params (nil no meio trunca a lista e
  -- desalinha os '?'). Só string hexadecimal válida entra; qualquer outra coisa vira ''.
  local function hex_or_empty(v)
    return (type(v) == "string" and v:match("^%x+$") ~= nil and #v <= 64) and v or ""
  end
  local email_hex = hex_or_empty(email_lookup)
  local whats_hex = hex_or_empty(whatsapp_lookup)
  local ip_sent   = ip_bin or ""

  -- Linha principal: IP + email + whatsapp (vetores legados, um INSERT único).
  if ip_bin or email_hex ~= "" or whats_hex ~= "" then
    local ok, id = pcall(function()
      return MySQL.insert.await([[
        INSERT INTO login_ban_vectors
          (account_id, ip_digest, email_lookup, whatsapp_lookup, banned_by, reason, expires_at)
        VALUES (?,
          IF(? = '', NULL, UNHEX(SHA2(CONCAT(?, ?), 256))),
          IF(? = '', NULL, UNHEX(?)), IF(? = '', NULL, UNHEX(?)),
          ?, ?, ?)
      ]], {
        acc_id,
        ip_sent, ip_sent, secret("ip"),
        email_hex, email_hex, whats_hex, whats_hex,
        banned_by, reason, exp,
      })
    end)
    if not ok or not tonumber(id) then return false, "falha_db" end
    last_id = tonumber(id)
  end

  -- Uma linha por identifier FiveM nativo (license, fivem, discord, steam) — scope "identifier".
  if id_key then
    for _, raw in ipairs(id_raws) do
      pcall(function()
        local new_id = MySQL.insert.await([[
          INSERT INTO login_ban_vectors
            (account_id, identifier_digest, banned_by, reason, expires_at)
          VALUES (?, UNHEX(SHA2(CONCAT(?, ?), 256)), ?, ?, ?)
        ]], { acc_id, raw, id_key, banned_by, reason, exp })
        last_id = last_id or tonumber(new_id)
      end)
    end
  end

  -- Linha extra para hardware token — scope "hwtoken" separado (server-specific fingerprint).
  if hw_raw and hw_key then
    pcall(function()
      local new_id = MySQL.insert.await([[
        INSERT INTO login_ban_vectors
          (account_id, identifier_digest, banned_by, reason, expires_at)
        VALUES (?, UNHEX(SHA2(CONCAT(?, ?), 256)), ?, ?, ?)
      ]], { acc_id, hw_raw, hw_key, banned_by, reason, exp })
      last_id = last_id or tonumber(new_id)
    end)
  end

  if not last_id then return false, "falha_db" end
  return true, last_id
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

  local checkpoint = "inicio"
  local ran, passed = pcall(function()
    local collision = MySQL.scalar.await(
      "SELECT 1 FROM login_accounts WHERE user_id = ? OR username = ? LIMIT 1",
      { uid, username })
    if collision then checkpoint = "colisao" return false end

    local migrated1 = C.migrarSchema()
    local migrated2 = C.migrarSchema()
    if not migrated1 or not migrated2 then checkpoint = "migracao" return false end

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
    if not registered then checkpoint = "cadastro" return false end
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
      or not (stored.age_18 == true or tonumber(stored.age_18) == 1) then
      checkpoint = "dados_cifrados" return false
    end

    if not C.autenticar(uid, username, oldPassword, "127.0.0.1") then checkpoint = "auth_scrypt" return false end

    local legacySalt = "0123456789abcdef0123456789abcdef"
    MySQL.update.await([[
      UPDATE login_accounts
         SET salt = ?, pass_hash = SHA2(CONCAT(?, ?), 256), hash_version = 1
       WHERE user_id = ?
    ]], { legacySalt, legacySalt, oldPassword, uid })
    if not C.autenticar(uid, username, oldPassword, "127.0.0.1") then checkpoint = "auth_legado" return false end
    local upgraded = MySQL.scalar.await(
      "SELECT hash_version FROM login_accounts WHERE user_id = ?", { uid })
    if tonumber(upgraded) ~= HASH_VERSION_SCRYPT then checkpoint = "rehash_legado" return false end

    local missOK, missMatched = C.recuperar(
      uid, "ausente@mirage.invalid", newPassword, newPassword, "127.0.0.2")
    if not missOK or missMatched then checkpoint = "recuperacao_miss" return false end
    if not C.autenticar(uid, username, oldPassword, "127.0.0.2") then checkpoint = "auth_pos_miss" return false end

    local hitOK, hitMatched = C.recuperar(
      uid, email, newPassword, newPassword, "127.0.0.3")
    if not hitOK or not hitMatched then checkpoint = "recuperacao_hit" return false end
    if C.autenticar(uid, username, oldPassword, "127.0.0.3") then checkpoint = "senha_antiga" return false end
    if not C.autenticar(uid, username, newPassword, "127.0.0.3") then checkpoint = "senha_nova" return false end

    -- round-trip ban: IP + email + identifier FiveM → registrarBan → verificarBan
    local acc = C.autenticar(uid, username, newPassword, "127.0.0.1")
    if not acc then checkpoint = "auth_ban" return false end
    -- verifica last_seen_at foi escrito por autenticar
    local seenAt = MySQL.scalar.await(
      "SELECT last_seen_at FROM login_accounts WHERE user_id = ?", { uid })
    if not seenAt then checkpoint = "telemetria" return false end

    local fakeIds = { license = "license:test_roundtrip_fake_abc123" }
    local banOK = C.registrarBan(
      acc.account_id, "198.51.100.1", acc.email_lookup, nil,
      "vh_test", "teste_ban_roundtrip", nil, fakeIds, nil)
    if not banOK then checkpoint = "registro_ban" return false end
    local hitIP,    _ = C.verificarBan("198.51.100.1", nil, nil, nil, nil)
    local hitEmail, _ = C.verificarBan("0.0.0.0", acc.email_lookup, nil, nil, nil)
    local hitId,    _ = C.verificarBan("0.0.0.0", nil, nil, fakeIds, nil)
    local missIP,   _ = C.verificarBan("198.51.100.2", nil, nil, nil, nil)
    pcall(function()
      MySQL.query.await(
        "DELETE FROM login_ban_vectors WHERE account_id = ? AND reason = ?",
        { acc.account_id, "teste_ban_roundtrip" })
    end)
    if not hitIP or not hitEmail or not hitId or missIP then checkpoint = "roundtrip_ban" return false end

    return true
  end)
  cleanup()
  if not ran then print("[vhub_login] persistencia falhou: " .. tostring(passed))
  elseif passed ~= true then print("[vhub_login] persistencia falhou em: " .. checkpoint) end
  return ran and passed == true
end

-- Executa 70 cadastros e autenticações sintéticos; sempre remove as linhas criadas.
function C.testarCargaCadastro(total)
  if GetConvar("vhub_test_mode", "0") ~= "1" or not _pepper then return false end
  total = tonumber(total)
  if total ~= 70 then return false end

  local started = GetGameTimer()
  local token = ("%d_%d"):format(started, math.random(100000, 999999))
  local prefix = "vhs" .. token:sub(-8) .. "_"
  local created, latencies = 0, {}

  local function cleanup()
    pcall(function()
      MySQL.update.await(
        "DELETE FROM login_accounts WHERE user_id BETWEEN ? AND ? AND username LIKE CONCAT(?, '%')",
        { 4294960001, 4294960070, prefix })
    end)
  end

  local ran, result = pcall(function()
    local done = promise.new()
    local completed, failed = 0, false
    for i = 1, total do
      Citizen.CreateThread(function()
        local ok, completedRun = pcall(function()
          local user_id = 4294960000 + i
          local username = prefix .. i
          local email = username .. "@mirage.invalid"
          local phone = ("551199%07d"):format(i)
          local password = "Stress@" .. i .. "Aa9"
          local collision = MySQL.scalar.await(
            "SELECT 1 FROM login_accounts WHERE user_id = ? OR username = ? LIMIT 1",
            { user_id, username })
          if collision then return false end
          local clock = GetGameTimer()
          local registered = C.registrar(user_id, {
            username = username,
            password = password,
            password_confirmation = password,
            email = email,
            whatsapp = phone,
            terms_accepted = true,
            age_18 = true,
            terms_version = CFG.terms_version,
          }, "198.18.0." .. i)
          if not registered or not C.autenticar(user_id, username, password, "198.18.0." .. i) then
            return false
          end
          created = created + 1
          latencies[#latencies + 1] = GetGameTimer() - clock
          return true
        end)
        if not ok or completedRun ~= true then failed = true end
        completed = completed + 1
        if completed == total then done:resolve(true) end
      end)
    end
    Citizen.Await(done)
    if failed or created ~= total then return false end

    table.sort(latencies)
    local function percentile(value)
      local index = math.max(1, math.ceil(#latencies * value))
      return latencies[index]
    end
    return {
      total = total,
      created = created,
      p50_ms = percentile(0.50),
      p95_ms = percentile(0.95),
      p99_ms = percentile(0.99),
      max_ms = latencies[#latencies],
      duration_ms = GetGameTimer() - started,
    }
  end)
  cleanup()
  if not ran or not result or created ~= total then return false end
  result.ok = true
  return result
end


return C
