-- server/mec.lua — reparo persistente e reboque físico autoritativo
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local CFG  = VHubCustom.cfg
local E    = VHubCustom.E
local U    = VHubCustom.U
local B    = VHubCustom.BAG
local respostas = {}
local reparos = {}

RegisterNetEvent(E.MEC_PHYSICAL_OK)
AddEventHandler(E.MEC_PHYSICAL_OK, function(token, ok, snapshot)
  local pendente = type(token) == 'string' and respostas[token]
  if not pendente or pendente.resolvido or source ~= pendente.dono then return end
  local contexto = pendente.contexto
  if not DoesEntityExist(contexto.entity) or NetworkGetEntityOwner(contexto.entity) ~= source
      or U.normalizePlate(GetVehicleNumberPlateText(contexto.entity)) ~= contexto.plate
      or GetEntityRoutingBucket(contexto.entity) ~= contexto.bucket then return end
  pendente.resolvido, pendente.ok = true, ok == true
  pendente.snapshot = type(snapshot) == 'table' and snapshot or nil
end)

local function fisica(contexto, token, componente)
  local dono = NetworkGetEntityOwner(contexto.entity)
  if not dono or dono <= 0 or not GetPlayerName(dono) then return false end
  local pendente = { dono = dono, contexto = contexto }
  respostas[token] = pendente
  TriggerClientEvent(E.MEC_PHYSICAL, dono, token, contexto.net_id, contexto.plate, componente)
  local prazo = GetGameTimer() + 4500
  while not pendente.resolvido and GetGameTimer() < prazo do Citizen.Wait(25) end
  respostas[token] = nil
  if not pendente.resolvido then return nil end
  return pendente.ok, pendente.snapshot
end

local REPAIR_TYPES = { tyre = true, engine = true, body = true }
local REPAIR_ITEMS = {
  tyre = 'kit_pneus',
  engine = 'kit_chave_nivel_1',
  body = 'martelinho_ouro',
}

local function possuiMaterial(src, item)
  local ok, possui = pcall(function() return exports.vhub_inventory:hasItem(src, item, 1) end)
  return ok and possui == true
end

local function consumirMaterial(src, item)
  local ok, consumiu = pcall(function() return exports.vhub_inventory:takeItem(src, item, 1) end)
  return ok and consumiu == true
end

local function devolverMaterial(src, item)
  local ok, devolveu = pcall(function() return exports.vhub_inventory:giveItem(src, item, 1) end)
  return ok and devolveu == true
end

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
  local tyres_dmg  = U.contarPneus(U.danoFisico(damage))
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
    return math.max(1, math.ceil(dmg / 100)) * unit_body
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
  local patch, custo, semDano = U.reparo(state, repairType, CFG.prices)
  return patch, custo, patch and 'Componente sem danos relevantes.' or 'Estado físico indisponível.', semDano
end

RegisterNetEvent(E.MEC_REPAIR)
AddEventHandler(E.MEC_REPAIR, function(leaseId, requestId, repairType)
  local src = source
  if not Core.rateOK(src, 'mec_repair') then
    Core.notify(src, 'Aguarde antes de reparar.', 'error')
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, repairType, nil, leaseId); return
  end
  if not REPAIR_TYPES[repairType] or not Core.requestId(requestId) then
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, nil, nil, leaseId); return
  end

  local context, lock, why = Core.beginMutation(src, 'mec', leaseId)
  if not context then
    Core.notify(src, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.', 'error')
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, repairType, nil, leaseId); return
  end
  local iniciado, revisao = pcall(function()
    return exports.vhub_conce:iniciarManutencaoVeicular(context.plate, context.net_id, lock)
  end)
  if not iniciado or not revisao then
    Core.releaseLock(src, context.plate, lock)
    Core.notify(src, 'Barreira física indisponível.', 'error')
    TriggerClientEvent(E.MEC_CONFIRM, src, context.plate, false, nil, context.net_id, leaseId); return
  end
  reparos[lock] = context
  local finalizado = false
  local function finish(ok, applyPhysical)
    if finalizado then return end
    finalizado = true
    reparos[lock] = nil
    pcall(function() exports.vhub_conce:encerrarManutencaoVeicular(context.plate, lock) end)
    Core.releaseLock(src, context.plate, lock)
    TriggerClientEvent(E.MEC_CONFIRM, src, context.plate, ok == true,
      ok == true and applyPhysical ~= false and repairType or nil, context.net_id, leaseId)
  end

  local expirado = false
  SetTimeout(30000, function()
    -- Não solta exclusão enquanto SQL está em voo: timeout não cancela uma escrita.
    if not finalizado then expirado = true; Core.notify(src, 'Operação demorada; aguarde a confirmação.', 'warning') end
  end)

  local state = Core.getVehicleState(context.plate)
  if not state then Core.notify(src, 'Prontuário indisponível.', 'error'); return finish(false) end
  local inspecionado, atual = fisica(context, lock .. ':inspect', 'inspect')
  if not inspecionado or not atual or not Core.lockValid(context, lock) then
    Core.notify(src, 'Sem controle físico do veículo. Tente novamente.', 'error'); return finish(false)
  end
  -- Health é lido da réplica do servidor. Apenas dano estrutural vem do owner validado.
  local engine = GetVehicleEngineHealth(context.entity)
  local body = GetVehicleBodyHealth(context.entity)
  state = { engine_health = math.min(tonumber(state.engine_health) or engine, engine),
    body_health = math.min(tonumber(state.body_health) or body, body), damage = U.danoFisico(atual.damage) }
  local patch, cost, invalidMessage, noOp = repairPatch(state, repairType)
  if not patch then Core.notify(src, invalidMessage, 'error'); return finish(false) end
  local before = { engine_health = state.engine_health, body_health = state.body_health, damage = state.damage }
  local material = not noOp and REPAIR_ITEMS[repairType] or nil
  local usaMaterial = material and possuiMaterial(src, material) or false
  local paymentPayload = { patch = patch, material = usaMaterial and material or false }

  local paid, operationId, paymentErr, replayed, charged, operation = Core.commitPayment(context,
    'repair_' .. repairType, requestId, usaMaterial and 0 or cost, paymentPayload, before, patch)
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
  if noOp then
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch, 'recovered_applied')
    Core.notify(src, invalidMessage or 'Reparo já aplicado.', 'info')
    return finish(true, false)
  end

  local materialConsumido = false
  if usaMaterial then
    if not consumirMaterial(src, material) then
      Core.compensatePayment(operationId, replayed, charged)
      Core.notify(src, 'Material indisponível. Nenhum reparo aplicado.', 'error')
      return finish(false)
    end
    materialConsumido = true
  end

  local function compensarAntesDaFisica()
    if materialConsumido and not devolverMaterial(src, material) then
      Core.log(context.plate, 'mec_repair_material_refund_failed', context.char_id,
        { item = material, operation_id = operationId })
    end
    return Core.compensatePayment(operationId, replayed, charged)
  end

  if expirado or not Core.lockValid(context, lock) or not Core.refreshOperation(operationId)
      or expirado or not Core.lockValid(context, lock) then
    local compensated, compensation = compensarAntesDaFisica()
    Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch,
      'lease_lost_' .. compensation)
    Core.notify(src, compensated and 'Sessão encerrada. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.', 'error')
    return finish(false)
  end

  local aplicado = fisica(context, lock .. ':apply', repairType)
  if aplicado ~= true then
    -- Reenvio idempotente cobre perda de ACK/migração do owner sem nova cobrança.
    aplicado = fisica(context, lock .. ':retry', repairType)
  end
  if aplicado == true and (repairType == 'engine' or repairType == 'body') then
    local prazo = GetGameTimer() + 1000
    local function confirmadoNaReplica()
      if not DoesEntityExist(context.entity) then return false end
      return (repairType == 'engine' and GetVehicleEngineHealth(context.entity)
        or GetVehicleBodyHealth(context.entity)) >= 995.0
    end
    while not confirmadoNaReplica() and GetGameTimer() < prazo do Citizen.Wait(50) end
    if not confirmadoNaReplica() then aplicado = nil end
  end
  if aplicado ~= true then
    -- Recusa/ACK do cliente não prova ausência de aplicação: nunca estornar depois do RPC.
    Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch, 'physical_unknown')
    Core.notify(src, 'Confirmação física perdida. Operação retida para reconciliação.', 'error')
    return finish(false)
  end

  -- Primeiro confirma a física; depois persiste, ainda sob a barreira de telemetria.
  local persistir = {}
  for chave, valor in pairs(patch) do persistir[chave] = valor end
  persistir._repair_operation_id = operationId
  local salvo = Core.saveVehicleState(context.plate, persistir, 'repair')
  if not salvo then salvo = Core.saveVehicleState(context.plate, persistir, 'repair') end
  if not salvo then
    Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch, 'physical_applied_save_failed')
    Core.notify(src, 'Reparo físico aplicado; persistência em reconciliação.', 'error')
    return finish(false)
  end

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'repair_' .. repairType, operationId, before, patch,
    replayed and 'replayed' or 'committed')
  Core.log(context.plate, 'mec_repair_' .. repairType, context.char_id,
    { cost = cost, item = usaMaterial and material or nil, operation_id = operationId })
  Core.notify(src, usaMaterial and ('Reparo concluído. %s utilizado.'):format(material)
    or ('Reparo concluído. R$ %d cobrados.'):format(cost), 'success')
  finish(true)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  for lock, contexto in pairs(reparos) do
    pcall(function() exports.vhub_conce:encerrarManutencaoVeicular(contexto.plate, lock) end)
  end
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
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, 'tow', nil, leaseId); return
  end

  local context, lock, why = Core.beginMutation(src, 'mec', leaseId)
  if not context then
    Core.notify(src, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.', 'error')
    TriggerClientEvent(E.MEC_CONFIRM, src, nil, false, 'tow', nil, leaseId); return
  end
  local function finish(ok)
    Core.releaseLock(src, context.plate, lock)
    TriggerClientEvent(E.MEC_CONFIRM, src, context.plate, ok == true, 'tow', context.net_id, leaseId)
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
