-- server/api/exports.lua — API pública (export-first, default-deny).
-- Exposta MESMO sem consumidor hoje (convenção do dono): quando outro resource
-- precisar saber o estado de login, já existe export nativo gated.

VHubLogin = VHubLogin or {}

local CFG = VHubLogin.Config
local F   = VHubLogin.Fluxo

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

-- etapa atual do gate: "login" | "charselect" | "spawning" | nil
exports("getSessionStep", function(src)
  if not invokerOK() then return nil end
  local s = F.get(tonumber(src) or -1)
  return s and s.step or nil
end)
