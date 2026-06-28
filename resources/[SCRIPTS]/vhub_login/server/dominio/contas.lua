-- server/dominio/contas.lua — escritor ÚNICO da credencial de conta.
-- Usa oxmysql direto (resource externo, padrão do projeto). NUNCA persiste senha
-- em texto: hash = SHA-256(salt || senha) com salt server-side por conta. A senha
-- só existe em memória durante a comparação; nunca é logada.

VHubLogin = VHubLogin or {}

local C = {}; VHubLogin.Contas = C
local CFG = VHubLogin.Config

math.randomseed(GetGameTimer() + os.time())   -- salt não-previsível entre boots


-- ============================================================
-- HELPERS
-- ============================================================

-- salt aleatório (32 hex) — unicidade por conta (não é segredo, é anti-rainbow)
local function gen_salt()
  local t = {}
  for i = 1, 32 do t[i] = ("%x"):format(math.random(0, 15)) end
  return table.concat(t)
end

-- username: charset seguro (alfanumérico + _) e tamanho dentro do config
local function username_ok(u)
  if type(u) ~= "string" then return false end
  if #u < CFG.username_min or #u > CFG.username_max then return false end
  return u:match("^[%w_]+$") ~= nil
end

local function password_ok(p)
  return type(p) == "string" and #p >= CFG.password_min and #p <= CFG.password_max
end


-- ============================================================
-- QUERIES (read-only)
-- ============================================================

-- conta já vinculada a este uid? (UNIQUE user_id) — retorna row|nil
function C.contaDoUser(user_id)
  return MySQL.single.await(
    "SELECT account_id, user_id, username FROM login_accounts WHERE user_id = ? LIMIT 1",
    { user_id })
end

-- username já tomado por qualquer conta?
function C.usernameTomado(username)
  return MySQL.single.await(
    "SELECT 1 AS x FROM login_accounts WHERE username = ? LIMIT 1", { username }) ~= nil
end


-- ============================================================
-- MUTATIONS (validadas, server-side)
-- ============================================================

-- registra conta nova amarrada ao uid (já resolvido pelo core). retorna ok, err
function C.registrar(user_id, username, password)
  if not user_id then return false, "sem_uid" end
  if not username_ok(username) then return false, "username_invalido" end
  if not password_ok(password) then return false, "senha_invalida" end
  if C.contaDoUser(user_id) then return false, "uid_ja_tem_conta" end
  if C.usernameTomado(username) then return false, "username_em_uso" end

  local salt = gen_salt()
  local id = MySQL.insert.await(
    "INSERT INTO login_accounts (user_id, username, salt, pass_hash) " ..
    "VALUES (?, ?, ?, SHA2(CONCAT(?, ?), 256))",
    { user_id, username, salt, salt, password })
  if not id then return false, "falha_db" end
  return true
end

-- autentica. FAIL-CLOSED: a conta DEVE pertencer ao uid atual (anti-roubo de
-- progressão entre licenças). retorna account|nil, err
function C.autenticar(user_id, username, password)
  if not user_id then return nil, "sem_uid" end
  if not username_ok(username) or not password_ok(password) then
    return nil, "credencial_invalida"
  end

  local acc = MySQL.single.await(
    "SELECT account_id, user_id, username, status FROM login_accounts " ..
    "WHERE username = ? AND pass_hash = SHA2(CONCAT(salt, ?), 256) LIMIT 1",
    { username, password })
  if not acc then return nil, "credencial_invalida" end
  if tonumber(acc.status) ~= 1 then return nil, "conta_bloqueada" end

  -- a conta é deste uid? (license diferente → recusa)
  if tonumber(acc.user_id) ~= tonumber(user_id) then return nil, "conta_outra_licenca" end

  MySQL.update.await("UPDATE login_accounts SET last_login = NOW() WHERE account_id = ?",
    { acc.account_id })
  return acc
end

return C
