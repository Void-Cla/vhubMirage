-- server/mec.lua — reparo persistente e reboque físico autoritativo
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local CFG  = VHubCustom.cfg
local E    = VHubCustom.E

local REPAIR_TYPES = { tyre = true, engine = true, body = true }

local function itemCount(value)
  if type(value) ~= 'table' then return 0 end
  local count = 0
  for _ in pairs(value) do count = count + 1 end
  return math.min(count, 16)
end


-- ============================================================
-- DIAGNOSE (FASE 4 ADR #81) — laudo estruturado de danos reais
-- ============================================================

-- retorna tabela de diagnóstico da placa ou nil se prontuário indisponível.
-- Campos por componente: { label, ok, detail, cost }
exports('mecDiagnose', function(plate)
  local caller = GetInvokingResource()
  -- permitido apenas por recursos confiáveis ou chamada interna (sem invoker)
  local DIAG_TRUSTED = { ['vhub_custom'] = true, ['vhub_admin'] = true }
  if caller and not DIAG_TRUSTED[caller] then return nil end

  local p = type(plate) == 'string' and plate:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$') or nil
  if not p or #p < 2 then return nil end

  local state
  pcall(function() state = exports.vhub_conce:getVehicleState(p) end)
  if not state then return nil end

  local damage = type(state.damage) == 'table' and state.damage or {}
  local tyres_dmg  = itemCount(damage.tyres) + itemCount(damage.tyres_rim)
  local engine_hp  = tonumber(state.engine_health)
  local body_hp    = tonumber(state.body_health)
  local windows_dmg= itemCount(damage.windows)
  local doors_dmg  = itemCount(damage.doors)

  local function healthLabel(hp)
    if not hp then return 'desconhecido' end
    if hp >= 950 then return 'perfeito' end
    if hp >= 700 then return 'leve' end
    if hp >= 400 then return 'moderado' end
    return 'grave'
  end

  local unit_tyre  = CFG.prices.pneu         or 300
  local unit_motor = CFG.prices.motor_parcial  or 800
  local unit_body  = CFG.prices.lataria_parcial or 500

  local function engineCost()
    if not engine_hp or engine_hp ~= engine_hp then return nil end
    local dmg = math.max(0, 1000 - engine_hp)
    if dmg < 50 then return 0 end
    return math.ceil(dmg / 100) * unit_motor
  end

  local function bodyCost()
    if not body_hp or body_hp ~= body_hp then return nil end
    local dmg = math.max(0, 1000 - body_hp)
    if dmg < 50 then return 0 end
    return math.ceil(dmg / 100) * unit_body
  end

  return {
    motor  = { label = 'Motor',    ok = (engine_hp or 0) >= 950,
               detail = healthLabel(engine_hp),
               cost   = engineCost() },
    lataria= { label = 'Lataria',  ok = (body_hp or 0) >= 950,
               detail = healthLabel(body_hp),
               cost   = bodyCost() },
    pneus  = { label = 'Pneus',    ok = tyres_dmg == 0,
               detail = tyres_dmg > 0 and (tyres_dmg .. ' danificado(s)') or 'ok',
               cost   = tyres_dmg * unit_tyre },
    vidros = { label = 'Vidros',   ok = windows_dmg == 0,
               detail = windows_dmg > 0 and (windows_dmg .. ' quebrado(s)') or 'ok',
               cost   = 0 },
    portas = { label = 'Portas',   ok = doors_dmg == 0,
               detail = doors_dmg > 0 and (doors_dmg .. ' danificada(s)') or 'ok',
               cost   = 0 },
  }
end)

local function repairPatch(state, repairType)
  local damage = type(state.damage) == 'table' and state.damage or {}
  if repairType == 'tyre' then
    local count = itemCount(damage.tyres) + itemCount(damage.tyres_rim)
    local patch = { damage = {
      doors = damage.doors, windows = damage.windows, tyres = {}, tyres_rim = {},
    } }
    if count == 0 then return patch, 0, 'Pneus sem danos registrados.', true end
    return patch, count * CFG.prices.pneu
  end

  local key = repairType == 'engine' and 'engine_health' or 'body_health'
  local health = tonumber(state[key])
  if not health or health ~= health or math.abs(health) == math.huge then
    return nil, 0, 'Estado físico indisponível. Entre e saia do veículo.'
  end
  local damagePoints = math.max(0, 1000 - health)
  if damagePoints < 50 then
    return { [key] = health }, 0, 'Componente sem danos relevantes.', true
  end
  local unit = repairType == 'engine' and CFG.prices.motor_parcial or CFG.prices.lataria_parcial
  return { [key] = 1000.0 }, math.ceil(damagePoints / 100) * unit
end

RegisterNetEvent(E.MEC_REPAIR)
AddEventHandler(E.MEC_REPAIR, function(leaseId, requestId, repairType)
  local src = source
  if not Core.rateOK(src, 'mec_repair') then
    Core.notify(src, 'Aguarde antes de reparar.', 'error')
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, repairType, nil); return
  end
  if not REPAIR_TYPES[repairType] then TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, nil, nil); return end

  local context, lock, why = Core.beginMutation(src, 'mec', leaseId)
  if not context then
    Core.notify(src, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.', 'error')
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, repairType, nil); return
  end
  local function finish(ok, applyPhysical)
    Core.releaseLock(src, context.plate, lock)
    TriggerClientEvent(E.MEC_CONFIRM, src, context.plate, ok == true,
      ok == true and applyPhysical ~= false and repairType or nil, context.net_id)
  end

  local state = Core.getVehicleState(context.plate)
  if not state then Core.notify(src, 'Prontuário indisponível.', 'error'); return finish(false) end
  local patch, cost, invalidMessage, noOp = repairPatch(state, repairType)
  if not patch then Core.notify(src, invalidMessage, 'error'); return finish(false) end
  local before = repairType == 'tyre' and { damage = state.damage } or { [repairType .. '_health'] = state[repairType .. '_health'] }

  local paid, operationId, paymentErr, replayed, charged, operation = Core.commitPayment(context,
    'repair_' .. repairType, requestId, cost, patch, before, patch)
  if not paid then
    Core.notify(src, paymentErr == 'insufficient' and ('Saldo insuficiente. Reparo: R$ %d.'):format(cost)
      or 'Falha ao processar pagamento.', 'error')
    return finish(false)
  end

  if replayed then
    Core.notify(src, 'Operação já concluída.', 'info')
    return finish(true, false)
  end
  cost = tonumber(operation and operation.amount) or cost
  if noOp or Core.sameSubset(state, patch) then
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch, 'recovered_applied')
    Core.notify(src, invalidMessage or 'Reparo já aplicado.', 'info')
    return finish(true, false)
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch,
      'lease_lost_' .. compensation)
    Core.notify(src, compensated and 'Sessão encerrada. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.', 'error')
    return finish(false)
  end

  if not Core.saveVehicleState(context.plate, patch, 'repair') then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch,
      'save_failed_' .. compensation)
    Core.notify(src, compensated and 'Falha ao salvar. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.', 'error')
    return finish(false)
  end

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch,
    replayed and 'replayed' or 'committed')
  Core.log(context.plate, 'mec_repair_' .. repairType, context.char_id,
    { cost = cost, operation_id = operationId })
  Core.notify(src, ('Reparo concluído. R$ %d cobrados.'):format(cost), 'success')
  finish(true)
end)

local function moveAndVerify(entity, target)
  for _ = 1, 5 do
    if not DoesEntityExist(entity) then return nil end
    local moved = pcall(SetEntityCoords, entity, target.x, target.y, target.z,
      false, false, false, false)
    local headed = pcall(SetEntityHeading, entity, target.h)
    if not moved or not headed then return nil end
    Citizen.Wait(100)
    if DoesEntityExist(entity) then
      local read, current = pcall(GetEntityCoords, entity)
      if read and current then
        local dx, dy, dz = current.x - target.x, current.y - target.y, current.z - target.z
        if dx * dx + dy * dy + dz * dz <= 4.0 then
          local headingOk, heading = pcall(GetEntityHeading, entity)
          if headingOk then return { x = current.x, y = current.y, z = current.z, h = heading } end
        end
      end
    end
  end
  return nil
end

RegisterNetEvent(E.MEC_TOW_REQ)
AddEventHandler(E.MEC_TOW_REQ, function(leaseId, requestId)
  local src = source
  if not Core.rateOK(src, 'mec_tow') then
    Core.notify(src, 'Aguarde antes de rebocar.', 'error')
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, 'tow', nil); return
  end

  local context, lock, why = Core.beginMutation(src, 'mec', leaseId)
  if not context then
    Core.notify(src, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.', 'error')
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, 'tow', nil); return
  end
  local function finish(ok)
    Core.releaseLock(src, context.plate, lock)
    TriggerClientEvent(E.MEC_CONFIRM, src, context.plate, ok == true, 'tow', context.net_id)
  end

  if Core.vehicleHasOccupants(context.entity) then
    Core.notify(src, 'Todos devem sair do veículo antes do reboque.', 'error'); return finish(false)
  end
  local target = context.zone.tow_drop
  if type(target) ~= 'table' then Core.notify(src, 'Destino de reboque inválido.', 'error'); return finish(false) end
  local readOld, old = pcall(GetEntityCoords, context.entity)
  local readHeading, oldHeading = pcall(GetEntityHeading, context.entity)
  if not readOld or not old or not readHeading then
    Core.notify(src, 'Réplica do veículo indisponível.', 'error'); return finish(false)
  end
  local before = { x = old.x, y = old.y, z = old.z, h = oldHeading, db = context.vehicle.position }
  local validRequest, operationId, paymentErr, replayed, charged, operation =
    Core.commitPayment(context, 'tow', requestId, 0, target, before, target)
  if not validRequest then
    Core.notify(src, paymentErr == 'refunded' and 'Operação anterior foi cancelada.'
      or 'Solicitação de reboque inválida.', 'error')
    return finish(false)
  end
  if replayed then Core.notify(src, 'Reboque já concluído.', 'info'); return finish(true) end
  if Core.operationApplied(operation) then
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'tow', operationId, before, target, 'recovered_applied')
    Core.notify(src, 'Reboque já concluído.', 'info')
    return finish(true)
  end
  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    Core.compensatePayment(operationId, false, charged)
    Core.auditVehicle(context, 'tow', operationId, nil, target, 'lease_lost')
    Core.notify(src, 'Sessão de reboque encerrada.', 'error'); return finish(false)
  end
  if Core.vehicleHasOccupants(context.entity) then
    Core.compensatePayment(operationId, false, charged)
    Core.notify(src, 'Todos devem sair do veículo antes do reboque.', 'error'); return finish(false)
  end

  local actual = moveAndVerify(context.entity, target)
  if not actual then
    moveAndVerify(context.entity, before)
    Core.compensatePayment(operationId, false, charged)
    Core.auditVehicle(context, 'tow', operationId, before, target, 'move_failed')
    Core.notify(src, 'Falha ao assumir a réplica do veículo.', 'error'); return finish(false)
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    local rolledBack = moveAndVerify(context.entity, before) ~= nil
    Core.compensatePayment(operationId, false, charged)
    Core.auditVehicle(context, 'tow', operationId, before, actual,
      rolledBack and 'lease_lost_rolled_back' or 'lease_lost_rollback_failed')
    Core.notify(src, rolledBack and 'Sessão encerrada; posição restaurada.'
      or 'Falha crítica no reboque.', 'error')
    return finish(false)
  end

  local positionJson = ('{"x":%.3f,"y":%.3f,"z":%.3f,"h":%.3f}')
    :format(actual.x, actual.y, actual.z, actual.h)
  if not Core.updatePosition(context.plate, positionJson) then
    local rolledBack = moveAndVerify(context.entity, before) ~= nil
    Core.compensatePayment(operationId, false, charged)
    Core.auditVehicle(context, 'tow', operationId, before, actual,
      rolledBack and 'save_failed_rolled_back' or 'save_failed_rollback_failed')
    Core.notify(src, rolledBack and 'Falha ao salvar; posição restaurada.' or 'Falha crítica no reboque.', 'error')
    return finish(false)
  end

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'tow', operationId, before, actual, 'committed')
  Core.log(context.plate, 'mec_tow', context.char_id, { operation_id = operationId })
  Core.notify(src, 'Veículo reposicionado com sucesso.', 'success')
  finish(true)
end)
