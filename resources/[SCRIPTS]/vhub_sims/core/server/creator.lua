-- creator.lua — criação inicial de personagem (caminho direto, sem saga durável)
---@diagnostic disable: undefined-global

-- Este arquivo é o dono do fluxo de CRIAÇÃO INICIAL de char (ADR #97). É deliberadamente separado
-- de creation.lua (checkout PAGO de barbearia/tattoo) porque a criação é GRÁTIS (amount=0) e
-- single-writer-por-char: não precisa de saga durável, pagamento nem CAS de revisão congelado —
-- justamente o aparato que travava o fluxo ("aparência mudou em outra sessão" / "char ocupado").
--
-- Idempotência SEM saga, por chaves que já existem no kernel:
--   • aparência: HSS operation_replay por digest (customization.lua) — rebase por digest embutido.
--   • identidade: vhub_identity dedup por operation_id (digest).
--   • marca de criação: CORE commitSimsCreation dedup por apv (auth.lua).
--
-- INVARIANTES (pagas em gate — não violar):
--   [SEG] CREATION_DONE ⟺ commitSimsCreation.ok. Falha DEPOIS do commit NUNCA emite CANCELLED
--         (o char já é válido; CANCELLED tentaria descriá-lo e prenderia o login).
--   [PER] Ordem b→c→d→e exata: aparência → identidade → commitSimsCreation → selectCharacter.
--         A âncora de FK da aparência é vh_characters (criada no beginCreation), não vh_sims_creation;
--         marcar 'created' só DEPOIS da aparência garante que não há char created sem aparência.
--   [PER] Ler a revisão VIVA no instante do commit (getCustomization), nunca congelar no payload.

VHubSimsCreator = VHubSimsCreator or {}

local Creator = VHubSimsCreator
local Core = VHubSimsCore
local Session = VHubSimsSession
local AP = VHubSims.APShape
local E = VHubSims.E
local Catalog = VHubSims.catalog


-- ============================================================
-- VALIDAÇÃO E IDENTIDADE
-- ============================================================

local function validId(value, maximum)
  return type(value) == 'string' and #value >= 8 and #value <= maximum
    and value:match('^[%w_:%-%.]+$') ~= nil
end

local function sanitizeName(value)
  if type(value) ~= 'string' then return nil end
  value = value:match('^%s*(.-)%s*$'):gsub('[^%a%sÀ-ÿ%-]', ''):gsub('%s+', ' '):sub(1, 50)
  if #value < 2 then return nil end
  return value
end

local VALID_ROLES = {
  legal = true, ilegal = true, mecanica = true,
  hospital = true, policia = true, livre = true,
}

-- normaliza identidade efêmera do wizard (mesmas regras do fluxo pago, fonte única aqui)
local function sanitizeIdentity(payload)
  if type(payload) ~= 'table' then return nil end
  local firstname = sanitizeName(payload.firstname)
  local lastname = sanitizeName(payload.lastname)
  local age = tonumber(payload.age)
  if not firstname or not lastname or not age or age ~= math.floor(age) or age < 16 or age > 120 then
    return nil
  end
  local role = type(payload.role) == 'string' and payload.role or nil
  if role and not VALID_ROLES[role] then return nil end
  local backstory = nil
  if type(payload.backstory) == 'string' then
    backstory = payload.backstory:match('^%s*(.-)%s*$'):sub(1, 1000)
    if backstory == '' then backstory = nil end
  end
  return { firstname = firstname, lastname = lastname, age = age,
           role = role, backstory = backstory }
end


-- ============================================================
-- ABERTURA / PRONTIDÃO
-- ============================================================

-- Budget da espera do owner físico (HSS): 120 × 50ms = 6s por handoff (L-18), 1 por abertura.
-- O 1º char de um boot frio pode levar > 2s no round-trip inicial do HSS (load + digest).
local READY_ATTEMPTS = 120
local READY_POLL_MS = 50

-- lê aparência atual e revisão viva do owner físico (HSS)
local function getCustomization(src)
  local ok, result = Core.call('vhub_hss', 'getCustomization', src)
  if not ok or not Core.resultOk(result) or type(result.customization) ~= 'table' then
    return nil, Core.resultError(result, 'dependency')
  end
  local normalized = AP.profile(result.customization)
  if not normalized then return nil, 'dependency' end
  return normalized, tonumber(result.revision) or 0
end

-- Aguarda (bounded) o owner físico (HSS) concluir o load ASSÍNCRONO do char recém-selecionado.
-- 'not_ready' é transitório (o gate de login reexibe e permite retry); erro terminal retorna direto.
local function waitOwnerReady(src)
  local lastErr = 'not_ready'
  for _ = 1, READY_ATTEMPTS do
    local current, revisionOrErr = getCustomization(src)
    if current then return current, tonumber(revisionOrErr) or 0 end
    lastErr = revisionOrErr or 'dependency'
    if lastErr ~= 'not_ready' then return nil, nil, lastErr end
    Citizen.Wait(READY_POLL_MS)
  end
  Core.log('error', 'Owner físico HSS não ficou pronto no budget — criação abortada (not_ready).', {
    src = src, last_err = lastErr,
  })
  return nil, nil, lastErr
end

-- monta payload de abertura do estúdio no modo criador (sem preços — criação é grátis)
local function openingPayload(session)
  local mode = Catalog.modes.creator
  return {
    mode = 'creator',
    label = mode.label,
    paid = false,
    tabs = AP.copy(mode.tabs),
    current = AP.copy(session.current),
    prices = {},
    catalog = {
      components = AP.copy(Catalog.component_labels),
      props = AP.copy(Catalog.prop_labels),
      tattoos = {},
      face_groups = AP.copy(Catalog.face_groups or {}),
      presets = AP.copy(Catalog.presets or {}),
    },
    session_id = session.session_id,
  }
end

local function sendOpen(src, session)
  TriggerClientEvent(E.CLI_STUDIO_OPEN, src, openingPayload(session))
end

local function sendResult(src, result)
  TriggerClientEvent(E.CLI_CHECKOUT_RESULT, src, result)
end

-- encerra o estágio físico do criador no HSS (idempotente pelo próprio HSS)
local function endStage(src, session)
  if not session.stage_token then return false, 'invalid_session' end
  local ok, result = Core.call('vhub_hss', 'endPendingStage', src, session.stage_token)
  if not ok or not Core.resultOk(result) then
    return false, Core.resultError(result, 'dependency')
  end
  return true
end


-- ============================================================
-- ENTRY POINTS (consumidos por creation.lua / login)
-- ============================================================

-- abre o criador mantendo o char no estágio pending do HSS; idempotente por request_id
function Creator.begin(src, requestId)
  if not Core.ready then return { ok = false, err = 'not_ready' } end
  if not validId(requestId, 64) then return { ok = false, err = 'invalid_request' } end
  if not Core.rate(src, 'begin') then return { ok = false, err = 'rate_limited' } end

  local user, charId = Core.getUser(src)
  if not user then return { ok = false, err = 'offline' } end

  -- Replay da mesma abertura: a sessão em memória já existe para este request.
  local active = Session.get(src)
  if active then
    if active.mode == 'creator' and active.request_id == requestId then
      sendOpen(src, active)
      return { ok = true, session_id = active.session_id, replayed = true }
    end
    return { ok = false, err = 'conflict' }
  end

  -- Barreira de prontidão: o HSS carrega o estado do char recém-selecionado de forma assíncrona.
  -- Espera bounded e já traz a aparência atual + revisão viva; transitório NÃO persiste nada.
  local current, revision, readyErr = waitOwnerReady(src)
  if not current then return { ok = false, err = readyErr or 'not_ready' } end

  -- Estágio físico do criador (bucket isolado + câmera). Falha aqui não deixa nada órfão.
  local sessionId = Core.token('creation', src)
  local okStage, stageResult = Core.call('vhub_hss', 'beginPendingStage', src, sessionId)
  if not okStage or not Core.resultOk(stageResult) or type(stageResult.stage_token) ~= 'string' then
    return { ok = false, err = Core.resultError(stageResult, 'dependency') }
  end
  local _, stageCharId = Core.getUser(src)
  if stageCharId ~= charId then
    Core.call('vhub_hss', 'endPendingStage', src, stageResult.stage_token)
    return { ok = false, err = 'conflict' }
  end

  local session = Session.start(src, {
    mode = 'creator',
    char_id = charId,
    request_id = requestId,
    session_id = sessionId,
    stage_token = stageResult.stage_token,
    current = current,
    revision = revision,
  })
  if not session then
    Core.call('vhub_hss', 'endPendingStage', src, stageResult.stage_token)
    return { ok = false, err = 'conflict' }
  end

  sendOpen(src, session)
  Core.log('info', 'Criador aberto (caminho direto).', { src = src, char_id = charId, session_id = sessionId })
  return { ok = true, session_id = sessionId }
end

-- valida e guarda identidade efêmera da sessão de criação
function Creator.submitWizard(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'wizard') then return false end
  local session = Session.require(src, payload.session_id, 'studio')
  if not session or session.mode ~= 'creator' then return false end

  local identity = sanitizeIdentity(payload)
  if not identity then
    sendResult(src, { ok = false, err = 'invalid_identity' })
    return false
  end

  session.identity = identity
  sendResult(src, { ok = true, wizard = true })
  return true
end


-- ============================================================
-- COMMIT DIRETO (idempotente, sem saga)
-- ============================================================

-- aplica a aparência lendo a revisão VIVA no instante do commit
local function applyAppearance(src, session, patch, digest)
  -- [PER] Revisão viva no commit — nunca congelada. getCustomization devolve a revisão atual do HSS;
  -- se um flush fisiológico avançou entry.version na janela, o HSS retorna 'busy' (transitório) e
  -- o próprio commitCustomization retenta; conflito de customization_revision aqui só ocorreria por
  -- edição concorrente real (não presumir impossibilidade fora do SIMS).
  local current, revision = getCustomization(src)
  if not current then return nil, 'dependency' end
  session.current = current
  session.revision = revision

  local ok, result = Core.call('vhub_hss', 'commitCustomization', src, patch, revision, digest)
  -- Só rebaseia divergência ANTES de escrever a operação, e somente se a aparência
  -- autoritativa permaneceu idêntica. Outro escritor real continua sendo conflito.
  if ok and type(result) == 'table' and result.err == 'conflict'
    and result.reason == 'revision_mismatch' then
    local freshCurrent, freshRevision = getCustomization(src)
    if freshCurrent and freshRevision ~= revision
      and AP.digest(freshCurrent) == AP.digest(current) then
      session.current = freshCurrent
      session.revision = freshRevision
      ok, result = Core.call('vhub_hss', 'commitCustomization', src, patch, freshRevision, digest)
    end
  end
  -- 'busy' é transitório (flush em voo): retenta uma vez relendo a revisão viva.
  if ok and type(result) == 'table' and result.ok ~= true and result.err == 'busy' then
    Citizen.Wait(50)
    local retryCurrent, retryRevision = getCustomization(src)
    if not retryCurrent then return nil, 'dependency' end
    if AP.digest(retryCurrent) ~= AP.digest(current) then return nil, 'conflict' end
    session.current = retryCurrent
    session.revision = retryRevision
    ok, result = Core.call('vhub_hss', 'commitCustomization', src, patch, retryRevision, digest)
  end
  if not ok or not Core.resultOk(result) then
    Core.log('warn', 'Commit de aparência do criador recusado.', {
      src = src, char_id = session.char_id,
      err = Core.resultError(result, 'dependency'),
      reason = type(result) == 'table' and result.reason or nil,
    })
    return nil, Core.resultError(result, 'dependency')
  end

  local customization = type(result.customization) == 'table'
    and AP.profile(result.customization) or AP.merge(session.current, patch)
  if not customization then return nil, 'dependency' end
  session.current = customization
  session.revision = tonumber(result.new_revision) or session.revision
  return customization
end

-- executa a criação idempotente na ordem b→c→d→e e emite o resultado ao login (invariante SEG)
function Creator.checkout(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'checkout') then return false end

  local session = Session.require(src, payload.session_id, 'studio')
  if not session or session.mode ~= 'creator' then
    sendResult(src, { ok = false, err = 'invalid_session' })
    return false
  end
  if Session.expired(session) then
    Creator.abort(src, session, 'expired')
    return false
  end
  local _, activeCharId = Core.getUser(src)
  if activeCharId ~= session.char_id then
    Creator.abort(src, session, 'invalid_session')
    return false
  end
  if not session.identity then
    sendResult(src, { ok = false, err = 'identity_required' })
    return false
  end

  local patch, patchError = Core.sanitizePatch(payload.patch, 'creator')
  if not patch then
    sendResult(src, { ok = false, err = patchError })
    return false
  end
  if VHubSimsOutfits and not VHubSimsOutfits.isAllowed(src, patch) then
    sendResult(src, { ok = false, err = 'forbidden_piece' })
    return false
  end

  -- Trava a sessão para commit único; replay do MESMO digest devolve o resultado memoizado.
  local digest = AP.digest({ session_id = session.session_id, mode = 'creator',
    patch = patch, identity = session.identity })
  local locked, lockError, cached = Session.beginCommit(src, session.session_id, digest)
  if cached then sendResult(src, cached); return cached.ok end
  if not locked then
    sendResult(src, { ok = false, err = lockError or 'invalid_session' })
    return false
  end
  session = locked

  -- (b) aparência — ANTES da marca de criação (âncora de FK é vh_characters, já existe)
  if next(patch) ~= nil then
    local customization, appearanceError = applyAppearance(src, session, patch, digest)
    if not customization then
      Session.retry(src)
      sendResult(src, { ok = false, err = appearanceError })
      return false
    end
  end

  -- (c) identidade — dedup por digest no vhub_identity
  local identityOk, identityResult = Core.call('vhub_identity', 'setIdentity', src, session.identity, digest)
  if not identityOk or not Core.resultOk(identityResult) then
    Session.retry(src)
    sendResult(src, { ok = false, err = Core.resultError(identityResult, 'dependency') })
    return false
  end

  -- Encerra o estágio físico antes de marcar 'created' (handoff do ped concluído).
  local stageEnded, stageError = endStage(src, session)
  if not stageEnded then
    Session.retry(src)
    sendResult(src, { ok = false, err = stageError })
    return false
  end

  -- (d) marca de criação — PONTO DE NÃO-RETORNO. commitSimsCreation.ok ⟹ char é válido (SEG).
  -- apv=2 = formato APV2; dedup idempotente por (char_id, apv) no CORE.
  local commitOk, commitResult = Core.call('vhub', 'commitSimsCreation', src, digest, 2)
  if not commitOk or not Core.resultOk(commitResult) then
    -- Falha ANTES do ponto de não-retorno: o char ainda não é 'created'. Retry idempotente
    -- (a aparência/identidade já aplicadas são reconhecidas por digest). Login segue em 'creating'.
    Session.retry(src)
    sendResult(src, { ok = false, err = Core.resultError(commitResult, 'storage') })
    return false
  end

  -- ⟵ A PARTIR DAQUI o char está criado. Nenhum caminho abaixo pode emitir CANCELLED (SEG).
  local charId = session.char_id

  -- (e) seleção do char ativo — UI/estado, NÃO é verdade de criação. Falha aqui NÃO descria o char.
  local selectOk = Core.call('vhub', 'selectCharacter', src, charId)
  if not selectOk then
    Core.log('warn', 'selectCharacter falhou após criação concluída (char permanece válido).', {
      src = src, char_id = charId,
    })
  end

  local result = { ok = true, charged = 0, changed = {}, created = true }
  Session.finish(src, result)
  sendResult(src, result)
  TriggerClientEvent(E.CLI_STUDIO_CLOSE, src, { reason = 'creation_completed', restore = false })

  Core.log('info', 'Criação concluída (caminho direto).', {
    src = src, char_id = charId, session_id = session.session_id,
    replayed = commitResult.replayed == true,
  })
  -- [SEG] CREATION_DONE ⟺ commitSimsCreation.ok — emitido SÓ aqui, no sucesso do commit.
  TriggerEvent(E.CREATION_DONE, charId)
  return true
end


-- ============================================================
-- CANCELAMENTO
-- ============================================================

-- aborta a criação ANTES do ponto de não-retorno: restaura estágio físico e cancela o rascunho.
-- Só pode ser chamado enquanto o char NÃO está 'created' (senão violaria a invariante SEG).
function Creator.abort(src, session, reason)
  Session.cleanup(src)
  endStage(src, session)
  sendResult(src, { ok = false, err = reason })
  TriggerClientEvent(E.CLI_STUDIO_CLOSE, src, { reason = reason, restore = true })
  if GetPlayerName(src) then TriggerEvent(E.CREATION_CANCELLED, session.char_id) end
end

-- cancela a sessão de criação a pedido do jogador (botão sair no estúdio)
function Creator.cancel(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'cancel') then return false end
  local session = Session.require(src, payload.session_id, 'studio')
  if not session or session.mode ~= 'creator' then return false end
  Creator.abort(src, session, 'cancelled')
  return true
end
