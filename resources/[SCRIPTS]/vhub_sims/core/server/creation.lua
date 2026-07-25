-- creation.lua — abertura, checkout, compensação e retomada durável do SIMS
---@diagnostic disable: undefined-global

VHubSimsCreation = VHubSimsCreation or {}

local Creation = VHubSimsCreation
local Core = VHubSimsCore
local SQL = VHubSimsSQL
local Session = VHubSimsSession
local Pricing = VHubSimsPricing
local AP = VHubSims.APShape
local E = VHubSims.E
local Catalog = VHubSims.catalog
local recovering = {}

local function isCheckoutSaga(saga)
  return type(saga) == 'table' and type(saga.operation_id) == 'string'
    and type(saga.request_id) == 'string' and saga.request_id:sub(1, 9) == 'checkout:'
end


-- ============================================================
-- VALIDAÇÃO E PAYLOAD DE ABERTURA
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

local function sanitizeIdentity(payload)
  if type(payload) ~= 'table' then return nil end
  local firstname = sanitizeName(payload.firstname)
  local lastname = sanitizeName(payload.lastname)
  local age = tonumber(payload.age)
  if not firstname or not lastname or not age or age ~= math.floor(age) or age < 16 or age > 120 then
    return nil
  end
  return { firstname = firstname, lastname = lastname, age = age }
end

local function getCustomization(src)
  local ok, result = Core.call('vhub_hss', 'getCustomization', src)
  if not ok or not Core.resultOk(result) or type(result.customization) ~= 'table' then
    return nil, Core.resultError(result, 'dependency')
  end
  local normalized = AP.profile(result.customization)
  if not normalized then return nil, 'dependency' end
  return normalized, tonumber(result.revision) or 0
end

-- Budget da espera do owner físico (HSS): 120 × 50ms = 6s máximo por chamada (L-18), 1 por handoff.
-- Elevado de 2s→6s (2026-07-22): o 1º char de um boot frio pode levar mais que 2s no round-trip
-- inicial do HSS (load + insert_if_absent + digest). Continua bounded e 1× por handoff.
local READY_ATTEMPTS = 120
local READY_POLL_MS = 50

-- Aguarda (bounded) o owner físico (HSS) concluir o load ASSÍNCRONO do char recém-selecionado e
-- devolve (aparência, revisão). 'recovering' e 'not_ready' são transitórios (reespera); qualquer
-- outro erro é terminal. Timeout → 'not_ready' (o gate de login reexibe e permite retry idempotente).
local function waitOwnerReady(src, charId)
  local lastErr = 'not_ready'
  for _ = 1, READY_ATTEMPTS do
    if not recovering[charId] then
      local current, revisionOrErr = getCustomization(src)
      if current then return current, tonumber(revisionOrErr) or 0 end
      lastErr = revisionOrErr or 'dependency'
      if lastErr ~= 'not_ready' then return nil, nil, lastErr end
    end
    Citizen.Wait(READY_POLL_MS)
  end
  -- Diagnóstico: o owner físico (HSS) NÃO ficou pronto dentro do budget. Se isto aparecer de forma
  -- persistente, o char não é carregado pelo HSS (State.is_loaded=false) — investigar _state_ready
  -- do vhub_hss (boot em duas fases) OU falha de State.register do char recém-criado.
  Core.log('error', 'Owner físico HSS não ficou pronto no budget — criação abortada (not_ready).', {
    src = src, char_id = charId, last_err = lastErr,
    hint = 'checar log do vhub_hss: "Falha ao carregar estado do personagem" OU _state_ready=false',
  })
  return nil, nil, lastErr
end

local function openingPayload(session)
  local mode = Catalog.modes[session.mode]
  return {
    mode = session.mode,
    label = mode.label,
    paid = mode.paid,
    tabs = AP.copy(mode.tabs),
    current = AP.copy(session.current),
    prices = AP.copy(Catalog.prices[session.mode] or {}),
    catalog = {
      components = AP.copy(Catalog.component_labels),
      props = AP.copy(Catalog.prop_labels),
      tattoos = session.mode == 'tattoo' and AP.copy(VHubSims.tattoos) or {},
    },
    session_id = session.session_id,
  }
end

local function sendOpen(src, session)
  TriggerClientEvent(E.CLI_STUDIO_OPEN, src, openingPayload(session))
end

-- abre uma vitrine paga já validada pelo servidor de zonas
function Creation.openPaidStudio(src, mode, shopId)
  if not Core.ready or type(mode) ~= 'string' or not Catalog.modes[mode]
    or Catalog.modes[mode].paid ~= true then
    return { ok = false, err = 'invalid_mode' }
  end

  local user, charId = Core.getUser(src)
  if not user then return { ok = false, err = 'offline' } end
  if Session.get(src) then return { ok = false, err = 'conflict' } end

  local current, revision = getCustomization(src)
  if not current then return { ok = false, err = 'dependency' } end

  local sessionId = Core.token('studio', src)
  local session = Session.start(src, {
    mode = mode,
    char_id = charId,
    request_id = Core.token('open', src),
    session_id = sessionId,
    shop_id = shopId,
    current = current,
    revision = revision,
  })
  if not session then return { ok = false, err = 'conflict' } end

  sendOpen(src, session)
  return { ok = true, session_id = sessionId }
end

local function sendResult(src, result)
  TriggerClientEvent(E.CLI_CHECKOUT_RESULT, src, result)
end

local function closeSession(src, result, reason)
  Session.finish(src, result)
  sendResult(src, result)
  TriggerClientEvent(E.CLI_STUDIO_CLOSE, src, { reason = reason, restore = false })
end


-- ============================================================
-- CRIADOR
-- ============================================================

-- consulta no CORE se o personagem atual exige criação
function Creation.needsCreation(src)
  if not Core.ready then return { ok = false, err = 'storage' } end
  local user, charId = Core.getUser(src)
  if not user then return { ok = false, err = 'offline' } end

  -- recuperação em voo para este char = transitório (o gate reespera), não conflito terminal.
  if recovering[charId] then
    Core.log('warn', 'needsCreation: recuperação em voo bloqueou (not_ready).', { src = src, char_id = charId })
    return { ok = false, err = 'not_ready' }
  end
  local saga = SQL.getRecoverableSaga(charId)
  if saga and saga.mode == 'creator' and saga.state == 'manual_reconcile' then
    return { ok = false, err = 'conflict' }
  end
  local checkoutPending = isCheckoutSaga(saga) and saga.mode == 'creator'
    and (saga.state == 'prepared' or saga.state == 'charged' or saga.state == 'customized')
  if checkoutPending then
    if not Creation.resumeCharacter(src, charId) then
      return { ok = false, err = 'conflict' }
    end
    return { ok = true, needed = false }
  end

  local ok, result = Core.call('vhub', 'getSimsCreation', src)
  if not ok or not Core.resultOk(result) then
    return { ok = false, err = Core.resultError(result, 'storage') }
  end
  return { ok = true, needed = result.created ~= true }
end

-- abre o criador mantendo o personagem no estágio pending do HSS
function Creation.beginCreation(src, requestId)
  if not Core.ready then return { ok = false, err = 'storage' } end
  if not validId(requestId, 64) then return { ok = false, err = 'invalid_request' } end

  local user, charId = Core.getUser(src)
  if not user then return { ok = false, err = 'offline' } end
  -- recuperação em voo para este char = transitório (o gate reespera), não conflito terminal.
  if recovering[charId] then
    Core.log('warn', 'beginCreation: recuperação em voo bloqueou (not_ready).', { src = src, char_id = charId })
    return { ok = false, err = 'not_ready' }
  end
  local recoverable = SQL.getRecoverableSaga(charId)
  local checkoutRecovery = isCheckoutSaga(recoverable) and recoverable.mode == 'creator'
  if recoverable and recoverable.mode == 'creator'
    and (recoverable.state == 'manual_reconcile' or (checkoutRecovery
      and (recoverable.state == 'prepared' or recoverable.state == 'charged'
        or recoverable.state == 'customized'))) then
    return { ok = false, err = 'conflict' }
  end

  local active = Session.get(src)
  if active then
    if active.mode == 'creator' and active.request_id == requestId then
      sendOpen(src, active)
      return { ok = true, session_id = active.session_id, replayed = true }
    end
    return { ok = false, err = 'conflict' }
  end

  local needed = Creation.needsCreation(src)
  if not needed.ok then return needed end
  if not needed.needed then return { ok = false, err = 'already_created' } end

  -- Barreira de prontidão: o owner físico (HSS) carrega o estado do char recém-selecionado de
  -- forma ASSÍNCRONA. Prosseguir antes disso devolvia conflict/dependency e deixava saga órfã.
  -- Espera bounded pelo owner ficar pronto e já traz a aparência atual; transitório NÃO persiste.
  local current, revision, readyErr = waitOwnerReady(src, charId)
  if not current then return { ok = false, err = readyErr or 'not_ready' } end

  -- session_id estável por request (replay via request memoizado no login).
  local existing = SQL.getSagaByRequest(requestId)
  if existing and existing.state == 'completed' then
    return { ok = true, session_id = existing.session_id, replayed = true }
  end
  local sessionId = existing and existing.session_id or Core.token('creation', src)

  if not SQL.closeStaleCreationStages(charId, requestId) then
    return { ok = false, err = 'storage' }
  end

  -- Estágio físico do criador — owner já pronto. Falha aqui NÃO deixa saga órfã (nada persistido).
  local okStage, stageResult = Core.call('vhub_hss', 'beginPendingStage', src, sessionId)
  if not okStage or not Core.resultOk(stageResult) or type(stageResult.stage_token) ~= 'string' then
    return { ok = false, err = Core.resultError(stageResult, 'dependency') }
  end
  local stageToken = stageResult.stage_token

  -- Só agora persiste a saga (handoff garantido); qualquer falha adiante reverte o estágio físico.
  local stageDigest, stagePayload = AP.digest({ char_id = charId, request_id = requestId })
  local stageSaga, sagaErr = SQL.createSaga({
    char_id = charId,
    request_id = requestId,
    session_id = sessionId,
    mode = 'creator',
    payload = stagePayload,
    digest = stageDigest,
    amount = 0,
  })
  if not stageSaga then
    Core.call('vhub_hss', 'endPendingStage', src, stageToken)
    return { ok = false, err = sagaErr }
  end
  if stageSaga.state == 'completed' then
    Core.call('vhub_hss', 'endPendingStage', src, stageToken)
    return { ok = true, session_id = sessionId, replayed = true }
  end

  local session = Session.start(src, {
    mode = 'creator',
    char_id = charId,
    request_id = requestId,
    session_id = sessionId,
    stage_token = stageToken,
    stage_saga_id = tonumber(stageSaga.id),
    current = current,
    revision = revision,
  })
  if not session then
    Core.call('vhub_hss', 'endPendingStage', src, stageToken)
    SQL.transitionSaga(tonumber(stageSaga.id), { 'prepared' }, 'refunded', 'session_conflict')
    return { ok = false, err = 'conflict' }
  end

  sendOpen(src, session)
  Core.log('info', 'Criador aberto.', { src = src, char_id = charId, session_id = sessionId })
  return { ok = true, session_id = sessionId }
end

-- valida e guarda identidade efêmera da sessão de criação
function Creation.submitWizard(src, payload)
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
-- CHECKOUT E SAGA
-- ============================================================

local function createCheckoutSaga(session, patch, digest, canonical)
  local suffix = digest:sub(1, 12)
  local requestId = ('checkout:%s:%s'):format(session.session_id, suffix)
  local sagaSession = ('%s:%s'):format(session.session_id, suffix)
  local payload = json.encode({
    patch = patch,
    identity = session.identity,
    expected_revision = session.revision,
  })
  return SQL.createSaga({
    char_id = session.char_id,
    request_id = requestId,
    session_id = sagaSession,
    mode = session.mode,
    operation_id = digest,
    payload = payload or canonical,
    digest = digest,
    amount = session.checkout_amount or 0,
  })
end

local function refundSaga(src, saga, err)
  local result
  for attempt = 1, 3 do
    local called
    called, result = Core.call('vhub_money', 'refundPayment', saga.operation_id)
    if called and Core.resultOk(result) then break end
    if attempt < 3 then Citizen.Wait(50 * attempt) end
  end
  if Core.resultOk(result) then
    for attempt = 1, 3 do
      if SQL.transitionSaga(tonumber(saga.id), { 'prepared', 'charged' }, 'refunded', err) then
        saga.state = 'refunded'
        return true
      end
      Citizen.Wait(50 * attempt)
    end
  end

  Core.ready = false
  SQL.transitionSaga(tonumber(saga.id), { 'prepared', 'charged' }, 'manual_reconcile',
    Core.resultError(result, 'refund_failed'))
  Core.log('error', 'Saga exige reconciliação manual.', {
    saga_id = tonumber(saga.id), operation_id = saga.operation_id, sims_blocked = true,
  })
  return false
end

local function transitionWithRetry(sagaId, expected, nextState, err)
  for attempt = 1, 3 do
    if SQL.transitionSaga(sagaId, expected, nextState, err) then return true end
    Citizen.Wait(50 * attempt)
  end
  return false
end

local function finalizeCreation(src, session, saga, customization)
  local identityOk, identityResult = Core.call('vhub_identity', 'setIdentity', src,
    session.identity, saga.digest)
  if not identityOk or not Core.resultOk(identityResult) then
    Session.retry(src)
    return false, Core.resultError(identityResult, 'dependency')
  end

  local endOk, endResult = Core.call('vhub_hss', 'endPendingStage', src, session.stage_token)
  if not endOk or not Core.resultOk(endResult) then
    Session.retry(src)
    return false, Core.resultError(endResult, 'dependency')
  end

  local commitOk, commitResult = Core.call('vhub', 'commitSimsCreation', src, saga.digest, 2)
  if not commitOk or not Core.resultOk(commitResult) then
    Session.retry(src)
    return false, Core.resultError(commitResult, 'storage')
  end

  if not transitionWithRetry(tonumber(saga.id), { 'customized' }, 'completed', nil) then
    Core.log('error', 'Saga finalizada externamente aguarda fechamento SQL.', {
      saga_id = tonumber(saga.id),
    })
  end
  transitionWithRetry(session.stage_saga_id, { 'prepared' }, 'completed', nil)
  return true
end

local function commitCustomization(src, session, saga, patch)
  local expectedRevision = session.revision
  local decodedOk, persisted = pcall(json.decode, saga.payload or '{}')
  if decodedOk and type(persisted) == 'table' and tonumber(persisted.expected_revision) then
    expectedRevision = tonumber(persisted.expected_revision)
  end
  local ok, result = Core.call('vhub_hss', 'commitCustomization', src, patch,
    expectedRevision, saga.digest)
  if not ok or not Core.resultOk(result) then
    return nil, Core.resultError(result, 'dependency')
  end

  local customization = type(result.customization) == 'table'
    and AP.profile(result.customization) or AP.merge(session.current, patch)
  if not customization then return nil, 'dependency' end
  session.current = customization
  session.revision = tonumber(result.new_revision) or session.revision
  return customization
end

local function prepareCheckout(src, payload, forcedPatch)
  local active = Session.get(src)
  if not active or active.session_id ~= payload.session_id then return nil, 'invalid_session' end
  if Session.expired(active) then return nil, 'expired' end
  if active.mode ~= 'creator' and (not VHubSimsShops
    or not VHubSimsShops.validate(src, active.shop_id, active.mode)) then
    return nil, 'invalid_context'
  end
  if active.mode == 'creator' and not active.identity then return nil, 'identity_required' end

  local patch, patchError = Core.sanitizePatch(forcedPatch or payload.patch, active.mode)
  if not patch then return nil, patchError end
  local after = AP.merge(active.current, patch)
  if VHubSimsOutfits and not VHubSimsOutfits.isAllowed(src, patch) then
    return nil, 'forbidden_piece'
  end
  if active.mode == 'tattoo' and not Pricing.validTattoos(after.tattoos) then
    return nil, 'invalid_patch'
  end

  local amount, changed = Pricing.calculate(active.mode, active.current, after)
  local digest, canonical = AP.digest({ session_id = active.session_id, mode = active.mode,
    patch = patch, identity = active.identity, amount = amount })
  active.checkout_amount = amount
  return {
    active = active,
    patch = patch,
    amount = amount,
    changed = changed,
    digest = digest,
    canonical = canonical,
  }
end

local function chargeSaga(src, session, saga, amount)
  if amount == 0 or saga.state ~= 'prepared' then return true end
  local ok, result = Core.call('vhub_money', 'commitPayment', src, amount,
    saga.operation_id, 'sims:' .. session.mode)
  if not ok or not Core.resultOk(result) then
    return false, Core.resultError(result, 'dependency')
  end
  if not SQL.transitionSaga(tonumber(saga.id), { 'prepared' }, 'charged', nil) then
    local refunded = refundSaga(src, saga, 'charge_transition_failed')
    return false, refunded and 'storage' or 'manual_reconcile'
  end
  saga.state = 'charged'
  return true
end

local function customizeSaga(src, session, saga, patch, amount)
  if saga.state ~= 'prepared' and saga.state ~= 'charged' then return session.current end
  if next(patch) == nil then
    if not SQL.transitionSaga(tonumber(saga.id), { 'prepared', 'charged' }, 'customized', nil) then
      return nil, 'storage'
    end
    saga.state = 'customized'
    return session.current
  end
  local customization, customizationError = commitCustomization(src, session, saga, patch)
  if not customization then
    if amount > 0 and saga.state == 'charged' then refundSaga(src, saga, customizationError) end
    return nil, customizationError
  end
  if not transitionWithRetry(tonumber(saga.id), { 'prepared', 'charged' }, 'customized', nil) then
    return nil, 'pending_recovery'
  end
  saga.state = 'customized'
  return customization
end

local function completeSaga(src, session, saga, customization)
  if session.mode == 'creator' then return finalizeCreation(src, session, saga, customization) end
  if not transitionWithRetry(tonumber(saga.id), { 'customized' }, 'completed', nil) then
    Core.log('error', 'Checkout aplicado aguarda fechamento SQL.', { saga_id = tonumber(saga.id) })
  end
  return true
end

-- executa checkout idempotente, com pagamento e compensação duráveis
function Creation.checkout(src, payload, forcedPatch)
  if type(payload) ~= 'table' or not Core.rate(src, 'checkout') then return false end
  local prepared, prepareError = prepareCheckout(src, payload, forcedPatch)
  if not prepared then
    sendResult(src, { ok = false, err = prepareError })
    if prepareError == 'expired' or prepareError == 'invalid_context' then
      local rejected = Session.cleanup(src)
      TriggerClientEvent(E.CLI_STUDIO_CLOSE, src, { reason = prepareError, restore = true })
      if rejected and rejected.mode == 'creator' and rejected.stage_token then
        Core.call('vhub_hss', 'endPendingStage', src, rejected.stage_token)
        SQL.transitionSaga(rejected.stage_saga_id, { 'prepared' }, 'refunded', prepareError)
        TriggerEvent(E.CREATION_CANCELLED, rejected.char_id)
      end
    end
    return false
  end
  if prepared.active.mode ~= 'creator' and #prepared.changed == 0 then
    local unchanged = { ok = true, charged = 0, changed = {} }
    closeSession(src, unchanged, 'completed')
    return true
  end

  local session, lockError, cached = Session.beginCommit(src, prepared.active.session_id,
    prepared.digest)
  if cached then sendResult(src, cached); return cached.ok end
  if not session then
    sendResult(src, { ok = false, err = lockError or 'invalid_session' })
    return false
  end

  local saga, sagaError = createCheckoutSaga(session, prepared.patch, prepared.digest,
    prepared.canonical)
  if not saga then
    Session.retry(src)
    sendResult(src, { ok = false, err = sagaError })
    return false
  end

  if saga.state == 'completed' then
    local replay = { ok = true, charged = tonumber(saga.amount) or 0, replayed = true }
    closeSession(src, replay, 'completed')
    return true
  end
  if saga.state == 'refunded' or saga.state == 'manual_reconcile' then
    Session.retry(src)
    sendResult(src, { ok = false, err = saga.state })
    return false
  end

  local charged, chargeError = chargeSaga(src, session, saga, prepared.amount)
  if not charged then Session.retry(src); sendResult(src, { ok = false, err = chargeError }); return false end
  local customization, customizationError = customizeSaga(src, session, saga, prepared.patch,
    prepared.amount)
  if not customization then
    if customizationError == 'pending_recovery' then
      Session.cleanup(src)
      sendResult(src, { ok = false, err = customizationError })
      TriggerClientEvent(E.CLI_STUDIO_CLOSE, src, { reason = customizationError, restore = false })
      if session.mode == 'creator' then
        Core.call('vhub_hss', 'endPendingStage', src, session.stage_token)
        SQL.transitionSaga(session.stage_saga_id, { 'prepared' }, 'refunded', customizationError)
        TriggerEvent(E.CREATION_CANCELLED, session.char_id)
      end
      return false
    end
    Session.retry(src); sendResult(src, { ok = false, err = customizationError }); return false
  end
  local completed, completeError = completeSaga(src, session, saga, customization)
  if not completed then sendResult(src, { ok = false, err = completeError }); return false end

  local result = { ok = true, charged = prepared.amount, changed = prepared.changed }
  Core.log('info', 'Checkout concluído.', {
    src = src, char_id = session.char_id, mode = session.mode,
    amount = prepared.amount, session_id = session.session_id,
  })
  local creationCompleted = session.mode == 'creator'
  local completedCharId = session.char_id
  closeSession(src, result, creationCompleted and 'creation_completed' or 'completed')
  if creationCompleted then TriggerEvent(E.CREATION_DONE, completedCharId) end
  return true
end


-- ============================================================
-- CANCELAMENTO E RETOMADA
-- ============================================================

-- cancela sessão após restaurar o estágio físico pelo owner HSS
function Creation.cancel(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'cancel') then return false end
  local session = Session.require(src, payload.session_id, 'studio')
  if not session then return false end

  if session.mode == 'creator' then
    local ok, result = Core.call('vhub_hss', 'endPendingStage', src, session.stage_token)
    if not ok or not Core.resultOk(result) then
      sendResult(src, { ok = false, err = Core.resultError(result, 'dependency') })
      return false
    end
    SQL.transitionSaga(session.stage_saga_id, { 'prepared' }, 'refunded', 'cancelled')
  end

  Session.cancel(src, payload.session_id)
  TriggerClientEvent(E.CLI_STUDIO_CLOSE, src, { reason = 'cancelled', restore = true })
  if session.mode == 'creator' then TriggerEvent(E.CREATION_CANCELLED, session.char_id) end
  return true
end

-- retoma saga online após reconnect sem duplicar débito ou customização
function Creation.resumeCharacter(src, charId)
  if not Core.ready then return false end
  if recovering[charId] then return false end

  -- Só reivindica 'recovering' quando há DE FATO uma saga de checkout a retomar. Marcar antes do
  -- getRecoverableSaga (async) fazia TODO char recém-carregado — inclusive um NOVO, sem saga —
  -- segurar recovering=true durante o await do SQL. O fluxo de criação do login roda logo após o
  -- characterLoad (mesmo tick) e batia nesse recovering em needsCreation/beginCreation, devolvendo
  -- 'not_ready' SILENCIOSO ("preparando seu piloto") e deixando o char órfão. Sem saga → nada a
  -- retomar → não toca recovering → o criador abre normalmente.
  local saga = SQL.getRecoverableSaga(charId)
  if not isCheckoutSaga(saga) then return false end
  local checkoutSession = saga.session_id:match('^(.*):[%x]+$')
  if not checkoutSession then return false end

  recovering[charId] = true
  local function done(result)
    recovering[charId] = nil
    return result
  end

  local okPayload, payload = pcall(json.decode, saga.payload)
  if not okPayload or type(payload) ~= 'table' or type(payload.patch) ~= 'table'
    or not tonumber(payload.expected_revision) then
    SQL.transitionSaga(tonumber(saga.id), { saga.state }, 'manual_reconcile', 'invalid_payload')
    return done(false)
  end

  if saga.state == 'prepared' and tonumber(saga.amount) and tonumber(saga.amount) > 0 then
    local paidOk, paid = Core.call('vhub_money', 'commitPayment', src, tonumber(saga.amount),
      saga.operation_id, 'sims:' .. saga.mode)
    if not paidOk or not Core.resultOk(paid) then
      refundSaga(src, saga, Core.resultError(paid, 'payment_conflict'))
      return done(false)
    end
    if not SQL.transitionSaga(tonumber(saga.id), { 'prepared' }, 'charged', nil) then
      refundSaga(src, saga, 'charge_transition_failed')
      return done(false)
    end
    saga.state = 'charged'
  end

  if (saga.state == 'prepared' or saga.state == 'charged') and next(payload.patch) ~= nil then
    local customOk, custom = Core.call('vhub_hss', 'commitCustomization', src, payload.patch,
      tonumber(payload.expected_revision), saga.digest)
    if not customOk or not Core.resultOk(custom) then
      if saga.state == 'charged' then refundSaga(src, saga, Core.resultError(custom, 'dependency')) end
      return done(false)
    end
    if not transitionWithRetry(tonumber(saga.id), { 'prepared', 'charged' }, 'customized', nil) then
      return done(false)
    end
    saga.state = 'customized'
  elseif saga.state == 'prepared' or saga.state == 'charged' then
    if not SQL.transitionSaga(tonumber(saga.id), { saga.state }, 'customized', nil) then
      return done(false)
    end
    saga.state = 'customized'
  end

  if saga.state ~= 'customized' then return done(false) end

  if saga.mode ~= 'creator' then
    if not transitionWithRetry(tonumber(saga.id), { 'customized' }, 'completed', nil) then
      return done(false)
    end
    Session.cleanup(src)
    return done(true)
  end

  if type(payload.identity) ~= 'table' then
    SQL.transitionSaga(tonumber(saga.id), { 'customized' }, 'manual_reconcile', 'invalid_identity')
    return done(false)
  end

  local okIdentity, identity = Core.call('vhub_identity', 'setIdentity', src, payload.identity, saga.digest)
  if not okIdentity or not Core.resultOk(identity) then return done(false) end

  local current = getCustomization(src)
  if type(current) ~= 'table' then return done(false) end
  local okCommit, committed = Core.call('vhub', 'commitSimsCreation', src, saga.digest, 2)
  if not okCommit or not Core.resultOk(committed) then return done(false) end

  if not transitionWithRetry(tonumber(saga.id), { 'customized' }, 'completed', nil) then
    return done(false)
  end
  local stageSaga = SQL.getSagaBySession(charId, checkoutSession)
  if stageSaga then
    transitionWithRetry(tonumber(stageSaga.id), { 'prepared' }, 'completed', nil)
  end
  Session.cleanup(src)
  TriggerEvent(E.CREATION_DONE, charId)
  return done(true)
end


-- ============================================================
-- EVENTOS
-- ============================================================

RegisterNetEvent(E.SRV_CHECKOUT, function(payload)
  Creation.checkout(source, payload)
end)

RegisterNetEvent(E.SRV_WIZARD_SUBMIT, function(payload)
  Creation.submitWizard(source, payload)
end)

RegisterNetEvent(E.SRV_CANCEL, function(payload)
  Creation.cancel(source, payload)
end)
