-- init.lua — boot, recuperação durável e lifecycle server do SIMS
---@diagnostic disable: undefined-global

local Core = VHubSimsCore
local SQL = VHubSimsSQL
local Session = VHubSimsSession
local Creation = VHubSimsCreation

local RECOVERY_BATCH = 16
local RECOVERY_MAX_BATCHES = 32
local RECOVERY_BACKOFF_MS = 250

local function recoverChargedSaga(saga)
  local sagaId = tonumber(saga.id)
  if not sagaId or type(saga.operation_id) ~= 'string' then
    Core.log('error', 'Saga cobrada inválida no recovery.', { saga_id = sagaId })
    return false
  end

  local result
  for attempt = 1, 3 do
    local called
    called, result = Core.call('vhub_money', 'refundPayment', saga.operation_id)
    if called and Core.resultOk(result) then break end
    if attempt < 3 then Citizen.Wait(100 * attempt) end
  end
  if not Core.resultOk(result) then
    Core.log('error', 'Estorno de recovery falhou; SIMS permanece bloqueado.', {
      saga_id = sagaId,
      err = Core.resultError(result, 'dependency'),
    })
    return false
  end

  for attempt = 1, 3 do
    if SQL.transitionSaga(sagaId, { 'charged' }, 'refunded', 'boot_recovery') then
      Core.log('info', 'Saga cobrada estornada no recovery.', { saga_id = sagaId })
      return true
    end
    if attempt < 3 then Citizen.Wait(100 * attempt) end
  end

  Core.log('error', 'Estorno concluído sem transição; SIMS permanece bloqueado.', {
    saga_id = sagaId,
  })
  return false
end

-- Budget: até 16 sagas/lote, quatro lotes/s, máximo de 32 lotes antes de liberar o SIMS.
local function recoverBoot()
  local cursor = 0
  for batch = 1, RECOVERY_MAX_BATCHES do
    local rows = SQL.listRecoverableSagas(cursor, RECOVERY_BATCH)
    if not rows then
      Core.log('error', 'Falha ao listar sagas recuperáveis.', {})
      return false
    end

    for _, saga in ipairs(rows) do
      cursor = math.max(cursor, tonumber(saga.id) or cursor)
      if saga.state == 'customized' and saga.mode ~= 'creator' then
        if not SQL.transitionSaga(tonumber(saga.id), { 'customized' }, 'completed', nil) then
          Core.log('error', 'Falha ao concluir saga no recovery.', { saga_id = tonumber(saga.id) })
          return false
        end
      elseif saga.state == 'charged' and not recoverChargedSaga(saga) then
        return false
      elseif saga.state == 'manual_reconcile' then
        Core.log('error', 'Saga pendente de reconciliação; SIMS permanece bloqueado.', {
          saga_id = tonumber(saga.id),
        })
        return false
      end
    end

    if #rows < RECOVERY_BATCH then return true end
    Citizen.Wait(RECOVERY_BACKOFF_MS)
  end

  Core.log('error', 'Recovery excedeu o limite de lotes; SIMS permanece bloqueado.', {})
  return false
end

local function boot()
  local ok, err = SQL.applySchema()
  if not ok then
    Core.log('error', 'SIMS bloqueado por falha de schema.', { err = err })
    return
  end
  Core.ready = false
  if not recoverBoot() then return end
  Core.ready = true
  Core.log('info', 'SIMS 1.0.1 pronto.', {})
end

AddEventHandler('onResourceStart', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(boot)
end)

AddEventHandler('vHub:characterLoad', function(user)
  if type(user) ~= 'table' or not tonumber(user.source) or not tonumber(user.char_id) then return end
  local src, charId = tonumber(user.source), tonumber(user.char_id)
  Citizen.CreateThread(function() Creation.resumeCharacter(src, charId) end)
end)

AddEventHandler('playerDropped', function()
  local src = source
  local session = Session.cleanup(src)
  Core.cleanup(src)
  if session and session.mode == 'creator' and session.stage_token then
    Core.call('vhub_hss', 'endPendingStage', src, session.stage_token)
    SQL.transitionSaga(session.stage_saga_id, { 'prepared' }, 'refunded', 'dropped')
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == 'vhub_hss' then
    Session.each(function(src, session)
      Session.cleanup(src)
      TriggerClientEvent(VHubSims.E.CLI_STUDIO_CLOSE, src, {
        reason = 'dependency_stopped',
        restore = false,
      })
      if session.mode == 'creator' then
        SQL.transitionSaga(session.stage_saga_id, { 'prepared' }, 'refunded', 'hss_stopped')
        if GetPlayerName(src) then TriggerEvent(VHubSims.E.CREATION_CANCELLED, session.char_id) end
      end
    end)
    return
  end
  if resource ~= GetCurrentResourceName() then return end
  Session.each(function(src, session)
    Session.cleanup(src)
    if session.mode == 'creator' and session.stage_token then
      Core.call('vhub_hss', 'endPendingStage', src, session.stage_token)
      SQL.transitionSaga(session.stage_saga_id, { 'prepared' }, 'refunded', 'resource_stopped')
      if GetPlayerName(src) then TriggerEvent(VHubSims.E.CREATION_CANCELLED, session.char_id) end
    end
  end)
  Core.ready = false
end)
