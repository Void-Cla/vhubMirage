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
local Creator = VHubSimsCreator
local recovering = {}  -- guard anti-reentrada de resumeCharacter (fluxo PAGO); ver ADR #97

-- ATENÇÃO (ADR #97): este arquivo cuida SÓ do checkout PAGO (barbearia/tattoo/roupas/cirurgião),
-- onde dinheiro justifica saga durável + compensação. A CRIAÇÃO INICIAL (grátis) vive em creator.lua
-- por um caminho direto sem saga. Não reintroduzir modo 'creator' aqui.

local function isCheckoutSaga(saga)
  return type(saga) == 'table' and type(saga.operation_id) == 'string'
    and type(saga.request_id) == 'string' and saga.request_id:sub(1, 9) == 'checkout:'
end


-- ============================================================
-- PAYLOAD DE ABERTURA (vitrine paga)
-- ============================================================

local function getCustomization(src)
  local ok, result = Core.call('vhub_hss', 'getCustomization', src)
  if not ok or not Core.resultOk(result) or type(result.customization) ~= 'table' then
    return nil, Core.resultError(result, 'dependency')
  end
  local normalized = AP.profile(result.customization)
  if not normalized then return nil, 'dependency' end
  return normalized, tonumber(result.revision) or 0
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
      face_groups = AP.copy(Catalog.face_groups or {}),
      presets = AP.copy(Catalog.presets or {}),
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
-- PRONTIDÃO DE CRIAÇÃO (consultada pelo login)
-- ============================================================

-- consulta no CORE se o personagem atual exige criação
-- A criação em si não usa mais saga durável (ADR #97 — caminho direto em creator.lua). Aqui só
-- restam duas coisas: (1) a verdade do CORE sobre 'created'; (2) o gate de dinheiro preso — uma
-- saga PAGA (barber/tattoo/…) em 'manual_reconcile' significa reconciliação financeira pendente e
-- deve bloquear até o admin resolver. Saga de criador não existe mais para bloquear nada.
function Creation.needsCreation(src)
  if not Core.ready then return { ok = false, err = 'not_ready' } end
  local user, charId = Core.getUser(src)
  if not user then return { ok = false, err = 'offline' } end

  -- Gate de dinheiro preso: só saga PAGA em manual_reconcile bloqueia (proteção financeira).
  local saga = SQL.getRecoverableSaga(charId)
  if saga and saga.mode ~= 'creator' and saga.state == 'manual_reconcile' then
    return { ok = false, err = 'conflict' }
  end

  local ok, result = Core.call('vhub', 'getSimsCreation', src)
  if not ok or not Core.resultOk(result) then
    return { ok = false, err = Core.resultError(result, 'storage') }
  end
  return { ok = true, needed = result.created ~= true }
end

-- abre o criador (delegação ao caminho direto de creator.lua — sem saga durável)
function Creation.beginCreation(src, requestId)
  return Creator.begin(src, requestId)
end


-- ============================================================
-- CHECKOUT E SAGA (paga)
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

local function commitCustomization(src, session, saga, patch)
  local expectedRevision = session.revision
  local decodedOk, persisted = pcall(json.decode, saga.payload or '{}')
  if decodedOk and type(persisted) == 'table' and tonumber(persisted.expected_revision) then
    expectedRevision = tonumber(persisted.expected_revision)
  end
  local ok, result = Core.call('vhub_hss', 'commitCustomization', src, patch,
    expectedRevision, saga.digest)
  -- 'busy' é transitório; retenta uma vez preservando a MESMA revisão CAS.
  if ok and type(result) == 'table' and result.ok ~= true and result.err == 'busy' then
    Citizen.Wait(50)
    ok, result = Core.call('vhub_hss', 'commitCustomization', src, patch,
      expectedRevision, saga.digest)
  end
  -- 'conflict' no checkout PAGO indica drift de revisão entre o snapshot capturado em
  -- openPaidStudio e a revisão viva do HSS — causado por flush fisiológico assíncrono que
  -- avançou customization_revision antes de o commit ser processado. O SIMS garante exclusão
  -- mútua (uma sessão paga ativa por jogador), então não há edição concorrente real.
  -- Rebase seguro: relê a revisão viva e retenta uma vez.
  if ok and type(result) == 'table' and result.ok ~= true and result.err == 'conflict' then
    local freshCurrent, freshRevision = getCustomization(src)
    if freshCurrent and freshRevision ~= nil then
      Core.log('info', 'commitCustomization conflict — rebase para revisão viva.', {
        src = src, char_id = session.char_id, mode = session.mode,
        stale_revision = expectedRevision, live_revision = freshRevision,
      })
      expectedRevision = freshRevision
      session.current = freshCurrent
      session.revision = freshRevision
      Citizen.Wait(25)
      ok, result = Core.call('vhub_hss', 'commitCustomization', src, patch,
        expectedRevision, saga.digest)
    end
  end
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
  if not VHubSimsShops or not VHubSimsShops.validate(src, active.shop_id, active.mode) then
    return nil, 'invalid_context'
  end

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

local function completeSaga(saga)
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
      Session.cleanup(src)
      TriggerClientEvent(E.CLI_STUDIO_CLOSE, src, { reason = prepareError, restore = true })
    end
    return false
  end
  if #prepared.changed == 0 then
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
      return false
    end
    Session.retry(src); sendResult(src, { ok = false, err = customizationError }); return false
  end
  local completed, completeError = completeSaga(saga)
  if not completed then sendResult(src, { ok = false, err = completeError }); return false end

  local result = { ok = true, charged = prepared.amount, changed = prepared.changed }
  Core.log('info', 'Checkout concluído.', {
    src = src, char_id = session.char_id, mode = session.mode,
    amount = prepared.amount, session_id = session.session_id,
  })
  closeSession(src, result, 'completed')
  return true
end


-- ============================================================
-- CANCELAMENTO E RETOMADA
-- ============================================================

-- cancela sessão de vitrine paga (criação tem seu próprio cancel em creator.lua)
function Creation.cancel(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'cancel') then return false end
  local session = Session.require(src, payload.session_id, 'studio')
  if not session then return false end

  Session.cancel(src, payload.session_id)
  TriggerClientEvent(E.CLI_STUDIO_CLOSE, src, { reason = 'cancelled', restore = true })
  return true
end

-- retoma saga PAGA (barbearia/tattoo/…) interrompida por reconnect sem duplicar débito nem aparência.
-- Criação (grátis) não gera saga (ADR #97) → nada a retomar aqui para modo criador.
function Creation.resumeCharacter(src, charId)
  if not Core.ready then return false end
  if recovering[charId] then return false end

  local saga = SQL.getRecoverableSaga(charId)
  if not isCheckoutSaga(saga) then return false end
  -- Saga de criador não existe mais; se aparecer uma antiga, ignore (o boot one-shot a fecha).
  if saga.mode == 'creator' then return false end

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
    local resumeRevision = tonumber(payload.expected_revision)
    local customOk, custom = Core.call('vhub_hss', 'commitCustomization', src, payload.patch,
      resumeRevision, saga.digest)
    -- rebase no resume: revisão pode ter avançado por flush fisiológico durante a interrupção
    if customOk and type(custom) == 'table' and custom.ok ~= true and custom.err == 'conflict' then
      local _, liveRevision = getCustomization(src)
      if liveRevision ~= nil and liveRevision ~= resumeRevision then
        Core.log('info', 'resumeCharacter conflict — rebase para revisão viva.', {
          src = src, char_id = charId, stale = resumeRevision, live = liveRevision,
        })
        customOk, custom = Core.call('vhub_hss', 'commitCustomization', src, payload.patch,
          liveRevision, saga.digest)
      end
    end
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

  if not transitionWithRetry(tonumber(saga.id), { 'customized' }, 'completed', nil) then
    return done(false)
  end
  Session.cleanup(src)
  return done(true)
end


-- ============================================================
-- EVENTOS
-- ============================================================

-- roteia por modo da sessão ativa: 'creator' → caminho direto (creator.lua); pago → saga (aqui).
local function isCreatorSession(src)
  local session = Session.get(src)
  return session ~= nil and session.mode == 'creator'
end

RegisterNetEvent(E.SRV_CHECKOUT, function(payload)
  if isCreatorSession(source) then
    Creator.checkout(source, payload)
  else
    Creation.checkout(source, payload)
  end
end)

RegisterNetEvent(E.SRV_WIZARD_SUBMIT, function(payload)
  -- wizard só existe no modo criador; sessão paga não tem identidade a submeter.
  Creator.submitWizard(source, payload)
end)

RegisterNetEvent(E.SRV_CANCEL, function(payload)
  if isCreatorSession(source) then
    Creator.cancel(source, payload)
  else
    Creation.cancel(source, payload)
  end
end)
