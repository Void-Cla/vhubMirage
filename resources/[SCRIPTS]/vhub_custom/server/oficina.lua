-- server/oficina.lua — tuning, calibração e kit de nitro sob lease física
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local CFG  = VHubCustom.cfg
local U    = VHubCustom.U
local E    = VHubCustom.E

local PERF_NAMES = {
  [11] = 'Motor', [12] = 'Freios', [13] = 'Câmbio',
  [15] = 'Suspensão', [16] = 'Blindagem', [18] = 'Turbo',
}
local PERF_PRICE_KEY = {
  [11] = 'engine_stage', [12] = 'brakes_stage', [13] = 'transmission_stage',
  [15] = 'suspension_stage', [16] = 'armor_stage', [18] = 'turbo',
}

local function vehicleSheet(plate)
  local ok, sheet = pcall(function() return exports.vhub_vehcontrol:getVehicleSheet(plate) end)
  return ok and sheet or nil
end

local function priceAt(index, stage)
  local value = CFG.prices[PERF_PRICE_KEY[index]]
  if index == 18 then return stage >= 1 and (tonumber(value) or 0) or 0 end
  return type(value) == 'table' and (tonumber(value[stage]) or 0) or 0
end

local function currentStage(customization, index)
  if index == 18 then return customization.turbo == true and 1 or 0 end
  local mods = type(customization.mods) == 'table' and customization.mods or {}
  return (tonumber(mods[index]) or tonumber(mods[tostring(index)]) or -1) + 1
end

RegisterNetEvent(E.OFICINA_PREVIEW)
AddEventHandler(E.OFICINA_PREVIEW, function(leaseId, draftAlloc)
  local src = source
  if not Core.rateOK(src, 'oficina_preview') or type(draftAlloc) ~= 'table' then return end
  local context = Core.validateLease(src, 'oficina', leaseId)
  if not context then return end
  local ok, sheet = pcall(function()
    return exports.vhub_vehcontrol:getVehicleSheetPreview(context.plate, draftAlloc)
  end)
  TriggerClientEvent(E.OFICINA_PREVIEW_OK, src, ok and sheet or nil)
end)

RegisterNetEvent(E.OFICINA_RECALIBRATE)
AddEventHandler(E.OFICINA_RECALIBRATE, function(leaseId, requestId, alloc)
  local src = source
  local function reply(ok, message, sheet)
    TriggerClientEvent(E.OFICINA_RECALIBRATE_OK, src, ok == true, message or '', sheet)
  end
  if not Core.rateOK(src, 'oficina_recal') then return reply(false, 'Aguarde um instante.') end
  if type(alloc) ~= 'table' then return reply(false, 'Distribuição inválida.') end

  local context, lock, why = Core.beginMutation(src, 'oficina', leaseId)
  if not context then return reply(false, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.') end
  local function finish(ok, message, sheet)
    Core.releaseLock(src, context.plate, lock)
    reply(ok, message, sheet)
  end

  local reserved, reservation = pcall(function()
    return exports.vhub_vehcontrol:reserveWorkshopRecalibration(src, context.plate, alloc)
  end)
  if not reserved or type(reservation) ~= 'table' or reservation.ok ~= true
      or type(reservation.token) ~= 'string' or type(reservation.alloc) ~= 'table' then
    return finish(false, (type(reservation) == 'table' and reservation.msg)
      or 'Falha ao reservar a calibração.')
  end
  local reservationToken, before, cleanAlloc = reservation.token, reservation.before, reservation.alloc
  local function cancelReservation()
    pcall(function() return exports.vhub_vehcontrol:cancelWorkshopRecalibration(src, reservationToken) end)
  end
  local alreadyApplied = reservation.replayed == true
  local cost = alreadyApplied and 0 or CFG.prices.recalibration
  local after = { customization = { handling = cleanAlloc } }
  local paid, operationId, paymentErr, replayed, charged, operation =
    Core.commitPayment(context, 'handling', requestId, cost, cleanAlloc,
      { customization = { handling = before } }, after)
  if not paid then
    cancelReservation()
    return finish(false, paymentErr == 'insufficient' and ('Saldo insuficiente. Custo: R$ %d.'):format(cost)
      or 'Falha ao processar pagamento.')
  end

  if replayed then
    cancelReservation()
    return finish(true, 'Operação já concluída.', vehicleSheet(context.plate))
  end
  cost = tonumber(operation and operation.amount) or cost
  if alreadyApplied then
    cancelReservation()
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'handling', operationId, before, cleanAlloc, 'recovered_applied')
    return finish(true, 'Calibração já aplicada.', vehicleSheet(context.plate))
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    cancelReservation()
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'handling', operationId, before, cleanAlloc, 'lease_lost_' .. compensation)
    return finish(false, compensated and 'Sessao encerrada. Valor estornado.'
      or 'Falha critica. Operacao em reconciliacao.')
  end

  local called, result = pcall(function()
    return exports.vhub_vehcontrol:commitWorkshopRecalibration(src, reservationToken)
  end)
  if not called or type(result) ~= 'table' or result.ok ~= true then
    cancelReservation()
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'handling', operationId, before, cleanAlloc, 'save_failed_' .. compensation)
    return finish(false, compensated and ((type(result) == 'table' and result.msg)
      or 'Falha ao salvar. Valor estornado.') or 'Falha critica. Operacao em reconciliacao.')
  end

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'handling', operationId, before, cleanAlloc,
    replayed and 'replayed' or 'committed')
  Core.log(context.plate, 'oficina_handling', context.char_id, { cost = cost, operation_id = operationId })
  finish(true, 'Veículo recalibrado!', result.sheet)
end)

RegisterNetEvent(E.OFICINA_NITRO_KIT)
AddEventHandler(E.OFICINA_NITRO_KIT, function(leaseId, requestId)
  local src = source
  local function reply(ok, message)
    TriggerClientEvent(E.OFICINA_NITRO_KIT_OK, src, ok == true, message or '')
  end
  if not Core.rateOK(src, 'oficina_nitro') then return reply(false, 'Aguarde um instante.') end

  local context, lock, why = Core.beginMutation(src, 'oficina', leaseId)
  if not context then return reply(false, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.') end
  local function finish(ok, message)
    Core.releaseLock(src, context.plate, lock)
    reply(ok, message)
  end

  local current = VHubCustom.nitroGetInternal(context.plate)
  local alreadyApplied = type(current) == 'table' and current.kit == true
  local cost = alreadyApplied and 0 or CFG.prices.nitro_kit
  local paid, operationId, paymentErr, replayed, charged, operation = Core.commitPayment(context,
    'nitro_kit', requestId, cost, { kit = true }, current, { kit = true })
  if not paid then
    return finish(false, paymentErr == 'insufficient' and ('Saldo insuficiente. Custo: R$ %d.'):format(cost)
      or 'Falha ao processar pagamento.')
  end

  if replayed then
    return finish(true, 'Operação já concluída.')
  end
  cost = tonumber(operation and operation.amount) or cost
  if alreadyApplied then
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'nitro_kit', operationId, current, { kit = true }, 'recovered_applied')
    return finish(true, 'Kit de nitro já instalado.')
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'nitro_kit', operationId, current, { kit = true },
      'lease_lost_' .. compensation)
    return finish(false, compensated and 'Sessao encerrada. Valor estornado.'
      or 'Falha critica. Operacao em reconciliacao.')
  end

  local called, installed = pcall(function() return VHubCustom.nitroInstallKitInternal(src, context.plate) end)
  if not called or installed ~= true then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'nitro_kit', operationId, current, { kit = true },
      'install_failed_' .. compensation)
    return finish(false, compensated and 'Falha ao instalar. Valor estornado.'
      or 'Falha critica. Operacao em reconciliacao.')
  end

  local after = VHubCustom.nitroGetInternal(context.plate)
  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'nitro_kit', operationId, current, after,
    replayed and 'replayed' or 'committed')
  Core.log(context.plate, 'oficina_nitro_kit', context.char_id, { cost = cost, operation_id = operationId })
  finish(true, ('Kit de nitro instalado. R$ %d cobrados.'):format(cost))
end)

-- ⚠️ DEPRECADO (ADR #82, R15): OFICINA_TUNE (stage escalar dos mods GTA) será substituído pelas
-- PEÇAS de engenharia (parts_catalog + OFICINA_INSTALL_PART) — mesmo domínio `mods`, um escritor.
-- Mantido funcional por 1 versão (deprecation path); deleção na FASE 3. Warn one-shot no boot.
local _tune_deprecation_warned = false
RegisterNetEvent(E.OFICINA_TUNE)
AddEventHandler(E.OFICINA_TUNE, function(leaseId, requestId, proposedMods)
  local src = source
  if not _tune_deprecation_warned then
    _tune_deprecation_warned = true
    VHubCustom.log('[DEPRECADO ADR #82] OFICINA_TUNE — migre p/ peças de engenharia (OFICINA_INSTALL_PART); deleção na FASE 3.')
  end
  if not Core.rateOK(src, 'oficina_tune') then
    Core.notify(src, 'Aguarde antes de aplicar outro tuning.', 'error')
    TriggerClientEvent(E.OFICINA_CONFIRM, src, nil, false, nil, nil); return
  end

  local context, lock, why = Core.beginMutation(src, 'oficina', leaseId)
  if not context then
    Core.notify(src, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.', 'error')
    TriggerClientEvent(E.OFICINA_CONFIRM, src, nil, false, nil, nil); return
  end
  local function finish(ok, mods)
    Core.releaseLock(src, context.plate, lock)
    TriggerClientEvent(E.OFICINA_CONFIRM, src, context.plate, ok == true, mods, context.net_id)
  end

  local clean = U.sanitizeMods(proposedMods, CFG.performance_mods, 3)
  if not clean or not next(clean) then Core.notify(src, 'Nenhum upgrade válido.', 'error'); return finish(false) end
  local sheet = vehicleSheet(context.plate)
  local cap = Core.stageCap(context.vehicle, sheet)
  if cap <= 0 then Core.notify(src, 'Este veículo não aceita tuning de performance.', 'error'); return finish(false) end
  for index, level in pairs(clean) do
    if level < 0 or level > cap then
      Core.notify(src, ('%s excede o stage máximo %d.'):format(PERF_NAMES[index] or 'Peça', cap), 'error')
      return finish(false)
    end
  end

  local state = Core.getVehicleState(context.plate)
  local customization = state and type(state.customization) == 'table' and state.customization or nil
  if not customization then Core.notify(src, 'Prontuário indisponível.', 'error'); return finish(false) end

  local before, cost, changed = {}, 0, false
  for index, level in pairs(clean) do
    local current = currentStage(customization, index)
    before[index] = current
    if level ~= current then changed = true end
    if level > current then cost = cost + math.max(0, priceAt(index, level) - priceAt(index, current)) end
  end
  local gtaMods, patch = {}, {}
  for index, stage in pairs(clean) do if index ~= 18 then gtaMods[index] = stage - 1 end end
  if next(gtaMods) then patch.mods = gtaMods end
  if clean[18] ~= nil then patch.turbo = clean[18] >= 1 end
  local paid, operationId, paymentErr, replayed, charged, operation =
    Core.commitPayment(context, 'tune', requestId, changed and cost or 0, clean,
      { customization = { mods = before } }, { customization = patch })
  if not paid then
    Core.notify(src, paymentErr == 'insufficient' and ('Saldo insuficiente. Custo: R$ %d.'):format(cost)
      or 'Falha ao processar pagamento.', 'error')
    return finish(false)
  end

  if replayed then
    Core.notify(src, 'Operação já concluída.', 'info')
    return finish(true)
  end
  cost = tonumber(operation and operation.amount) or cost
  if not changed then
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'tune', operationId, before, clean, 'recovered_applied')
    Core.notify(src, 'Tuning já aplicado.', 'info')
    return finish(true)
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'tune', operationId, before, clean, 'lease_lost_' .. compensation)
    Core.notify(src, compensated and 'Sessao encerrada. Valor estornado.'
      or 'Falha critica. Operacao em reconciliacao.', 'error')
    return finish(false)
  end
  if not Core.saveVehicleState(context.plate, { customization = patch }, 'tune') then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'tune', operationId, before, clean, 'save_failed_' .. compensation)
    Core.notify(src, compensated and 'Falha ao salvar. Valor estornado.'
      or 'Falha critica. Operacao em reconciliacao.', 'error')
    return finish(false)
  end

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'tune', operationId, before, clean,
    replayed and 'replayed' or 'committed')
  Core.log(context.plate, 'oficina_tune', context.char_id,
    { cost = cost, cap = cap, operation_id = operationId })
  Core.notify(src, ('Tuning aplicado. R$ %d cobrados.'):format(cost), 'success')
  finish(true, clean)
end)


-- ============================================================
-- PEÇA DE INVENTÁRIO → DESEMPENHO (FASE 3 ADR #81)
-- ============================================================
-- Mapa fechado: item_id → {index GTA, stage}. Escritor: vhub_custom (L-13).
-- A oficina consome o item via takeItem e aplica customization.mods (Doutrina da Placa).
-- skillApplyHandling PERMANECE false — peça altera stage GTA, não handling runtime (ADR #81).

-- ⚠️ DEPRECADO (ADR #82 F2.1, R15): PART_MAP legado (itemId de inventário → stage GTA). O install
-- agora opera por part_id do parts_catalog (fonte única = customization.parts). Mantido só como
-- TRADUTOR de compat por 1 versão: quem tiver item antigo no bolso ainda instala. Deleção na F3.
-- NB: o handler antigo passava action='part_'..itemId a commitPayment, que NÃO existe em ACTION_CODE
-- → sempre 'invalid_request'. Ou seja, o install legado nunca chegou a persistir. A versão nova usa
-- action='tune' (válido) + fingerprint por part_id — primeiro caminho de install que de fato grava.
local PART_MAP_LEGACY = {
  ['part_engine_stage2']       = 'engine_aspirado',
  ['part_engine_stage3']       = 'engine_turbo',
  ['part_brakes_stage2']       = 'brakes_sport',
  ['part_brakes_stage3']       = 'brakes_race',
  ['part_transmission_stage2'] = 'transmission_sport',
  ['part_transmission_stage3'] = 'transmission_race',
  ['part_suspension_stage2']   = 'suspension_coilover',
  ['part_suspension_stage3']   = 'suspension_race',
}
local _partmap_deprecation_warned = false

-- resolve o id recebido do cliente → id canônico do catálogo (aplica shim legado 1x c/ warn)
local function resolveCatalogId(id)
  local cat = VHubCustom.PartsCatalog
  if cat and cat.get(id) then return id end                 -- já é id do catálogo
  local mapped = PART_MAP_LEGACY[id]
  if mapped then
    if not _partmap_deprecation_warned then
      _partmap_deprecation_warned = true
      VHubCustom.log('[DEPRECADO ADR #82 F2.1] itemId legado no install de peça — migre p/ part_id do catálogo; deleção na F3.')
    end
    return mapped
  end
  return nil
end

-- snapshot AUTORITATIVO pós-install/remove p/ a NUI re-renderizar sem 2ª verdade local (A-04):
-- ids instalados + STATUS honesto por peça (mesmo juízo do auth) + ficha derivada fresca (sheet.eng).
local function freshState(src, context)
  local plate = context.plate
  local st; pcall(function() st = Core.getVehicleState(plate) end)
  local cust = (st and type(st.customization) == 'table') and st.customization or {}
  local curParts = type(cust.parts) == 'table' and cust.parts or {}
  local installed = {}
  for id, v in pairs(curParts) do if v ~= nil and v ~= false then installed[id] = true end end
  local sheet; pcall(function() sheet = exports.vhub_vehcontrol:getVehicleSheet(plate) end)
  sheet = type(sheet) == 'table' and sheet or nil
  local cap = Core.stageCap(context.vehicle, sheet)
  return {
    installed_parts = installed,
    parts_status = Core.computePartsStatus(src, cap, curParts),
    sheet = sheet,
  }
end

-- mensagem honesta por estado de compatibilidade (ADR #85 D1) — o server é o juiz; a NUI só ecoa.
local function installRejectMsg(state, part)
  local name = part.name or 'Peça'
  if state == 'already_installed' then return ('%s já está instalada.'):format(name) end
  if state == 'missing_item'      then return 'Você não possui esta peça.' end
  if state == 'conflict'          then return ('%s é incompatível com uma peça já instalada.'):format(name) end
  if state == 'requires_missing'  then return ('%s exige outra peça instalada antes.'):format(name) end
  return 'Não foi possível instalar esta peça.'
end

RegisterNetEvent(E.OFICINA_INSTALL_PART)
AddEventHandler(E.OFICINA_INSTALL_PART, function(leaseId, requestId, partId)
  local src = source
  local function reply(ok, message, fresh)
    TriggerClientEvent(E.OFICINA_INSTALL_PART_OK, src, ok == true, message or '', fresh)
  end
  if not Core.rateOK(src, 'oficina_install_part') then return reply(false, 'Aguarde um instante.') end
  if type(partId) ~= 'string' then return reply(false, 'Peça inválida.') end

  -- whitelist fechada: só id do catálogo (ou item legado traduzido) entra
  local canonId = resolveCatalogId(partId)
  local part = canonId and VHubCustom.PartsCatalog.get(canonId) or nil
  if not part then return reply(false, 'Peça desconhecida.') end

  local context, lock, why = Core.beginMutation(src, 'oficina', leaseId)
  if not context then return reply(false, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.') end
  local function finish(ok, message, fresh)
    Core.releaseLock(src, context.plate, lock)
    reply(ok, message, fresh)
  end

  local state = Core.getVehicleState(context.plate)
  local customization = state and type(state.customization) == 'table' and state.customization or nil
  if not customization then return finish(false, 'Prontuário indisponível.') end
  local curParts = type(customization.parts) == 'table' and customization.parts or {}
  local gtaMod   = type(part.gta_mod) == 'table' and part.gta_mod or nil
  local needItem = type(part.item) == 'string' and part.item or nil

  -- ADR #85 D1: o GATE agora é COMPATIBILIDADE (família/conflito/dependência/item/já-instalada),
  -- NÃO mais um teto de stage. `Core.stageCap` continua vivo, mas rebaixado a `hint` não-bloqueante
  -- (o veículo aceita a peça; o DNA/classe só avisa quando ela é agressiva p/ o chassi). O status
  -- é o MESMO juízo que o payload de auth (init.lua) devolve à NUI — fonte única (Core.resolvePartStatus).
  local cap     = Core.stageCap(context.vehicle, vehicleSheet(context.plate))
  local hasItem = function(it)
    local ok, has = pcall(function() return exports.vhub_inventory:hasItem(src, it, 1) == true end)
    return ok and has == true
  end
  local status = Core.resolvePartStatus(part, curParts, cap, hasItem)
  if status.state ~= 'ok' then return finish(false, installRejectMsg(status.state, part)) end

  -- PATCH ATÔMICO (parts = fonte única; mods/turbo/drift_capable derivados NA MESMA transação):
  --  - parts[canonId]=true                        → a peça instalada
  --  - parts[substituída]=false p/ cada replaces  → libera o slot da família (merge esparso)
  --  - mods[idx]=stage-1 OU turbo=bool            → projeção GTA (stage 0 = revert: mods[idx]=-1)
  --  - drift_capable                              → liga se a peça habilita; DESLIGA se substituiu
  --                                                 quem habilitava (ex.: trocar hidráulico→profissional)
  local partsPatch = { [canonId] = true }
  local newHasDrift, replacedHadDrift = false, false
  if type(part.capabilities) == 'table' then
    for _, c in ipairs(part.capabilities) do if c == 'drift' then newHasDrift = true end end
  end
  if type(part.replaces) == 'table' then
    for _, rid in ipairs(part.replaces) do
      partsPatch[rid] = false
      local rp = VHubCustom.PartsCatalog.get(rid)
      if rp and type(rp.capabilities) == 'table' then
        for _, c in ipairs(rp.capabilities) do if c == 'drift' then replacedHadDrift = true end end
      end
    end
  end
  local patch = { parts = partsPatch }
  if gtaMod then
    local idx   = tonumber(gtaMod.index)
    local stage = tonumber(gtaMod.stage) or 1
    if idx == 18 then
      patch.turbo = stage >= 1                 -- stage 0 (Aspiração Natural) = turbo OFF
    elseif idx then
      patch.mods = { [idx] = stage - 1 }       -- GTA level = stage-1 (stage 0 → -1 = stock)
    end
  end
  if newHasDrift then patch.drift_capable = true
  elseif replacedHadDrift then patch.drift_capable = false end

  local before = { parts = curParts, mods = customization.mods, turbo = customization.turbo }

  -- action='tune' (válido em ACTION_CODE); fingerprint por part_id garante operationId único por peça
  local paid, operationId, paymentErr, replayed, charged =
    Core.commitPayment(context, 'tune', requestId, tonumber(part.price) or 0,
      { part = canonId }, { customization = before }, { customization = patch })
  if not paid then
    return finish(false, paymentErr == 'insufficient' and 'Saldo insuficiente.' or 'Falha ao processar.')
  end

  if replayed then
    return finish(true, ('%s já instalada.'):format(part.name or 'Peça'))
  end

  -- tomar item só se a peça exige (estorna em qualquer falha posterior)
  local took = not needItem
  if needItem then
    pcall(function() took = exports.vhub_inventory:takeItem(src, needItem, 1) == true end)
    if not took then
      Core.compensatePayment(operationId, false, charged)
      return finish(false, 'Falha ao consumir a peça do inventário.')
    end
  end

  local function refund()
    if needItem then pcall(function() exports.vhub_inventory:giveItem(src, needItem, 1) end) end
    Core.compensatePayment(operationId, false, charged)
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    refund()
    Core.auditVehicle(context, 'tune', operationId, before, patch, 'lease_lost')
    return finish(false, 'Sessão encerrada. Peça devolvida.')
  end

  if not Core.saveVehicleState(context.plate, { customization = patch }, 'tune') then
    refund()
    Core.auditVehicle(context, 'tune', operationId, before, patch, 'save_failed')
    return finish(false, 'Falha ao salvar. Peça devolvida.')
  end

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'tune', operationId, before, patch, 'committed')
  Core.log(context.plate, 'oficina_install_part', context.char_id,
    { part = canonId, family = part.family, operation_id = operationId })

  -- ADR #82 F2.1: push live da ficha recomposta ao motorista (traz sheet.eng novo → o applier
  -- da Camada A reaplica a base sem esperar sair/entrar). O vehcontrol filtra por placa: só
  -- afeta o carro se este src o dirige. Best-effort (pcall): falha de push não desfaz a compra.
  pcall(function() exports.vhub_vehcontrol:refreshSheet(context.plate, src) end)

  -- devolve estado fresco (peças + status + ficha) p/ a NUI re-renderizar autoritativo (A-04)
  finish(true, ('%s instalada com sucesso!'):format(part.name or 'Peça'), freshState(src, context))
end)


-- ============================================================
-- REMOVER PEÇA (ADR #85 F2.5-A — remoção como primeira classe)
-- ============================================================
-- Reverte customization.parts[id]=false + desfaz a projeção GTA/capability NA MESMA transação
-- (L-13, escritor único vhub_custom). Custo 0 e SEM devolução de item na F2.5-A (refund fora do
-- escopo — ADR #85 D2). Idempotente por fingerprint { remove=id } (operationId distinto do install).
RegisterNetEvent(E.OFICINA_REMOVE_PART)
AddEventHandler(E.OFICINA_REMOVE_PART, function(leaseId, requestId, partId)
  local src = source
  local function reply(ok, message, fresh)
    TriggerClientEvent(E.OFICINA_REMOVE_PART_OK, src, ok == true, message or '', fresh)
  end
  if not Core.rateOK(src, 'oficina_remove_part') then return reply(false, 'Aguarde um instante.') end
  if type(partId) ~= 'string' then return reply(false, 'Peça inválida.') end

  local canonId = resolveCatalogId(partId)
  local part = canonId and VHubCustom.PartsCatalog.get(canonId) or nil
  if not part then return reply(false, 'Peça desconhecida.') end

  local context, lock, why = Core.beginMutation(src, 'oficina', leaseId)
  if not context then return reply(false, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.') end
  local function finish(ok, message, fresh)
    Core.releaseLock(src, context.plate, lock)
    reply(ok, message, fresh)
  end

  local state = Core.getVehicleState(context.plate)
  local customization = state and type(state.customization) == 'table' and state.customization or nil
  if not customization then return finish(false, 'Prontuário indisponível.') end
  local curParts = type(customization.parts) == 'table' and customization.parts or {}
  if curParts[canonId] ~= true then
    return finish(false, ('%s não está instalada.'):format(part.name or 'Peça'))
  end

  -- PATCH REVERSO (mesma transação, L-13):
  --  - parts[canonId]=false  → merge esparso marca removido (não apaga a chave)
  --  - mods[idx]=-1 OU turbo=false → volta o mod GTA ao "original" (-1 é stock; 0 seria stage 1)
  --  - drift_capable=false   → se a peça habilitava a capability 'drift'
  local partsPatch = { [canonId] = false }
  local patch = { parts = partsPatch }
  local gtaMod = type(part.gta_mod) == 'table' and part.gta_mod or nil
  if gtaMod then
    local idx = tonumber(gtaMod.index)
    if idx == 18 then
      patch.turbo = false
    elseif idx then
      patch.mods = { [idx] = -1 }
    end
  end
  if type(part.capabilities) == 'table' then
    for _, capName in ipairs(part.capabilities) do
      if capName == 'drift' then patch.drift_capable = false end
    end
  end

  local before = { parts = curParts, mods = customization.mods, turbo = customization.turbo }

  -- custo 0; fingerprint { remove=canonId } → operationId distinto do install da mesma peça
  local paid, operationId, paymentErr, replayed, charged =
    Core.commitPayment(context, 'tune', requestId, 0,
      { remove = canonId }, { customization = before }, { customization = patch })
  if not paid then
    return finish(false, paymentErr == 'insufficient' and 'Saldo insuficiente.' or 'Falha ao processar.')
  end
  if replayed then
    return finish(true, ('%s já removida.'):format(part.name or 'Peça'))
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    Core.compensatePayment(operationId, false, charged)
    Core.auditVehicle(context, 'tune', operationId, before, patch, 'lease_lost')
    return finish(false, 'Sessão encerrada.')
  end

  if not Core.saveVehicleState(context.plate, { customization = patch }, 'tune') then
    Core.compensatePayment(operationId, false, charged)
    Core.auditVehicle(context, 'tune', operationId, before, patch, 'save_failed')
    return finish(false, 'Falha ao salvar.')
  end

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'tune', operationId, before, patch, 'committed')
  Core.log(context.plate, 'oficina_remove_part', context.char_id,
    { part = canonId, family = part.family, operation_id = operationId })

  pcall(function() exports.vhub_vehcontrol:refreshSheet(context.plate, src) end)
  finish(true, ('%s removida.'):format(part.name or 'Peça'), freshState(src, context))
end)


-- ============================================================
-- HANDLING LIVRE (handling_ext) — REMOVIDO (ADR #82, código zumbi L-15)
-- ============================================================
-- O handler OFICINA_HANDLING gravava customization.handling_ext via saveVehicleState('handling_ext'),
-- MAS `handling_ext` nunca esteve em CUST_KEYS (vhub_conce/vstate.lua) → sanitizeCustJson descartava
-- silenciosamente. Nunca funcionou. Os knobs de handling (freio de mão, direção, largada, rigidez)
-- passam a ser cobertos pelas PEÇAS de engenharia (parts_catalog) na Camada B (ADR #83, física
-- model-wide gated). Não há substituto físico na FASE 1 — a superfície zumbi apenas some.
