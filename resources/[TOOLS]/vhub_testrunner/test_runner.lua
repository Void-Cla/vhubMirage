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

-- Regressão A1 (IT.6 / Void-Zero): round-trip de vh_vehicle_data (write → flush → read).
-- Trava o bug @dkey→@key (decisão #20). Se as prepared vh/set_vd|get_vd regredirem para
-- @dkey, o write falha silencioso e o read volta nil → este teste fica vermelho na hora.
function tests.test_vdata_roundtrip()
  if not (vHub.State and vHub.State._ready) then
    safePrint("State._ready=false — pulando test_vdata_roundtrip"); return nil
  end
  local done = promise.new()
  Citizen.CreateThread(function()
    local plate = "TRVD01"
    -- ancora a FK (vh_vehicle_data → vh_vehicles)
    Citizen.Await(vHub.State:exec("vh/veh_create", { plate = plate, key_uid = nil }))
    local marcador = { fuel = 42.5, odometer = 123.4, probe = GetGameTimer() }
    vHub.setVData(plate, "state", marcador)   -- enfileira + invalida VRAM
    vHub.State:_flush()
    Citizen.Wait(800)                          -- janela do batch
    local lido = vHub.getVData(plate, "state") -- VRAM invalidada → vem do banco
    done:resolve(type(lido) == "table"
      and lido.probe == marcador.probe
      and math.abs((lido.fuel or 0) - 42.5) < 0.001)
  end)
  return Citizen.Await(done)
end

-- Regressão blindagem b64 (decisão A2 2026-06-11): _pack grava 'b64:'+base64 e
-- _unpack decodifica — o msgpack binário era MANGLED na fronteira Lua→JS do
-- oxmysql (bytes >= 0x80 viravam pares UTF-8; perda total na leitura). Cobre:
-- payload binário completo 0x00–0xFF, valor string que colide com o prefixo
-- 'b64:' e segundo ciclo write→flush→read (re-serialização estável).
function tests.test_blob_armor_roundtrip()
  if not (vHub.State and vHub.State._ready) then
    safePrint("State._ready=false — pulando test_blob_armor_roundtrip"); return nil
  end
  local done = promise.new()
  Citizen.CreateThread(function()
    local plate = "TRVD02"
    -- ancora a FK (vh_vehicle_data → vh_vehicles)
    Citizen.Await(vHub.State:exec("vh/veh_create", { plate = plate, key_uid = nil }))

    local bytes = {}
    for b = 0, 255 do bytes[#bytes + 1] = string.char(b) end
    local payload = {
      raw     = table.concat(bytes),     -- binário completo (o mangle era fatal aqui)
      colisao = "b64:texto_legitimo",    -- colisão de prefixo DENTRO do valor
      fuel    = 73.25,
    }

    vHub.setVData(plate, "state", payload)   -- enfileira + invalida VRAM
    vHub.State:_flush()
    Citizen.Wait(800)
    local lido = vHub.getVData(plate, "state")
    local ok1 = type(lido) == "table"
      and lido.raw == payload.raw
      and lido.colisao == "b64:texto_legitimo"
      and math.abs((lido.fuel or 0) - 73.25) < 0.001

    -- segundo ciclo write→flush→read: formato estável, sem dupla blindagem
    vHub.setVData(plate, "state", payload)
    vHub.State:_flush()
    Citizen.Wait(800)
    local lido2 = vHub.getVData(plate, "state")
    local ok2 = type(lido2) == "table" and lido2.raw == payload.raw

    done:resolve(ok1 == true and ok2 == true)
  end)
  return Citizen.Await(done)
end

-- Regressão PRONTUÁRIO (sprint que supera #21): round-trip de vhub_vehicle_state
-- via escritor único do conce. Cobre: normalização de placa suja (" trvs01 " →
-- TRVS01, anti ghost-row #23), merge de patch parcial (campo ausente preservado)
-- e fail-closed p/ placa sem registro de negócio.
function tests.test_vstate_roundtrip()
  local done = promise.new()
  Citizen.CreateThread(function()
    local plate = 'TRVS01'
    pcall(function() exports.vhub_conce:deleteVehicle(plate) end)   -- limpa resto de run anterior
    local created = false
    pcall(function()
      created = exports.vhub_conce:createVehicle({
        plate = plate, model = 'sultan', vtype = 'car', category = 'test',
        char_id = nil, status = 'out',
      }) == true
    end)
    if not created then
      safePrint("conce indisponível — pulando test_vstate_roundtrip"); done:resolve(nil)
      return
    end

    -- placa suja DEVE normalizar p/ a mesma linha
    local ok1 = exports.vhub_conce:saveVehicleState(' trvs01 ', { fuel = 47.5 }, 'pump')
    -- patch parcial: engine muda, fuel do write anterior PRESERVADO
    local ok2 = exports.vhub_conce:saveVehicleState(plate, { engine_health = 612.0 }, 'store')
    local st  = exports.vhub_conce:getVehicleState(plate)
    local merged = type(st) == 'table'
      and math.abs((st.fuel or 0) - 47.5) < 0.01
      and math.abs((st.engine_health or 0) - 612.0) < 0.01
    -- fail-closed: placa inexistente nunca escreve
    local ok3 = exports.vhub_conce:saveVehicleState('ZZNOPE99', { fuel = 1.0 }, 'pump')

    pcall(function() exports.vhub_conce:deleteVehicle(plate) end)
    done:resolve(ok1 == true and ok2 == true and merged == true and ok3 == false)
  end)
  return Citizen.Await(done)
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
