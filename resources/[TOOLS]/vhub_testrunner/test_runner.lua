-- test_runner.lua — Resource de testes automáticos para vHub (server-side)
-- Responsabilidade: executar smoke-tests automatizados em ambiente de teste FXServer.

-- Notas: executar apenas em ambiente de teste. Os testes podem realizar operações DB.

local function safePrint(...) print("[vhub_test]", ...) end

local tests = {}
local vHub = nil

local function resolve_vhub()
  if vHub then return vHub end
  local ok, value = pcall(function() return exports.vhub:getVHub() end)
  if ok and type(value) == 'table' then vHub = value end
  return vHub
end

-- Confirma que vHub e módulos essenciais foram carregados
function tests.check_vhub_loaded()
  local core = resolve_vhub()
  return type(core) == 'table' and type(core.State) == 'table' and type(core.Auth) == 'table'
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

-- Regressão CORE-001 (ADR #95): transação com write-set SQL DIFERIDO.
-- Trava o P0 em que o rollback restaurava a VRAM mas o SQL enfileirado PERSISTIA.
-- Cobre os 3 caminhos que mudaram: (1) commit drena o write-set → banco tem o valor;
-- (2) rollback descarta o write-set → banco NÃO tem o valor (nem batch pendente);
-- (3) dupla escrita da mesma chave na tx → último valor vence após o commit.
function tests.test_tx_deferred_writeset()
  if not (vHub.State and vHub.State._ready) then
    safePrint("State._ready=false — pulando test_tx_deferred_writeset"); return nil
  end
  local done = promise.new()
  Citizen.CreateThread(function()
    local plate = "TRTX01"
    Citizen.Await(vHub.State:exec("vh/veh_create", { plate = plate, key_uid = nil }))

    -- (2) ROLLBACK: escreve na tx, aborta → banco continua sem a chave.
    local txA = vHub.State:begin()
    vHub.setVData(plate, "tx_probe", { v = 111 }, txA)
    vHub.State:rollback(txA)
    vHub.State:_flush()
    Citizen.Wait(800)
    local afterRollback = vHub.getVData(plate, "tx_probe")   -- deve ser nil (nada persistiu)
    local okRollback = (afterRollback == nil)

    -- (1)+(3) COMMIT com dupla escrita da mesma chave: 222 depois 333 → vence 333.
    local txB = vHub.State:begin()
    vHub.setVData(plate, "tx_probe", { v = 222 }, txB)
    vHub.setVData(plate, "tx_probe", { v = 333 }, txB)
    local okCommit = vHub.State:commit(txB)                  -- true
    vHub.State:_flush()
    Citizen.Wait(800)
    local afterCommit = vHub.getVData(plate, "tx_probe")     -- VRAM invalidada → lê do banco
    local okCommitVal = (type(afterCommit) == "table" and afterCommit.v == 333)

    done:resolve(okRollback == true and okCommit == true and okCommitVal == true)
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

-- Regressão HSS v2: retry injetado, flush, reload/digest e outbox KVP.
function tests.test_hss_persistence_roundtrip()
  if GetConvar('vhub_test_mode', '0') ~= '1' or GetResourceState('vhub_hss') ~= 'started' then
    safePrint("HSS test mode indisponível — pulando test_hss_persistence_roundtrip")
    return nil
  end
  local players = GetPlayers()
  local src = players[1] and tonumber(players[1]) or nil
  if not src then
    safePrint("jogador online ausente — pulando test_hss_persistence_roundtrip")
    return nil
  end
  local token = exports.vhub_hss:runPersistenceTest(src)
  if type(token) ~= 'string' then return false end
  local deadline = GetGameTimer() + 60000
  while GetGameTimer() < deadline do
    Citizen.Wait(100)
    local result = exports.vhub_hss:getPersistenceTest(token)
    if result and result.done == true then return result.result == true end
  end
  return false
end

-- Regressão login 0.2: migração, cifra, hash v1→v2 e recuperação miss/hit.
function tests.test_login_persistence_roundtrip()
  if GetConvar('vhub_test_mode', '0') ~= '1'
    or GetResourceState('vhub_login') ~= 'started' then
    safePrint("login test mode indisponível — pulando test_login_persistence_roundtrip")
    return nil
  end
  local token = exports.vhub_login:runPersistenceTest()
  if type(token) ~= 'string' then return false end
  local deadline = GetGameTimer() + 30000
  while GetGameTimer() < deadline do
    Citizen.Wait(100)
    local result = exports.vhub_login:getPersistenceTest(token)
    if result and result.done == true then return result.result == true end
  end
  return false
end

-- Carga descartável: 70 cadastros/autenticações no domínio real, sem jogadores externos.
function tests.test_login_registration_load_70()
  if GetConvar('vhub_test_mode', '0') ~= '1'
    or GetResourceState('vhub_login') ~= 'started' then
    safePrint("login test mode indisponível — pulando test_login_registration_load_70")
    return nil
  end
  local token = exports.vhub_login:runRegistrationLoadTest()
  if type(token) ~= 'string' then return false end
  local deadline = GetGameTimer() + 120000
  while GetGameTimer() < deadline do
    Citizen.Wait(100)
    local result = exports.vhub_login:getRegistrationLoadTest(token)
    if result and result.done == true then
      safePrint(('login_load_70 metrics=%s'):format(json.encode(result.result)))
      return type(result.result) == 'table' and result.result.ok == true
    end
  end
  return false
end

-- Garante separação determinística sem cortar conteúdo citado ou comentários.
function tests.test_sql_script_splitter()
  local script = [=[
    -- comentário com ; ignorado
    CREATE TABLE `teste;nome` (`valor` VARCHAR(32) DEFAULT 'a;b');
    # outro comentário ; ignorado
    INSERT INTO `teste;nome` (`valor`) VALUES ("c;d");
    /* bloco ; ignorado */ SELECT 1
  ]=]
  local statements = VHubSQLScript.separar(script)
  if type(statements) ~= 'table' or #statements ~= 3 then return false end
  if not statements[1]:find("'a;b'", 1, true) then return false end
  if not statements[2]:find('"c;d"', 1, true) then return false end
  local invalid = VHubSQLScript.separar("SELECT 'sem_fim")
  return invalid == nil
end

-- Confirma que o driver rejeita duas instruções na mesma chamada.
function tests.test_multiple_statements_blocked()
  local ok = pcall(function()
    MySQL.query.await('SELECT 1; SELECT 2', {})
  end)
  return ok == false
end

-- P0 financeiro: commit real com retry, conflito e limpeza de fixture.
function tests.test_money_atomic_transfer()
  if GetConvar('vhub_test_mode', '0') ~= '1' or GetResourceState('vhub_money') ~= 'started' then
    safePrint('money test mode indisponivel — pulando test_money_atomic_transfer')
    return nil
  end
  local result = exports.vhub_money:runAtomicTransferTest()
  return type(result) == 'table' and result.ok == true
end

-- Cobertura end-to-end do engine de skill (decisão #27): cria um veículo de teste
-- com bloco p1 (nissan370z = tier A, budget 800) e valida que os exports read-only
-- do vhub_vehcontrol derivam a ficha a partir do prontuário do conce. Espelha o
-- harness puro tools/test_tier_rules.lua, mas exercita a cadeia REAL de exports
-- (catálogo → prontuário → sheetOf). Limpa o veículo no fim (placa-sentinela TRSK01).
function tests.test_vehicle_sheet_export()
  if not (vHub.State and vHub.State._ready) then
    safePrint("State._ready=false — pulando test_vehicle_sheet_export"); return nil
  end
  if not (exports and exports.vhub_vehcontrol and exports.vhub_conce) then
    safePrint("exports vhub_vehcontrol/vhub_conce indisponíveis — pulando test_vehicle_sheet_export")
    return nil
  end

  local done = promise.new()
  Citizen.CreateThread(function()
    local plate = 'TRSK01'
    pcall(function() exports.vhub_conce:deleteVehicle(plate) end)   -- limpa resto de run anterior

    local created = false
    pcall(function()
      created = exports.vhub_conce:createVehicle({
        plate = plate, model = 'nissan370z', vtype = 'car', category = 'test',
        char_id = nil, status = 'out',
      }) == true
    end)
    if not created then
      safePrint("conce indisponível p/ criar veículo — pulando test_vehicle_sheet_export")
      done:resolve(nil); return
    end

    -- corpo sob pcall: garante que o cleanup e o resolve SEMPRE rodam, mesmo que
    -- algum export lance erro Lua (senão a thread morre, deixa TRSK01 órfão e o
    -- Citizen.Await abaixo nunca retorna).
    local ok_run, result = pcall(function()
      -- ficha derivada: carro com p1 'nissan370z' nasce tier_base A, budget 800
      local sheet = exports.vhub_vehcontrol:getVehicleSheet(plate)
      local okSheet = type(sheet) == 'table'
        and sheet.tier_base == 'A' and sheet.budget == 800
        and type(sheet.alloc) == 'table' and type(sheet.ranges) == 'table'

      -- getters atômicos coerentes com a ficha
      local tier  = exports.vhub_vehcontrol:getVehicleTier(plate)
      local score = exports.vhub_vehcontrol:getVehicleScore(plate)
      local okGetters = (type(sheet) == 'table') and tier == sheet.tier and type(score) == 'number'

      -- prévia hipotética read-only: alloc tabela → ficha; não-tabela → nil (nunca persiste)
      local prev = exports.vhub_vehcontrol:getVehicleSheetPreview(plate,
        { potencia = 160, grip = 160, frenagem = 160, aero = 160, suspensao = 160 })
      local okPrev    = type(prev) == 'table' and type(prev.score) == 'number'
      local okPrevNil = exports.vhub_vehcontrol:getVehicleSheetPreview(plate, 'naoTabela') == nil

      -- fail-closed: placa sem registro (sem p1) não tem skill → nil
      local okNoP1 = exports.vhub_vehcontrol:getVehicleSheet('ZZNOPE99') == nil

      return okSheet and okGetters and okPrev and okPrevNil and okNoP1
    end)

    pcall(function() exports.vhub_conce:deleteVehicle(plate) end)   -- cleanup SEMPRE (não deixa órfão)

    done:resolve(ok_run and result == true)
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

local function run_login_suite()
  local persistence = tests.test_login_persistence_roundtrip()
  local load = tests.test_login_registration_load_70()
  safePrint(('login_persistence=%s login_load_70=%s'):format(tostring(persistence), tostring(load)))
  return persistence == true and load == true
end

RegisterCommand('vhub_run_tests', function(source, args, raw)
  if source ~= 0 then safePrint('execute a partir do console do servidor (source 0)') return end
  run_all()
end, false)

RegisterCommand('vhub_run_login_suite', function(source)
  if source ~= 0 then safePrint('execute a partir do console do servidor (source 0)') return end
  run_login_suite()
end, false)

AddEventHandler('onResourceStart', function(resource)
  if resource ~= GetCurrentResourceName()
    or GetConvar('vhub_test_mode', '0') ~= '1'
    or GetConvar('vhub_test_autorun', '0') ~= '1' then
    return
  end
  Citizen.SetTimeout(15000, function()
    local parser = tests.test_sql_script_splitter()
    safePrint(('sql_script_splitter_autorun=%s'):format(tostring(parser)))
    local blocked = tests.test_multiple_statements_blocked()
    safePrint(('multiple_statements_blocked_autorun=%s'):format(tostring(blocked)))
    local result = tests.test_money_atomic_transfer()
    safePrint(('money_atomic_transfer_autorun=%s'):format(tostring(result)))
  end)
end)
