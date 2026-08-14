-- server/api/exports.lua — API pública (export-first, default-deny).
-- Exposta MESMO sem consumidor hoje (convenção do dono): quando outro resource
-- precisar saber o estado de login, já existe export nativo gated.

VHubLogin = VHubLogin or {}

local CFG = VHubLogin.Config
local F   = VHubLogin.Fluxo
local C   = VHubLogin.Contas

local _testSeq = 0
local _testResults = {}
local _testRunning = false

-- invocador confiável (vazio = só consumo interno). NÃO popular sem ownership.
local function invokerOK()
  local who = GetInvokingResource()
  if not who or who == GetCurrentResourceName() then return true end
  return (CFG.login_trusted or {})[who] == true
end

-- jogador concluiu o login nesta sessão?
exports("isAuthenticated", function(src)
  if not invokerOK() then return false end
  return F.isAuth(tonumber(src) or -1)
end)

-- dados NÃO sensíveis da conta (nunca hash/salt)
exports("getAccount", function(src)
  if not invokerOK() then return nil end
  local s = F.get(tonumber(src) or -1)
  if not s or not s.account then return nil end
  return {
    account_id = s.account.account_id,
    username   = s.account.username,
    user_id    = s.account.user_id,
  }
end)

-- etapa atual do gate: "login" | "charselect" | "creating" | "spawning" | "ready" | nil
exports("getSessionStep", function(src)
  if not invokerOK() then return nil end
  local s = F.get(tonumber(src) or -1)
  return s and s.step or nil
end)

exports("completeEntry", function(src)
  if GetInvokingResource() ~= "vhub_spawselector" or not invokerOK() then return false end
  return F.concluirEntrada(tonumber(src) or -1)
end)

exports("returnToCharacters", function(src)
  if GetInvokingResource() ~= "vhub_spawselector" or not invokerOK() then return nil end
  return F.voltarPersonagens(tonumber(src) or -1)
end)

-- registra ban multi-vetor (IP+email+whatsapp) via vhub_admin ou console server.
-- src pode ser nil quando a conta nunca existiu; banned_by deve ser username do admin.
exports("banPlayer", function(target_src, admin_src, reason, expires_at)
  if not invokerOK() then return false, "nao_autorizado" end
  local who = GetInvokingResource()
  if who ~= "vhub_admin" and who ~= GetCurrentResourceName() then
    return false, "nao_autorizado"
  end

  target_src = tonumber(target_src)
  if not target_src then return false, "jogador_invalido" end

  local admin_username = "console"
  if tonumber(admin_src) then
    local acc = F.get(tonumber(admin_src))
    if acc and acc.account then admin_username = acc.account.username or "admin" end
  end

  if type(reason) ~= "string" or reason == "" then return false, "motivo_invalido" end

  local session = F.get(target_src)
  local account_id    = session and session.account and session.account.account_id or nil
  local email_lookup  = session and session.account and session.account.email_lookup or nil
  local whatsapp_lookup = session and session.account and session.account.whatsapp_lookup or nil
  local ip = GetPlayerEndpoint(tostring(target_src))

  -- Coleta identifiers FiveM nativos do player alvo ANTES do drop (player ainda conectado).
  -- Reutiliza o que já foi coletado em F.iniciar; extrai de novo como fallback.
  local ids     = session and session.identifiers or nil
  local hwToken = session and session.hw_token or nil
  if not ids then
    ids, hwToken = C.extrairIdentifiers(target_src)
  end

  local ok, result = C.registrarBan(
    account_id, ip, email_lookup, whatsapp_lookup,
    admin_username, reason, expires_at, ids, hwToken)
  if not ok then return false, result end

  DropPlayer(tostring(target_src), "Banido: " .. reason)
  return true, result
end)

-- Inicia round-trip de persistência apenas para o testrunner em modo de teste.
exports("runPersistenceTest", function()
  if GetConvar("vhub_test_mode", "0") ~= "1"
    or GetInvokingResource() ~= "vhub_testrunner"
    or _testRunning then
    return nil
  end

  _testRunning = true
  _testSeq = _testSeq + 1
  local token = ("login:%d:%d"):format(GetGameTimer(), _testSeq)
  _testResults[token] = { done = false }
  Citizen.CreateThread(function()
    local ok, result = pcall(C.testarPersistencia)
    local completed = { done = true, result = ok and result == true }
    _testResults[token] = completed
    _testRunning = false
    Citizen.SetTimeout(60000, function()
      if _testResults[token] == completed then _testResults[token] = nil end
    end)
  end)
  return token
end)

-- Consulta e consome o resultado do round-trip controlado.
exports("getPersistenceTest", function(token)
  if GetConvar("vhub_test_mode", "0") ~= "1"
    or GetInvokingResource() ~= "vhub_testrunner"
    or type(token) ~= "string" then
    return nil
  end
  local result = _testResults[token]
  if result and result.done then _testResults[token] = nil end
  return result
end)
