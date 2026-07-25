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

-- etapa atual do gate: "login" | "charselect" | "creating" | "spawning" | nil
exports("getSessionStep", function(src)
  if not invokerOK() then return nil end
  local s = F.get(tonumber(src) or -1)
  return s and s.step or nil
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
