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
  local ok, released = pcall(function() return exports.vhub_hss:releaseCreationHold(src) end)
  return ok and released == true
end

local function prepareSpawnSelector(src)
  if GetResourceState("vhub_spawselector") ~= "started" then return nil, "dependency" end
  local ok, payload, err = pcall(function()
    return exports.vhub_spawselector:preparePending(src)
  end)
  if not ok or type(payload) ~= "table" or type(payload.data) ~= "table" then
    return nil, err or "dependency"
  end
  return payload
end

local function isolateEntry(src)
  if GetResourceState("vhub_hss") ~= "started" then return false end
  local ok, bucket = pcall(function() return exports.vhub_hss:isolateEntrySession(src) end)
  return ok and type(bucket) == "number" and bucket > 1 and bucket % 1 == 0
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

-- Rollback de rascunho (ADR #97 / L-03): apaga o char recém-criado que NÃO concluiu o criador,
-- para não deixar "Piloto N" órfão após erro/cancelamento. Idempotente e seguro no CORE (a
-- invariante lá recusa qualquer char com conclusão de criador — nunca apaga personagem real).
local function discardDraft(src, char_id)
  if not tonumber(char_id) then return false, "invalid_request" end
  local ok, result = pcall(function()
    return exports.vhub:discardDraftCharacter(src, char_id)
  end)
  if not ok then return false, "core_indisponivel" end
  if type(result) ~= "table" then return false, "resposta_invalida" end
  return result.ok == true, result.err
end

-- Compensação efêmera do login; só o CORE descarta. Mantém alvo/request até confirmar o efeito.
local function compensarRascunho(src, sessao, char_id)
  if F.sessions[src] ~= sessao then return false, "estado_invalido" end
  if sessao.descarte_em_andamento then return false, "rollback_pendente" end
  local alvo = sessao.rascunho_pendente or char_id
  if not alvo then return true end
  if char_id and char_id ~= alvo then return false, "rollback_pendente" end

  sessao.rascunho_pendente = alvo
  local pedido, token = sessao.create_request_id, {}
  sessao.descarte_em_andamento = token
  local descartado, erro = discardDraft(src, alvo)
  if not descartado then
    pcall(function()
      exports.vhub:log("error", "login", "Descarte de rascunho pendente; avanço bloqueado.", {
        src = src, char_id = alvo, erro = tostring(erro or "erro"),
      })
    end)
  end
  -- O export pode ceder execução; resposta antiga não limpa estado de outra operação/sessão.
  if F.sessions[src] ~= sessao or sessao.descarte_em_andamento ~= token then
    return false, "estado_invalido"
  end
  sessao.descarte_em_andamento = nil
  if sessao.rascunho_pendente ~= alvo or sessao.create_request_id ~= pedido then
    return false, "estado_invalido"
  end
  if not descartado then return false, "rollback_pendente" end
  sessao.rascunho_pendente = nil
  sessao.create_request_id = nil
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

-- is_new=true marca um char criado AGORA (F.criar). Só rascunhos assim são descartados no
-- cancelamento (rollback L-03). Retomada de char pré-existente (F.selecionar) usa is_new=false
-- para preservar a opção de continuar depois.
local function enterCreation(src, session, char_id, request_id, is_new)
  local result, err = beginCreation(src, request_id)
  if not result then return false, err end

  session.step = "creating"
  session.deadline = nil
  session.creating_char_id = char_id
  session.creating_is_new = is_new == true
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
      card.customization = customization
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


function F.isolarEntrada(src)
  local s = F.sessions[src]
  return s ~= nil and s.step == "charselect" and isolateEntry(src)
end

function F.prepararSeletor(src)
  local s = F.sessions[src]
  if not s or s.step ~= "spawning" then return nil, "estado_invalido" end
  return prepareSpawnSelector(src)
end

function F.concluirEntrada(src)
  local s = F.sessions[src]
  if not s or s.step ~= "spawning" then return false end
  s.step = "ready"
  s.deadline = nil
  return true
end

function F.voltarPersonagens(src)
  local s = F.sessions[src]
  if not s or (s.step ~= "spawning" and s.step ~= "creating") then
    return nil, "estado_invalido"
  end

  -- Cancela criação em andamento antes de voltar à seleção.
  if s.step == "creating" then
    local char_id = s.creating_char_id
    -- Rollback do rascunho NOVO ao voltar (L-03 / ADR #97): não deixa "Piloto N" órfão. Zera
    -- create_request_id junto (evita o mapa request→char devolver o char apagado na próxima criação).
    if char_id and s.creating_is_new then
      local descartado, erro = compensarRascunho(src, s, char_id)
      if not descartado then return nil, erro end
    end
    if char_id then F.creatingByChar[char_id] = nil end
    s.creating_char_id  = nil
    s.creating_is_new   = nil
    s.creation_session_id = nil
    s.create_request_id = nil
    s.pick_char_id      = nil
    s.pick_request_id   = nil
    -- Avisa o sims para fechar sua NUI e liberar o slot (ignore falha — pode já ter saído).
    pcall(function() exports.vhub_sims:cancelCreation(src) end)
  end

  s.step = "charselect"
  s.deadline = GetGameTimer() + (CFG.auth_deadline * 1000)
  if not isolateEntry(src) then
    s.step = "spawning"
    s.deadline = nil
    return nil, "hss_indisponivel"
  end
  local characters = F.personagens(src)
  if type(characters) ~= "table" then
    s.step = "spawning"
    s.deadline = nil
    return nil, "core_indisponivel"
  end
  F.armarDeadline(src)
  return characters
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
-- check pré-auth: IP + identifiers FiveM nativos (license, fivem, discord, steam, hw token).
function F.iniciar(src)
  if F.sessions[src] then return false end
  local uid = uidOf(src)
  if not uid then return false end
  local ip = GetPlayerEndpoint(src)
  local ids, hwToken = VHubLogin.Contas.extrairIdentifiers(src)
  local banned, banReason = VHubLogin.Contas.verificarBan(ip, nil, nil, ids, hwToken)
  if banned then
    DropPlayer(tostring(src), "Acesso bloqueado: " .. tostring(banReason or "banido") .. ".")
    return false
  end
  F.sessions[src] = {
    step        = "login",
    uid         = uid,
    deadline    = GetGameTimer() + (CFG.auth_deadline * 1000),
    identifiers = ids,
    hw_token    = hwToken,
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

  -- Ban pós-auth: IP + email/whatsapp da conta + identifiers FiveM nativos.
  -- identifiers já coletados em F.iniciar; reusar evita segunda chamada de nativas.
  local banned, banReason = VHubLogin.Contas.verificarBan(
    GetPlayerEndpoint(src), acc.email_lookup, acc.whatsapp_lookup,
    s.identifiers, s.hw_token)
  if banned then
    DropPlayer(tostring(src), "Acesso bloqueado: " .. tostring(banReason or "conta banida") .. ".")
    return false, "banido"
  end

  if not isolateEntry(src) then return false, "hss_indisponivel" end
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
  if not isolateEntry(src) then return false, "hss_indisponivel" end
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
    if char_id and char_id ~= s.rascunho_pendente then
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
  local compensado, erro = compensarRascunho(src, s)
  if not compensado then return false, erro end

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
    if not releaseCreation(src) then return false, "dependency" end
    s.step = "spawning"
    local selector, selectorErr = prepareSpawnSelector(src)
    if not selector then
      s.step = "charselect"
      return false, selectorErr
    end
    return true, nil, "spawning", selector
  end

  if s.pick_char_id ~= cid then
    s.pick_char_id = cid
    s.pick_request_id = newRequestId(s, "pick")
  end
  -- Retomada de rascunho pré-existente: is_new=false (NÃO descartar no cancelamento — preserva
  -- a opção de continuar depois; o rollback só se aplica a char criado agora em F.criar).
  local started, beginErr = enterCreation(src, s, cid, s.pick_request_id, false)
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
  local compensado, erro = compensarRascunho(src, s)
  if not compensado then return false, erro end

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

  -- Falha após createCharacter = char recém-criado órfão. Rollback (L-03 / ADR #97): apaga o
  -- rascunho e zera create_request_id (senão o mapa request→char_id devolveria o char apagado na
  -- retentativa; zerado, a próxima criação gera char novo). discardDraft é seguro (só rascunho).
  local function rollbackDraft(err)
    local descartado, erroDescarte = compensarRascunho(src, s, char_id)
    if erroDescarte == "estado_invalido" then return false, erroDescarte end
    releaseCreation(src)
    return false, descartado and err or erroDescarte
  end

  local selected, selectErr = selectCore(src, char_id)
  if not selected then return rollbackDraft(selectErr) end

  local needed, needsErr = needsCreation(src)
  if needed == nil then return rollbackDraft(needsErr) end
  if not needed then return rollbackDraft("conflict") end

  local started, beginErr = enterCreation(src, s, char_id, s.create_request_id, true)
  if not started then return rollbackDraft(beginErr) end
  return true, nil, "creating"
end

-- Finaliza o handoff do criador e devolve a sessão à seleção.
-- completed=true → criação concluída (mantém o char). completed~=true → cancelou/falhou: se era
-- rascunho NOVO (is_new), rollback L-03 (ADR #97) apaga o char pra não deixar "Piloto N" órfão.
function F.concluirCriacao(char_id, completed)
  char_id = tonumber(char_id)
  local src = char_id and F.creatingByChar[char_id] or nil
  local s = src and F.sessions[src] or nil
  if not s or s.step ~= "creating" or s.creating_char_id ~= char_id then return nil end
  if s.descarte_em_andamento then return nil end -- o encerramento em voo é o único escritor

  local erroDescarte
  if completed ~= true and s.creating_is_new then
    local descartado, erro = compensarRascunho(src, s, char_id)
    if erro == "estado_invalido" then return nil end
    if not descartado then erroDescarte = erro end
  end
  if F.sessions[src] ~= s or s.step ~= "creating" or s.creating_char_id ~= char_id then return nil end

  F.creatingByChar[char_id] = nil
  s.step = "charselect"
  s.creating_char_id = nil
  s.creating_is_new = nil
  s.creation_session_id = nil
  if not s.rascunho_pendente then s.create_request_id = nil end
  s.pick_char_id = nil
  s.pick_request_id = nil
  return src, isolateEntry(src), erroDescarte
end
