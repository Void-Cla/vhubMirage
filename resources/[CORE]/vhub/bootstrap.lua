local RECURSO = GetCurrentResourceName()

local Boot = {
  pronto = false,
  falha = nil,
  inicio_ms = GetGameTimer(),
  metricas = {
    batches = 0,
    batch_falhas = 0,
    batch_reenfileirados = 0,
    ultima_latencia_db_ms = 0
  }
}

local vHubRuntime = nil
local DriverRuntime = nil

local function codificar(meta)
  return meta and (" "..json.encode(meta)) or ""
end

local function logar(nivel, mensagem, meta)
  -- Usa vHub.Logger quando disponível, senão faz fallback para print (bootstrap)
  if rawget(_G, "vHub") and vHub and vHub.Logger then
    if nivel == "ERROR" then vHub.Logger:error("bootstrap", mensagem, meta)
    elseif nivel == "WARN" then vHub.Logger:warn("bootstrap", mensagem, meta)
    else vHub.Logger:info("bootstrap", mensagem, meta) end
  else
    print(("[vhub][%s] %s%s"):format(nivel, mensagem, codificar(meta)))
  end
end

local function falhar(codigo, mensagem, meta)
  Boot.pronto = false
  Boot.falha = codigo
  logar("FATAL", mensagem, meta)
  error(("[vhub] %s"):format(mensagem), 0)
end

local function inteiro(nome, padrao, minimo, maximo)
  local valor = GetConvarInt(nome, padrao)
  if valor < minimo then return minimo end
  if valor > maximo then return maximo end
  return valor
end

local function decimal(nome, padrao, minimo, maximo)
  local valor = GetConvarFloat(nome, padrao)
  if valor < minimo then return minimo end
  if valor > maximo then return maximo end
  return valor
end

local function booleano(nome, padrao)
  return GetConvarInt(nome, padrao and 1 or 0) == 1
end

local function criar_config()
  return {
    db = {
      driver = "oxmysql",
      resource = "oxmysql"
    },
    log_level = inteiro("vhub_log_level", 1, 0, 3),
    max_payload = inteiro("vhub_max_payload", 8192, 512, 65536),
    save_interval = inteiro("vhub_save_interval", 60, 15, 3600),
    fuel_rate = decimal("vhub_fuel_rate", 0.005, 0.0, 1.0),
    whitelist_enabled = booleano("vhub_whitelist", false),
    modules = {},
    lang = {
      not_whitelisted = "Sem whitelist. ID: "
    },
    webhooks = {
      join = GetConvar("vhub_webhook_join", ""),
      leave = GetConvar("vhub_webhook_leave", ""),
      ban = GetConvar("vhub_webhook_ban", ""),
      security = GetConvar("vhub_webhook_security", "")
    }
  }
end

local function blob_para_string(blob)
  if type(blob) ~= "table" then return blob end
  local bytes = {}
  for indice, byte in ipairs(blob) do bytes[indice] = string.char(byte) end
  return table.concat(bytes)
end

local function normalizar_linhas(resultado)
  if type(resultado) ~= "table" then return resultado end
  for _, linha in pairs(resultado) do
    if type(linha) == "table" then
      for chave, valor in pairs(linha) do
        if type(valor) == "table" then linha[chave] = blob_para_string(valor) end
      end
    end
  end
  return resultado
end

local function criar_driver()
  local Driver = {
    name = "oxmysql",
    api = nil,
    queries = {},
    metricas = {
      queries = 0,
      transacoes = 0,
      falhas = 0,
      ultima_latencia_ms = 0
    }
  }

  function Driver:_executar(metodo, consulta, parametros)
    local inicio = GetGameTimer()
    local promessa = promise.new()
    local resolvido = false

    local function resolver(resultado, erro)
      if resolvido then return end
      resolvido = true
      promessa:resolve({resultado = resultado, erro = erro})
    end

    SetTimeout(15000, function()
      resolver(nil, "timeout_db")
    end)

    local ok_envio, erro_envio = pcall(function()
      if metodo == "query" then
        self.api:query(consulta, parametros or {}, resolver)
      elseif metodo == "scalar" then
        self.api:scalar(consulta, parametros or {}, resolver)
      elseif metodo == "update" then
        self.api:update(consulta, parametros or {}, resolver)
      elseif metodo == "transaction" then
        self.api:transaction(consulta, parametros or {}, resolver)
      else
        resolver(nil, "metodo_db_invalido")
      end
    end)

    if not ok_envio then
      self.metricas.falhas = self.metricas.falhas + 1
      return false, erro_envio, GetGameTimer() - inicio
    end

    local envelope = Citizen.Await(promessa)
    local latencia = GetGameTimer() - inicio
    self.metricas.ultima_latencia_ms = latencia
    Boot.metricas.ultima_latencia_db_ms = latencia

    if envelope.erro then
      self.metricas.falhas = self.metricas.falhas + 1
      return false, envelope.erro, latencia
    end

    return true, envelope.resultado, latencia
  end

  function Driver:_consulta(nome)
    local consulta = self.queries[nome]
    if type(consulta) ~= "string" or consulta == "" then
      self.metricas.falhas = self.metricas.falhas + 1
      logar("ERROR", "consulta SQL nao preparada", {nome = tostring(nome)})
      return nil
    end
    return consulta
  end

  function Driver:init(cfg)
    local estado = GetResourceState("oxmysql")
    local conexao = GetConvar("mysql_connection_string", "")

    if estado ~= "started" then
      logar("ERROR", "oxmysql nao iniciado", {estado = estado})
      return false
    end

    if conexao == "" then
      logar("ERROR", "mysql_connection_string ausente")
      return false
    end

    if not conexao:lower():find("multiplestatements=true", 1, true) then
      logar("ERROR", "mysql_connection_string sem multipleStatements=true")
      return false
    end

    self.api = exports.oxmysql
    if type(self.api) ~= "table" then
      logar("ERROR", "exports oxmysql indisponiveis")
      return false
    end

    local ok_ping, resultado = self:_executar("scalar", "SELECT 1", {})
    if not ok_ping or tonumber(resultado) ~= 1 then
      logar("ERROR", "ping SQL falhou", {resultado = resultado})
      return false
    end

    return true
  end

  function Driver:prepare(nome, consulta)
    if type(nome) ~= "string" or nome == "" then error("nome de prepare invalido") end
    if type(consulta) ~= "string" or consulta == "" then error("SQL de prepare invalido") end
    self.queries[nome] = consulta
  end

  function Driver:query(nome, parametros, modo)
    local consulta = self:_consulta(nome)
    if not consulta then return modo == "scalar" and nil or {} end

    local metodo = modo == "execute" and "update" or modo == "scalar" and "scalar" or "query"
    local ok, resultado = self:_executar(metodo, consulta, parametros or {})
    self.metricas.queries = self.metricas.queries + 1

    if not ok then
      logar("ERROR", "query SQL falhou", {nome = nome, modo = modo or "query"})
      return metodo == "update" and 0 or metodo == "scalar" and nil or {}
    end

    if metodo == "query" and consulta:find(";.-SELECT.+LAST_INSERT_ID%(%)") and type(resultado) == "table" and resultado[1] then
      return {{id = resultado[1].insertId}}, resultado[1].affectedRows
    end

    if metodo == "query" then return normalizar_linhas(resultado or {}) end
    return resultado
  end

  function Driver:batch(operacoes, total)
    if tonumber(total or 0) <= 0 then return true end

    local transacao = {}
    for indice = 1, total do
      local operacao = operacoes[indice]
      local nome = type(operacao) == "table" and operacao[1] or nil
      local parametros = type(operacao) == "table" and operacao[2] or nil
      local consulta = self:_consulta(nome)
      if not consulta then return false end
      transacao[#transacao + 1] = {query = consulta, parameters = parametros or {}}
    end

    local ok, resultado, latencia = self:_executar("transaction", transacao, {})
    self.metricas.transacoes = self.metricas.transacoes + 1
    Boot.metricas.batches = Boot.metricas.batches + 1

    if not ok or resultado ~= true then
      self.metricas.falhas = self.metricas.falhas + 1
      Boot.metricas.batch_falhas = Boot.metricas.batch_falhas + 1
      logar("ERROR", "batch SQL falhou", {total = total, latencia_ms = latencia})
      return false
    end

    return true
  end

  return Driver
end

local function validar_driver(driver)
  for _, metodo in ipairs({"init", "prepare", "query", "batch"}) do
    if type(driver[metodo]) ~= "function" then
      falhar("driver_invalido", "driver DB sem contrato obrigatorio", {metodo = metodo})
    end
  end
end

local function carregar_base()
  local fonte = LoadResourceFile(RECURSO, "base.lua")
  if type(fonte) ~= "string" or fonte == "" then
    falhar("base_ausente", "base.lua nao encontrado no resource vhub")
  end

  local chunk, erro = load(fonte, ("@%s/base.lua"):format(RECURSO), "t", _ENV)
  if not chunk then falhar("base_invalida", "base.lua nao compila", {erro = erro}) end

  local ok, modulo = pcall(chunk)
  if not ok then falhar("base_falhou", "base.lua falhou ao carregar", {erro = modulo}) end
  if type(modulo) ~= "table" then falhar("base_sem_retorno", "base.lua precisa retornar tabela vHub") end

  return modulo
end

local function validar_base(vhub)
  local obrigatorios = {
    {"init", "function"},
    {"State", "table"},
    {"Kernel", "table"},
    {"Auth", "table"},
    {"Vehicle", "table"},
    {"Security", "table"},
    {"Notify", "table"}
  }

  for _, item in ipairs(obrigatorios) do
    if type(vhub[item[1]]) ~= item[2] then
      falhar("contrato_base_invalido", "base.lua sem simbolo obrigatorio", {simbolo = item[1]})
    end
  end
end

local function aplicar_schema(driver)
  local schema = LoadResourceFile(RECURSO, "sql/schema.sql")
  if type(schema) ~= "string" or schema == "" then
    falhar("schema_ausente", "sql/schema.sql nao encontrado")
  end

  local ok, resultado = driver:_executar("query", schema, {})
  if not ok then falhar("schema_falhou", "schema inicial falhou", {resultado = resultado}) end
end

local function snapshot()
  local state = vHubRuntime and vHubRuntime.State or nil
  local auth = vHubRuntime and vHubRuntime.Auth or nil
  local vehicle = vHubRuntime and vHubRuntime.Vehicle or nil
  local sessoes = 0
  local veiculos = 0

  if auth and auth._sessions then
    for _ in pairs(auth._sessions) do sessoes = sessoes + 1 end
  end

  if vehicle and vehicle._veh then
    for _ in pairs(vehicle._veh) do veiculos = veiculos + 1 end
  end

  return {
    recurso = RECURSO,
    pronto = Boot.pronto,
    falha = Boot.falha,
    uptime_ms = GetGameTimer() - Boot.inicio_ms,
    db_ready = state and state._ready == true or false,
    batch_pendente = state and state._batchN or 0,
    sessoes = sessoes,
    veiculos = veiculos,
    metricas = Boot.metricas,
    driver = DriverRuntime and DriverRuntime.metricas or nil
  }
end

exports("API", function()
  return vHubRuntime
end)

exports("Status", function()
  return snapshot()
end)

exports("Health", function()
  return snapshot()
end)

RegisterCommand("vhub_status", function(source)
  if source ~= 0 then return end
  logar("INFO", "status", snapshot())
end, true)

AddEventHandler("onResourceStop", function(resource)
    if resource == "oxmysql" and Boot.pronto then
      Boot.pronto = false
      Boot.falha = "oxmysql_parado"
      logar("ERROR", "oxmysql parou durante runtime")
    end

  if resource == RECURSO and vHubRuntime and vHubRuntime.State then
    local State = vHubRuntime.State
    if State._batchN > 0 and State._ready then
      local operacoes, total = State._batch, State._batchN
      State._batch, State._batchN = {}, 0
      local ok, resultado = pcall(State._driver.batch, State._driver, operacoes, total)
      if not ok or resultado == false then
        logar("ERROR", "flush final falhou", {total = total, erro = resultado})
      else
        logar("INFO", "flush final concluido", {total = total})
      end
    end
  end
end)

local function iniciar()
  local config = criar_config()
  local driver = criar_driver()
  validar_driver(driver)

  vHubRuntime = carregar_base()
  DriverRuntime = driver

  validar_base(vHubRuntime)
  vHubRuntime.log = logar
  vHubRuntime:init(config, driver)

  if not vHubRuntime.State._ready then
    falhar("db_indisponivel", "base iniciou sem State pronto")
  end

  aplicar_schema(driver)

  Boot.pronto = true
  Boot.falha = nil
  logar("INFO", "vhub iniciado", snapshot())
end

iniciar()
