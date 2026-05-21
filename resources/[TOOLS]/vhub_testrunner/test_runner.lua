-- test_runner.lua — Resource de testes automáticos para vHub (server-side)
-- Responsabilidade: executar smoke-tests automatizados em ambiente de teste FXServer.

-- Notas: executar apenas em ambiente de teste. Os testes podem realizar operações DB.

local function safePrint(...) print("[vhub_test]", ...) end

local tests = {}

-- Confirma que vHub e módulos essenciais foram carregados
function tests.check_vhub_loaded()
  return type(vHub) == 'table' and type(vHub.State) == 'table' and type(vHub.Auth) == 'table'
end

-- Verifica se vHub._next_user_id foi seedado (mitigação LAST_INSERT_ID)
function tests.check_db_seed()
  return vHub._next_user_id ~= nil
end

-- Testa reenqueue do batch quando driver.batch retorna false
function tests.test_flush_requeue()
  local State = vHub.State
  if not State then return false end
  local driver = State._driver
  if not driver then return false end
  if not State._ready then
    safePrint("State._ready=false — pulando test_flush_requeue")
    return nil
  end
  local orig_batch = driver.batch
  driver.batch = function(self, ops, total) return false end
  State:_queue({"vh/veh_set_key", {plate="TR_TEST", key_uid=999}})
  State:_flush()
  Citizen.Wait(600)
  local requeued = (State._batch and #State._batch > 0)
  driver.batch = orig_batch
  return requeued
end

-- Simula criação concorrente de usuários (usa GetPlayerIdentifiers mock)
function tests.test_concurrent_user_creation()
  if not vHub.State or not vHub.State._ready then
    safePrint("State._ready=false — pulando test_concurrent_user_creation")
    return nil
  end
  local origGetPlayerIdentifiers = GetPlayerIdentifiers
  GetPlayerIdentifiers = function(src) return {"license:bot:" .. tostring(src)} end
  local created_ids = {}
  local N = 12
  for i = 1, N do
    Citizen.CreateThread(function()
      local uid = vHub.Auth:_resolveUID(100000 + i)
      table.insert(created_ids, uid)
    end)
  end
  Citizen.Wait(2500)
  local uniq = {}
  local ok = true
  for _, id in ipairs(created_ids) do
    if not id or uniq[id] then ok = false; break end
    uniq[id] = true
  end
  GetPlayerIdentifiers = origGetPlayerIdentifiers
  return ok
end

-- Testa proteção de exports via GetInvokingResource
function tests.test_exports_protection()
  if not exports or not exports.vhub then
    safePrint("exports.vhub indisponível — certifique-se que vhub está iniciado")
    return nil
  end
  local origGetInvokingResource = GetInvokingResource
  -- forçar recurso não confiável
  GetInvokingResource = function() return "untrusted_resource" end
  local ok_blocked = pcall(function() local r = exports.vhub.grantPerm(999, "test"); return r end)
  -- agora como recurso local
  GetInvokingResource = function() return GetCurrentResourceName() end
  local ok_allowed = pcall(function() return exports.vhub.grantPerm(999, "test") end)
  -- cleanup: revogar perm se aplicada
  vHub.Kernel:revokePerm(999, "test")
  GetInvokingResource = origGetInvokingResource
  return (ok_blocked and ok_allowed)
end

local function run_all()
  if not tests.check_vhub_loaded() then
    safePrint("vHub não carregado — garanta que vhub esteja iniciado antes de executar os testes")
    return
  end
  safePrint("Iniciando testes automatizados...")
  for name, fn in pairs(tests) do
    local ok, res = pcall(fn)
    safePrint(('%s -> ok=%s, result=%s'):format(name, tostring(ok), tostring(res)))
  end
  safePrint("Testes completados. Revise as saídas acima.")
end

RegisterCommand('vhub_run_tests', function(source, args, raw)
  if source ~= 0 then safePrint('execute a partir do console do servidor (source 0)') return end
  run_all()
end, false)
