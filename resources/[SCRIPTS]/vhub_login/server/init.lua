-- server/init.lua — lifecycle + GATE de entrada + net handlers.
-- O core auto-spawna; o único ponto de interceptação é o vhub_hss:
-- chooseSpawn (a junta do hold/999). Aqui o gate decide: não-autenticado → abre
-- login (ped já em hold); autenticado → seleciona/cria personagem antes do selector.

VHubLogin = VHubLogin or {}

local CFG = VHubLogin.Config
local F   = VHubLogin.Fluxo
local C   = VHubLogin.Contas
local E   = VHubLogin.E

local _ready = false
local _inflight = {}
local _booting = false
local _grace = {}
local _stage = { schema = false, migracao = false, seguranca = false }

local function log(level, message, data)
  pcall(function() exports.vhub:log(level, "login", message, data or {}) end)
end


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- Executa os estágios pendentes da cadeia de prontidão; falha isolada por pcall.
local function prepararGate(res)
  if not _stage.schema then
    local schema = LoadResourceFile(res, "sql/login_accounts.sql")
    if not schema or #schema == 0 then return false, "schema_ausente" end

    -- statement a statement (padrão vhub_hss): sem dependência de multi-statement
    local ok, err = pcall(function()
      for statement in schema:gmatch("([^;]+);") do
        if statement:match("%S") then MySQL.query.await(statement, {}) end
      end
    end)
    if not ok then return false, "schema_falhou", err end
    _stage.schema = true
  end

  if not _stage.migracao then
    local ok, migrated, migrationErr = pcall(C.migrarSchema)
    if not ok then return false, "migracao_lancou", migrated end
    if not migrated then return false, "migracao_recusada", migrationErr end
    _stage.migracao = true
  end

  if not _stage.seguranca then
    local ok, secure, securityErr = pcall(C.prepararSeguranca)
    if not ok then return false, "seguranca_lancou", secure end
    if not secure then return false, "seguranca_recusada", securityErr end
    _stage.seguranca = true
  end

  -- CORE pronto por último: pós-wipe ele recria o schema inteiro e pode demorar
  local coreOK = pcall(function() return exports.vhub:getCharacterIds(0) end)
  if not coreOK then return false, "core_indisponivel" end
  return true
end

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  if _booting then return end
  _booting = true

  -- Retry persistente: um gate fail-closed que desiste vira lockout permanente
  -- do servidor inteiro. Backoff 200ms→5s (L-18); log de erro a cada 30s.
  Citizen.CreateThread(function()
    local delay, lastLog = 200, -60000
    while not _ready do
      local ok, motivo, detalhe = prepararGate(res)
      if ok then
        _ready = true
        log("info", "Gate de entrada pronto.", { enabled = CFG.enabled })
        break
      end
      local now = GetGameTimer()
      if now - lastLog >= 30000 then
        lastLog = now
        log("error", "Gate de entrada ainda não pronto; nova tentativa em curso.", {
          motivo = motivo, detalhe = tostring(detalhe or ""),
        })
      end
      Citizen.Wait(delay)
      delay = math.min(delay * 2, 5000)
    end
    _booting = false
  end)
end)


-- ============================================================
-- GATE — intercepta o pedido de spawn do vhub_hss
-- ============================================================

-- Aguarda a prontidão do boot dentro da janela de graça (poll 500ms, O(1)/player).
local function aguardarProntidao(timeout_ms)
  local deadline = GetGameTimer() + timeout_ms
  while not _ready and GetGameTimer() < deadline do
    Citizen.Wait(500)
  end
  return _ready
end

AddEventHandler(VHubHSS.E.SPAWN_CHOOSE, function(src)
  if not CFG.enabled then return end                 -- gate desligado → inerte (selector abre)
  Citizen.CreateThread(function()
    if not _ready then
      -- Gate LIGADO com boot incompleto: janela de graça FAIL-CLOSED. O ped está
      -- invisível/congelado no bucket 999 (HSS) — esperar é seguro. Expirou sem
      -- prontidão → recusa; um gate de credencial NUNCA deixa entrar sem login.
      if _grace[src] then return end                 -- replay durante a janela: 1 poll por src
      _grace[src] = true
      local pronto = aguardarProntidao(30000)
      _grace[src] = nil
      if not pronto then
        DropPlayer(tostring(src), "Servidor inicializando — reconecte em instantes.")
        return
      end
      if GetPlayerName(src) == nil then return end   -- caiu durante a espera
    end

    local session = F.get(src)
    if session and session.step ~= "login" then
      if session.step == "ready" then
        local released, spawned = pcall(function() return exports.vhub_hss:spawnAt(src, nil) end)
        if not released or spawned ~= true then
          DropPlayer(tostring(src), "Falha ao restaurar o personagem.")
        end
      elseif session.step == "spawning" then
        local selector = F.prepararSeletor(src)
        if not selector then
          DropPlayer(tostring(src), "Falha ao preparar a selecao de destino.")
          return
        end
        TriggerClientEvent(E.PROCEED_SPAWN, src, selector)
      elseif session.step == "charselect" then
        if not F.isolarEntrada(src) then
          DropPlayer(tostring(src), "Falha ao isolar a sessão de personagens.")
          return
        end
        TriggerClientEvent(E.CREATION_RETURN, src, F.personagens(src) or {})
      end
      return -- creating mantém SIMS + hold; somente spawning abre o selector
    end
    if F.iniciar(src) then
      F.armarDeadline(src)                       -- sessão nova SEMPRE nasce com deadline
      TriggerClientEvent(E.OPEN, src)            -- abre NUI de login
      return
    end

    -- iniciar falhou: sessão pendente em "login" (replay do core — L-17) → reabre a
    -- NUI (deadline original segue armado). Sem sessão (UID indisponível) → drop
    -- FAIL-CLOSED: sem isso o selector_timeout do HSS soltaria o player sem login.
    local sessao = F.get(src)
    if sessao and sessao.step == "login" then
      TriggerClientEvent(E.OPEN, src)
      return
    end
    DropPlayer(tostring(src), "Falha ao iniciar a sessão de login — reconecte.")
  end)
end)

-- O selector (Opção A) consulta isto para ceder a abertura ao gate SÓ quando ele
-- está realmente ativo. enabled=false ou core não pronto → selector abre normal
-- (estado intermediário seguro: ninguém fica preso sem login).
-- Liga = enabled (desacoplado de _ready): o selector cede sempre que o gate está
-- ligado; se o core cair, o handler acima faz fail-closed (DropPlayer), nunca
-- deixa o selector spawnar um não-autenticado.
exports("isGateActive", function() return CFG.enabled == true end)


-- ============================================================
-- ANTI BRUTE-FORCE (por UID + ação)
-- ============================================================

local _rl = {}
local function rateOK(src, action, limit)
  local session = F.get(src)
  local actor = session and ("u:" .. tostring(session.uid)) or ("s:" .. tostring(src))
  local key = actor .. ":" .. action
  local now = GetGameTimer()
  local e = _rl[key]
  if not e or (now - e.win) > limit.window then
    local token = {}
    _rl[key] = { win = now, hits = 1, token = token }
    Citizen.SetTimeout(limit.window + 100, function()
      local current = _rl[key]
      if current and current.token == token then _rl[key] = nil end
    end)
    return true
  end
  e.hits = e.hits + 1
  return e.hits <= limit.max
end

local function safeText(value, maxLength)
  if type(value) ~= "string" or #value > maxLength then return nil end
  if value:find("[%z\1-\31\127]") then return nil end
  return value
end

local function sendError(src, err)
  TriggerClientEvent(E.AUTH_FAIL, src, tostring(err or "erro"))
end

local function runRequest(src, action, limit, work, done)
  if not rateOK(src, action, limit) then return sendError(src, "rate_limit") end
  if _inflight[src] then return sendError(src, "operacao_em_andamento") end

  local token = { action = action, session = F.get(src) }
  _inflight[src] = token
  Citizen.CreateThread(function()
    local ran, ok, err, detail, extra = pcall(work)
    if _inflight[src] ~= token or F.get(src) ~= token.session then return end
    _inflight[src] = nil
    if not ran then
      log("error", "Operação de autenticação falhou.", { action = action, src = src })
      return done(false, "erro")
    end
    done(ok, err, detail, extra)
  end)
end


-- ============================================================
-- NET HANDLERS (cliente → servidor)
-- ============================================================

RegisterNetEvent(E.TRY_LOGIN)
AddEventHandler(E.TRY_LOGIN, function(username, password)
  local src = source
  if type(username) == "table" then
    password = username.password
    username = username.username
  end
  username = safeText(username, CFG.username_max)
  password = safeText(password, CFG.password_max)

  runRequest(src, "login", CFG.rate.login, function()
    if not username or not password then return false, "credencial_invalida" end
    return F.autenticar(src, username, password)
  end, function(ok, err)
    if ok then
      TriggerClientEvent(E.AUTH_OK, src, F.personagens(src) or {})
    else
      sendError(src, err)
    end
  end)
end)

-- assinatura 0.1.x preservada como depreciação explícita; cadastro exige cliente V2.
RegisterNetEvent(E.TRY_REGISTER)
AddEventHandler(E.TRY_REGISTER, function()
  local src = source
  if not rateOK(src, "register_legacy", CFG.rate.register) then
    return sendError(src, "rate_limit")
  end
  sendError(src, "cadastro_atualizacao_necessaria")
end)

RegisterNetEvent(E.TRY_REGISTER_V2)
AddEventHandler(E.TRY_REGISTER_V2, function(payload)
  local src = source
  local data = type(payload) == "table" and payload or {}
  data = {
    username = safeText(data.username, CFG.username_max),
    password = safeText(data.password, CFG.password_max),
    password_confirmation = safeText(data.password_confirmation, CFG.password_max),
    email = safeText(data.email, CFG.email_max),
    whatsapp = safeText(data.whatsapp, 32),
    terms_accepted = data.terms_accepted == true,
    age_18 = data.age_18 == true,
    terms_version = safeText(data.terms_version, 32),
  }

  runRequest(src, "register", CFG.rate.register, function()
    return F.registrar(src, data)
  end, function(ok, err)
    if ok then
      TriggerClientEvent(E.AUTH_OK, src, F.personagens(src) or {})
    else
      sendError(src, err)
    end
  end)
end)

RegisterNetEvent(E.TRY_RECOVERY)
AddEventHandler(E.TRY_RECOVERY, function(payload)
  local src = source
  payload = type(payload) == "table" and payload or {}
  local data = {
    contact = safeText(payload.contact, CFG.email_max),
    password = safeText(payload.password, CFG.password_max),
    password_confirmation = safeText(payload.password_confirmation, CFG.password_max),
  }

  runRequest(src, "recovery", CFG.rate.recovery, function()
    return F.recuperar(src, data)
  end, function(ok, err)
    if ok then
      TriggerClientEvent(E.RECOVERY_DONE, src)
    else
      sendError(src, err)
    end
  end)
end)

RegisterNetEvent(E.PICK_CHAR)
AddEventHandler(E.PICK_CHAR, function(cid)
  local src = source
  cid = tonumber(cid)

  runRequest(src, "pick", CFG.rate.pick, function()
    if not cid or cid < 1 or cid ~= math.floor(cid) then return false, "char_invalido" end
    return F.selecionar(src, cid)
  end, function(ok, err, transition, selector)
    if ok then
      if transition == "creating" then
        TriggerClientEvent(E.CREATION_HANDOFF, src)
      else
        TriggerClientEvent(E.CHAR_OK, src, selector)
      end
    else
      if not F.isolarEntrada(src) then
        DropPlayer(tostring(src), "Falha ao isolar a sessão de personagens.")
        return
      end
      TriggerClientEvent(E.CHAR_FAIL, src, err)
    end
  end)
end)

-- Cria no CORE e entrega ao SIMS sem consumir o pending do HSS.
RegisterNetEvent(E.REQUEST_CREATE)
AddEventHandler(E.REQUEST_CREATE, function()
  local src = source
  runRequest(src, "create", CFG.rate.create, function()
    return F.criar(src)
  end, function(ok, err, transition)
    if ok and transition == "creating" then
      TriggerClientEvent(E.CREATION_HANDOFF, src)
      return
    end
    if not F.isolarEntrada(src) then
      DropPlayer(tostring(src), "Falha ao isolar a sessão de personagens.")
      return
    end
    TriggerClientEvent(E.CREATION_RETURN, src, F.personagens(src) or {}, err or "erro")
  end)
end)

local function returnFromCreation(char_id)
  Citizen.CreateThread(function()
    local src, isolated = F.concluirCriacao(char_id)
    if not src or GetPlayerName(src) == nil then return end
    if not isolated then
      DropPlayer(tostring(src), "Falha ao isolar a sessão de personagens.")
      return
    end
    TriggerClientEvent(E.CREATION_RETURN, src, F.personagens(src) or {})
  end)
end

-- O SIMS concluiu; reabre a seleção com resumos autoritativos atualizados.
AddEventHandler(E.CREATION_DONE, function(char_id)
  if GetInvokingResource() ~= "vhub_sims" then return end
  returnFromCreation(char_id)
end)

-- O SIMS cancelou; retorna ao charselect sem abrir selector nem gravar conclusão.
AddEventHandler(E.CREATION_CANCELLED, function(char_id)
  if GetInvokingResource() ~= "vhub_sims" then return end
  returnFromCreation(char_id)
end)


-- ============================================================
-- HIGIENE
-- ============================================================

AddEventHandler("playerDropped", function()
  local src = source
  F.limpar(src)
  _inflight[src] = nil
  _grace[src] = nil
end)

AddEventHandler("onResourceStop", function(resource)
  if resource ~= GetCurrentResourceName() then return end
  for src in pairs(F.sessions) do
    if GetPlayerName(src) then
      DropPlayer(tostring(src), "Gate de autenticação reiniciado. Reconecte.")
    end
  end
end)
