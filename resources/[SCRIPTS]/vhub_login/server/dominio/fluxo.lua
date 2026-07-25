-- server/dominio/fluxo.lua — máquina de estados da sessão de entrada.
-- Orquestra: login → seleção de char (verdade DELEGADA ao core) → handoff p/ o
-- selector. NÃO toca ped, bucket nem coordenada (donos: HSS/selector).

VHubLogin = VHubLogin or {}

local F = {}; VHubLogin.Fluxo = F
local CFG = VHubLogin.Config

-- [src] = { step="login"|"charselect"|"creating"|"spawning", uid, account, deadline_ms }
F.sessions = {}
F.creatingByChar = {}

local _requestSeq = 0

-- Trava por UID: reconexão não limpa e terceiros não bloqueiam username alheio.
local _uidFails = {}
local function uidBlocked(uid)
  local e = _uidFails[uid]
  return e ~= nil and e.until_ms ~= nil and GetGameTimer() < e.until_ms
end
local function uidFail(uid)
  local e = _uidFails[uid] or { n = 0 }
  e.n = e.n + 1
  if e.n >= (CFG.lockout.fails or 5) then
    e.until_ms = GetGameTimer() + (CFG.lockout.ms or 60000)
    e.n = 0
  end
  local token = {}
  e.token = token
  _uidFails[uid] = e
  Citizen.SetTimeout((CFG.lockout.ms or 60000) * 2, function()
    local current = _uidFails[uid]
    if current and current.token == token then _uidFails[uid] = nil end
  end)
end
local function uidOK(uid) _uidFails[uid] = nil end


-- ============================================================
-- PONTES PARA O CORE (sem reimplementar nada)
-- ============================================================

local function uidOf(src)
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  return ok and uid or nil
end
-- garante hold no HSS antes de selectCore (R6); retorna false se HSS indisponível ou player caiu
local function holdCreation(src)
  local ok, ret = pcall(function() return exports.vhub_hss:holdForCreation(src) end)
  return ok and ret == true
end

-- libera hold (e pending, se ainda ativo) em todos os caminhos que não entram em criação
local function releaseCreation(src)
  pcall(function() exports.vhub_hss:releaseCreationHold(src) end)
end

local function newRequestId(session, purpose)
  _requestSeq = _requestSeq + 1
  return ("login:%s:%d:%d:%d:%d"):format(
    purpose,
    tonumber(session.uid) or 0,
    os.time(),
    GetGameTimer(),
    _requestSeq
  )
end

local function selectCore(src, char_id)
  local ok, selected = pcall(function()
    return exports.vhub:selectCharacter(src, char_id)
  end)
  if not ok then return false, "core_indisponivel" end
  if selected ~= true then return false, "char_invalido" end
  return true
end

local function needsCreation(src)
  if GetResourceState("vhub_sims") ~= "started" then return nil, "dependency" end
  local ok, result = pcall(function() return exports.vhub_sims:needsCreation(src) end)
  if not ok or type(result) ~= "table" or result.ok ~= true then
    return nil, type(result) == "table" and result.err or "dependency"
  end
  return result.needed == true
end

local function beginCreation(src, request_id)
  if GetResourceState("vhub_sims") ~= "started" then return nil, "dependency" end
  local ok, result = pcall(function()
    return exports.vhub_sims:beginCreation(src, request_id)
  end)
  if not ok or type(result) ~= "table" or result.ok ~= true then
    return nil, type(result) == "table" and result.err or "dependency"
  end
  return result
end

local function enterCreation(src, session, char_id, request_id)
  local result, err = beginCreation(src, request_id)
  if not result then return false, err end

  session.step = "creating"
  session.deadline = nil
  session.creating_char_id = char_id
  session.creation_session_id = result.session_id
  F.creatingByChar[char_id] = src
  return true
end

local function mergeSummary(cards, items, kind)
  if type(items) ~= "table" then return end
  for _, item in ipairs(items) do
    local char_id = type(item) == "table" and tonumber(item.char_id) or nil
    local card = char_id and cards[char_id] or nil
    if card and kind == "identity" then
      card.firstname = type(item.firstname) == "string" and item.firstname or nil
      card.lastname = type(item.lastname) == "string" and item.lastname or nil
      card.age = tonumber(item.age)
      local name = table.concat({ card.firstname or "", card.lastname or "" }, " ")
      name = name:gsub("^%s+", ""):gsub("%s+$", "")
      if name ~= "" then card.name = name end
    elseif card and kind == "hss" then
      local customization = type(item.customization) == "table" and item.customization or nil
      card.model = customization and type(customization.model) == "string"
        and customization.model or nil
      card.appearance_revision = math.max(0, tonumber(item.revision) or 0)
    end
  end
end

-- ============================================================
-- ESTADO
-- ============================================================

-- retorna a sessão ativa do jogador, ou nil se não iniciada
function F.get(src) return F.sessions[src] end

-- autenticado nesta sessão? (passou da etapa de login)
function F.isAuth(src)
  local s = F.sessions[src]
  return s ~= nil and s.step ~= "login"
end

-- encerra e descarta a sessão do jogador (disconnect ou drop)
function F.limpar(src)
  local session = F.sessions[src]
  if session and session.creating_char_id then
    F.creatingByChar[session.creating_char_id] = nil
  end
  F.sessions[src] = nil
end

-- abre o gate (chamado pelo chooseSpawn). retorna true se abriu login agora.
function F.iniciar(src)
  if F.sessions[src] then return false end
  local uid = uidOf(src)
  if not uid then return false end
  F.sessions[src] = {
    step     = "login",
    uid      = uid,
    deadline = GetGameTimer() + (CFG.auth_deadline * 1000),
  }
  return true
end

-- DropPlayer no prazo exato; token da sessão impede efeito após replay/reconexão.
function F.armarDeadline(src)
  local session = F.sessions[src]
  if not session then return end

  local function expire()
    if F.sessions[src] ~= session or not session.deadline
      or session.step == "creating" or session.step == "spawning" then return end
    local remaining = session.deadline - GetGameTimer()
    if remaining > 0 then return Citizen.SetTimeout(remaining, expire) end
    F.sessions[src] = nil
    DropPlayer(tostring(src), "Tempo de login esgotado.")
  end
  Citizen.SetTimeout(math.max(0, session.deadline - GetGameTimer()), expire)
end


-- ============================================================
-- TRANSIÇÕES
-- ============================================================

-- login de conta existente
function F.autenticar(src, username, password)
  local s = F.sessions[src]
  if not s or s.step ~= "login" then return false, "estado_invalido" end
  if uidBlocked(s.uid) then return false, "bloqueado_temporario" end
  local acc, err = VHubLogin.Contas.autenticar(
    s.uid, username, password, GetPlayerEndpoint(src))
  if not acc then uidFail(s.uid); return false, err end
  uidOK(s.uid)
  s.account = acc
  s.step    = "charselect"
  return true
end

-- registro de conta nova → auto-login
function F.registrar(src, data)
  local s = F.sessions[src]
  if not s or s.step ~= "login" then return false, "estado_invalido" end
  local ok, err = VHubLogin.Contas.registrar(s.uid, data, GetPlayerEndpoint(src))
  if not ok then return false, err end
  local acc = VHubLogin.Contas.autenticar(
    s.uid, data.username, data.password, GetPlayerEndpoint(src))
  if not acc then return false, "falha_pos_registro" end
  s.account = acc
  s.step    = "charselect"
  return true
end

-- recuperação provisória: mesmo UID atual + contato exato; resposta externa é genérica.
function F.recuperar(src, data)
  local s = F.sessions[src]
  if not s or s.step ~= "login" then return false, "estado_invalido" end
  local ok, result = VHubLogin.Contas.recuperar(
    s.uid,
    data.contact,
    data.password,
    data.password_confirmation,
    GetPlayerEndpoint(src))
  if not ok then return false, result end
  return true -- `result` não cruza a fronteira: evita enumeração de contato.
end

-- Lista personagens do CORE e agrega somente resumos públicos dos owners.
function F.personagens(src)
  local s = F.sessions[src]
  if not s or s.step ~= "charselect" then return nil end
  local ok, result = pcall(function() return exports.vhub:getCharacterIds(src) end)
  if not ok or type(result) ~= "table" or result.ok ~= true then return nil end

  local cards, ordered = {}, {}
  for index, raw_id in ipairs(result.items or {}) do
    local char_id = tonumber(raw_id)
    if char_id then
      local card = { id = char_id, char_id = char_id, name = "Piloto " .. index }
      cards[char_id] = card
      ordered[#ordered + 1] = card
    end
  end

  local hssOK, hss = pcall(function()
    return exports.vhub_hss:getCharacterSummaries(src)
  end)
  if hssOK and type(hss) == "table" and hss.ok == true then
    mergeSummary(cards, hss.items, "hss")
  end

  local identityOK, identities = pcall(function()
    return exports.vhub_identity:getCharacterSummaries(src)
  end)
  if identityOK and type(identities) == "table" and identities.ok == true then
    mergeSummary(cards, identities.items, "identity")
  end
  return ordered
end

-- Seleciona personagem e decide entre criação obrigatória ou spawn.
function F.selecionar(src, cid)
  local s = F.sessions[src]
  if not s or s.step ~= "charselect" then return false, "estado_invalido" end

  -- Segura o pending do HSS antes de selectCore disparar characterLoad; sem o hold,
  -- handle_profile_loaded liberaria o spawn antes do SIMS abrir (R6 / replay-safe).
  if not holdCreation(src) then return false, "hss_indisponivel" end

  local selected, selectErr = selectCore(src, cid)
  if not selected then
    releaseCreation(src)
    return false, selectErr
  end

  local needed, needsErr = needsCreation(src)
  if needed == nil then
    releaseCreation(src)
    return false, needsErr
  end
  if not needed then
    -- Personagem completo: libera pending para o selector ou posição salva.
    releaseCreation(src)
    s.step = "spawning"
    return true, nil, "spawning"
  end

  if s.pick_char_id ~= cid then
    s.pick_char_id = cid
    s.pick_request_id = newRequestId(s, "pick")
  end
  local started, beginErr = enterCreation(src, s, cid, s.pick_request_id)
  if not started then
    releaseCreation(src)
    return false, beginErr
  end
  return true, nil, "creating"
end

-- Cria personagem no CORE e inicia o criador sem liberar o hold do HSS.
function F.criar(src)
  local s = F.sessions[src]
  if not s or s.step ~= "charselect" then return false, "estado_invalido" end

  -- Segura o hold do HSS ANTES de qualquer escrita no CORE. Sem o hold, handle_profile_loaded
  -- liberaria o spawn antes do SIMS abrir (R6 / replay-safe); e travando primeiro, se o HSS
  -- estiver indisponível falhamos SEM deixar personagem órfão no banco (conta segue zerada).
  if not holdCreation(src) then return false, "hss_indisponivel" end

  s.create_request_id = s.create_request_id or newRequestId(s, "create")
  local ok, created = pcall(function()
    return exports.vhub:createCharacter(src, s.create_request_id)
  end)
  if not ok or type(created) ~= "table" then
    releaseCreation(src)
    return false, "core_indisponivel"
  end
  if created.ok ~= true then
    releaseCreation(src)
    return false, created.err or "storage"
  end

  local char_id = tonumber(created.char_id)
  if not char_id then
    releaseCreation(src)
    return false, "storage"
  end

  local selected, selectErr = selectCore(src, char_id)
  if not selected then
    releaseCreation(src)
    return false, selectErr
  end

  local needed, needsErr = needsCreation(src)
  if needed == nil then
    releaseCreation(src)
    return false, needsErr
  end
  if not needed then
    releaseCreation(src)
    return false, "conflict"
  end

  local started, beginErr = enterCreation(src, s, char_id, s.create_request_id)
  if not started then
    releaseCreation(src)
    return false, beginErr
  end
  return true, nil, "creating"
end

-- Finaliza o handoff do criador e devolve a sessão à seleção.
function F.concluirCriacao(char_id)
  char_id = tonumber(char_id)
  local src = char_id and F.creatingByChar[char_id] or nil
  local s = src and F.sessions[src] or nil
  if not s or s.step ~= "creating" or s.creating_char_id ~= char_id then return nil end

  F.creatingByChar[char_id] = nil
  s.step = "charselect"
  s.creating_char_id = nil
  s.creation_session_id = nil
  s.create_request_id = nil
  s.pick_char_id = nil
  s.pick_request_id = nil
  return src
end
