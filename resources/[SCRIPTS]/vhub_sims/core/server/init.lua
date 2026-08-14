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
  Core.log('info', 'SIMS 1.2.3 pronto.', {})
end

VHubSimsAdmin = VHubSimsAdmin or {}

-- força saga de charId de 'manual_reconcile' → 'refunded' e relança o boot recovery
local function forceResolveSaga(charId)
  charId = tonumber(charId)
  if not charId then return false, 'char_id_invalido' end
  local saga = SQL.getRecoverableSaga(charId)
  if not saga or saga.state ~= 'manual_reconcile' then
    return false, 'saga_nao_encontrada_ou_estado_invalido'
  end
  local ok = SQL.transitionSaga(tonumber(saga.id), { 'manual_reconcile' }, 'refunded', 'admin_force')
  if not ok then return false, 'transicao_falhou' end
  Core.log('warn', 'Saga manual_reconcile forçada para refunded por admin.', {
    saga_id = tonumber(saga.id),
    char_id = charId,
  })
  if not Core.ready then
    Citizen.CreateThread(function()
      Core.ready = false
      if recoverBoot() then
        Core.ready = true
        Core.log('info', 'SIMS reativado após resolução de saga.', {})
      end
    end)
  end
  return true
end

VHubSimsAdmin.forceResolveSaga = forceResolveSaga

RegisterCommand('sims_clear_saga', function(src, args)
  if src ~= 0 then return end  -- somente console do servidor
  local charId = tonumber(args[1])
  if not charId then
    Core.log('warn', 'Uso: sims_clear_saga <char_id>', {})
    return
  end
  local ok, err = forceResolveSaga(charId)
  if ok then
    Core.log('info', 'Saga resolvida por admin via console.', { char_id = charId })
  else
    Core.log('error', 'Falha ao resolver saga via console.', { char_id = charId, err = err })
  end
end, true)

-- desbloqueio de emergência: mata sessão em memória do SIMS independente de saga SQL.
-- Uso: sims_reset_session <src>
-- Quando usar: sims_clear_saga não bastou (a saga estava em 'prepared', não 'manual_reconcile'),
-- e o jogador recebe 'conflitou' ao tentar selecionar o char na próxima vez.
RegisterCommand('sims_reset_session', function(src, args)
  if src ~= 0 then return end  -- somente console do servidor
  local targetSrc = tonumber(args[1])
  if not targetSrc then
    Core.log('warn', 'Uso: sims_reset_session <src>', {})
    return
  end
  local session = Session.get(targetSrc)
  if not session then
    Core.log('warn', 'sims_reset_session: nenhuma sessão em memória.', { src = targetSrc })
    return
  end
  -- Encerrar stage físico antes de limpar para não deixar o jogador preso no interior de criação.
  if session.mode == 'creator' and session.stage_token then
    Core.call('vhub_hss', 'endPendingStage', targetSrc, session.stage_token)
    SQL.transitionSaga(session.stage_saga_id, { 'prepared' }, 'refunded', 'admin_reset_session')
  end
  Session.cleanup(targetSrc)
  Core.log('warn', 'sims_reset_session: sessão removida por admin.', {
    src = targetSrc, mode = session.mode, session_id = session.session_id,
  })
end, true)

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
