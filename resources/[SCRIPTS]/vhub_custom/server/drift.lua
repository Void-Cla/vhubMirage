-- server/drift.lua — instalação/remoção do Freio de Mão Hidráulico (peça de desempenho)
--
-- Domínio: OFICINA (usa lease SERVICE_AUTH do oficina + ACTION_CODE.drift_install/drift_remove).
-- Saga idêntica ao OFICINA_NITRO_KIT: commitPayment → lockValid+refreshOperation → takeItem/giveItem
-- → saveVehicleState → completeOperation → auditVehicle.
-- Escritor único de customization.drift_capable (L-13, source='tune').
-- State Bag 'vhub_custom:drift' escrito aqui na entidade e reidratado por server/visual.lua::hydrate.
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local CFG  = VHubCustom.cfg
local E    = VHubCustom.E
local BAG  = VHubCustom.BAG

local DRIFT_ITEM = 'hydraulic_handbrake'


-- ============================================================
-- HELPERS
-- ============================================================

-- escreve o State Bag de drift na entidade viva (replicate=true → todos os clientes)
local function setBag(netId, value)
  if not netId or netId == 0 then return end
  local ent = NetworkGetEntityFromNetworkId(netId)
  if ent and ent ~= 0 and DoesEntityExist(ent) then
    Entity(ent).state:set(BAG.DRIFT, value == true, true)
  end
end

-- lê drift_capable do prontuário persistido (placa via conce)
local function currentDrift(plate)
  local st = Core.getVehicleState(plate)
  local cust = (st and type(st.customization) == 'table') and st.customization or {}
  return cust.drift_capable == true
end


-- ============================================================
-- INSTALL — Freio de Mão Hidráulico
-- ============================================================

RegisterNetEvent(E.DRIFT_INSTALL)
AddEventHandler(E.DRIFT_INSTALL, function(leaseId, requestId)
  local src = source
  local function reply(ok, message)
    TriggerClientEvent(E.DRIFT_CONFIRM, src, ok == true, message or '', 'install')
  end
  if not Core.rateOK(src, 'drift_install') then return reply(false, 'Aguarde um instante.') end

  local context, lock, why = Core.beginMutation(src, 'oficina', leaseId)
  if not context then
    return reply(false, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.')
  end
  local function finish(ok, message)
    Core.releaseLock(src, context.plate, lock)
    reply(ok, message)
  end

  local alreadyInstalled = currentDrift(context.plate)
  local cost = alreadyInstalled and 0 or CFG.prices.drift_install
  local before = { drift_capable = alreadyInstalled }
  local after  = { drift_capable = true }

  local paid, operationId, paymentErr, replayed, charged, operation = Core.commitPayment(
    context, 'drift_install', requestId, cost, { item = DRIFT_ITEM }, before, after)
  if not paid then
    return finish(false, paymentErr == 'insufficient'
      and ('Saldo insuficiente. Custo: R$ %d.'):format(cost)
      or 'Falha ao processar pagamento.')
  end

  if replayed then
    return finish(true, 'Operação já concluída.')
  end
  cost = tonumber(operation and operation.amount) or cost
  if alreadyInstalled then
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'drift_install', operationId, before, after, 'recovered_applied')
    return finish(true, 'Freio de mão hidráulico já instalado.')
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'drift_install', operationId, before, after, 'lease_lost_' .. compensation)
    return finish(false, compensated and 'Sessão encerrada. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.')
  end

  -- consome o item do inventário do jogador (etapa externa da saga — estorna no fail)
  local took = false
  pcall(function()
    took = exports.vhub_inventory:takeItem(src, DRIFT_ITEM, 1) == true
  end)
  if not took then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'drift_install', operationId, before, after, 'no_item_' .. compensation)
    return finish(false, compensated and 'Você não possui o Freio de Mão Hidráulico. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.')
  end

  -- persiste drift_capable = true (escritor único via saveVehicleState, source='tune')
  local saved = Core.saveVehicleState(context.plate, { customization = { drift_capable = true } }, 'tune')
  if not saved then
    -- estorna item e pagamento
    pcall(function() exports.vhub_inventory:giveItem(src, DRIFT_ITEM, 1) end)
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'drift_install', operationId, before, after, 'save_failed_' .. compensation)
    return finish(false, compensated and 'Falha ao salvar. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.')
  end

  -- propaga State Bag para todos os clientes (cobre carro em jogo sem passar pelo garage)
  setBag(context.net_id, true)

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'drift_install', operationId, before, after,
    replayed and 'replayed' or 'committed')
  Core.log(context.plate, 'drift_install', context.char_id, { cost = cost, operation_id = operationId })
  finish(true, ('Freio de Mão Hidráulico instalado! R$ %d cobrados.'):format(cost))
end)


-- ============================================================
-- REMOVE — Freio de Mão Hidráulico
-- ============================================================

RegisterNetEvent(E.DRIFT_REMOVE)
AddEventHandler(E.DRIFT_REMOVE, function(leaseId, requestId)
  local src = source
  local function reply(ok, message)
    TriggerClientEvent(E.DRIFT_CONFIRM, src, ok == true, message or '', 'remove')
  end
  if not Core.rateOK(src, 'drift_remove') then return reply(false, 'Aguarde um instante.') end

  local context, lock, why = Core.beginMutation(src, 'oficina', leaseId)
  if not context then
    return reply(false, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.')
  end
  local function finish(ok, message)
    Core.releaseLock(src, context.plate, lock)
    reply(ok, message)
  end

  local alreadyRemoved = not currentDrift(context.plate)
  local cost = alreadyRemoved and 0 or CFG.prices.drift_remove
  local before = { drift_capable = not alreadyRemoved }
  local after  = { drift_capable = false }

  local paid, operationId, paymentErr, replayed, charged, operation = Core.commitPayment(
    context, 'drift_remove', requestId, cost, { item = DRIFT_ITEM }, before, after)
  if not paid then
    return finish(false, paymentErr == 'insufficient'
      and ('Saldo insuficiente. Custo: R$ %d.'):format(cost)
      or 'Falha ao processar pagamento.')
  end

  if replayed then
    return finish(true, 'Operação já concluída.')
  end
  cost = tonumber(operation and operation.amount) or cost
  if alreadyRemoved then
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'drift_remove', operationId, before, after, 'recovered_applied')
    return finish(true, 'Peça já removida.')
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'drift_remove', operationId, before, after, 'lease_lost_' .. compensation)
    return finish(false, compensated and 'Sessão encerrada. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.')
  end

  -- persiste drift_capable = false ANTES de devolver o item (sem item perdido se persist falha)
  local saved = Core.saveVehicleState(context.plate, { customization = { drift_capable = false } }, 'tune')
  if not saved then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'drift_remove', operationId, before, after, 'save_failed_' .. compensation)
    return finish(false, compensated and 'Falha ao salvar. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.')
  end

  -- propaga State Bag (desativa drift em clientes que estiverem no carro)
  setBag(context.net_id, false)

  -- devolve a peça ao inventário (best-effort após persistência bem-sucedida)
  pcall(function() exports.vhub_inventory:giveItem(src, DRIFT_ITEM, 1) end)

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'drift_remove', operationId, before, after,
    replayed and 'replayed' or 'committed')
  Core.log(context.plate, 'drift_remove', context.char_id, { cost = cost, operation_id = operationId })
  finish(true, ('Freio de Mão Hidráulico removido. R$ %d cobrados.'):format(cost))
end)
