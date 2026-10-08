-- client/oficina.lua — L2 HAL: integração da NUI da oficina (modelo de PEÇAS, ADR #82 F2.3).
-- Install por part_id do catálogo (server-authoritative). O visual GTA da peça persiste em
-- customization.mods e reaparece no respawn (garage re-aplica) — sem preview efêmero client.
---@diagnostic disable: undefined-global

local E   = VHubCustom.E
local mutacao, preview = nil, nil

-- Projeção GTA confirmada pelo servidor, enviada ao owner (não somente ao cliente da NUI).
RegisterNetEvent(E.OFICINA_PROJECTION)
AddEventHandler(E.OFICINA_PROJECTION, function(netId, plate, revisao, patch)
  revisao = VHubCustom.U.integer(revisao, 0, 2147483647)
  if source ~= 65535 or not revisao or type(patch) ~= 'table' then return end
  Citizen.CreateThread(function()
    local prazo = GetGameTimer() + 2000
    local veh
    repeat
      veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
      if veh ~= 0 and DoesEntityExist(veh) then
        if VHubCustom.U.normalizePlate(GetVehicleNumberPlateText(veh)) ~= plate then return end
        local atual = VHubCustom.U.integer(Entity(veh).state[VHubCustom.BAG.TUNE_REVISION], 0, 2147483647) or 0
        if atual > revisao then return end
        if atual == revisao and NetworkHasControlOfEntity(veh) then break end
        NetworkRequestControlOfEntity(veh)
      end
      Citizen.Wait(50)
    until GetGameTimer() >= prazo
    if veh == 0 or not DoesEntityExist(veh) or not NetworkHasControlOfEntity(veh)
        or Entity(veh).state[VHubCustom.BAG.TUNE_REVISION] ~= revisao then return end
    SetVehicleModKit(veh, 0)
    for indice, nivel in pairs(type(patch.mods) == 'table' and patch.mods or {}) do
      local idx, valor = VHubCustom.U.integer(indice, 0, 49), VHubCustom.U.integer(nivel, -1, 5)
      if idx and valor and VHubCustom.cfg.performance_mods[idx] and idx ~= 18
          and (valor == -1 or valor < GetNumVehicleMods(veh, idx)) then SetVehicleMod(veh, idx, valor, false) end
    end
    if type(patch.turbo) == 'boolean' then ToggleVehicleMod(veh, 18, patch.turbo) end
  end)
end)

local function enviarMutacao(evento, payload, cb)
  local servico = VHubCustom.service
  if mutacao or not VHubCustom.inMenu or not servico or servico.domain ~= 'oficina' then
    cb({ ok = false }); return
  end
  mutacao = VHubCustom.nextRequestId()
  TriggerServerEvent(evento, servico.lease_id, mutacao, payload)
  cb({ ok = true })
end

local function respostaAtual(leaseId, requestId)
  local servico = VHubCustom.service
  if not VHubCustom.inMenu or not servico or servico.domain ~= 'oficina'
      or leaseId ~= servico.lease_id or requestId ~= mutacao then return false end
  mutacao = nil
  return true
end


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- monta e despacha a mensagem openOficina para o NUI com os dados do catálogo + ficha real
local function dispatchOpenOficina(veh, auth)
  local cap       = tonumber(auth.stage_cap) or 0
  local model     = GetEntityModel(veh)

  local nome      = auth.name or GetDisplayNameFromVehicleModel(model) or auth.plate
  local categoria = auth.category or '—'

  SendNUIMessage({
    action = 'openOficina',
    data   = {
      plate       = auth.plate,
      nome        = nome,
      categoria   = categoria,
      stage_cap   = cap,
      sheet       = auth.sheet,
      -- ADR #82: catálogo declarativo de peças de engenharia (famílias + peças + vetor de deltas).
      -- A NUI NÃO é autoridade: instalar peça passa por OFICINA_INSTALL_PART (server valida
      -- catálogo/cap/ownership/item/pagamento e grava customization.parts — fonte única).
      parts_catalog = VHubCustom.PartsCatalog and VHubCustom.PartsCatalog.forNUI() or nil,
      -- ADR #82 F2.3: ids das peças instaladas (server-authoritative) — mantido p/ compat.
      installed_parts = auth.installed_parts or {},
      -- ADR #85 D1: status honesto por peça (state/hint/replaces) — juízo único server-side.
      parts_status = auth.parts_status or {},
    },
  })

  SetNuiFocus(true, true)
  VHubCustom.inMenu = true
end

-- abre menu de oficina: pré-checa acesso no servidor antes de exibir o NUI
-- se o veículo não estiver no sistema, mostra notificação e não abre
function VHubCustom.openOficina(auth)
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then return end
  if VHubCustom.inMenu then return end
  if type(auth) ~= 'table' or not VHubCustom.service or VHubCustom.service.domain ~= 'oficina' then return end

  dispatchOpenOficina(veh, auth)
end

-- fecha NUI de oficina. Sem rollback de preview: o modelo de PEÇAS persiste server-side
-- (customization.parts/mods) e não altera o veículo até o server confirmar — nada a reverter.
function VHubCustom.closeOficina()
  mutacao, preview = nil, nil
  VHubCustom.inMenu = false
  VHubCustom.endService('oficina')
  SetNuiFocus(false, false)
  -- ADR #82 F2.2: fecha o capô que a interação de olho abriu (no-op se veio pelo fluxo antigo)
  if VHubCustom.closeEngineHood then VHubCustom.closeEngineHood() end
end


-- ============================================================
-- NUI CALLBACKS
-- ============================================================

-- NUI → fecha sem aplicar (botão Fechar ou ESC)
RegisterNUICallback('oficina:fechar', function(_, cb)
  VHubCustom.closeOficina()
  cb('ok')
end)

-- NUI → redistribui pontos livres (mesmo motor do vhub_vehcontrol, porta 'oficina' cobra
-- dinheiro em vez de consumir item — decisão #27, único handler RECALIBRATE no servidor)
RegisterNUICallback('oficina:recalibrar', function(data, cb)
  if type(data) ~= 'table' or type(data.alloc) ~= 'table' then cb({ ok = false }); return end
  enviarMutacao(E.OFICINA_RECALIBRATE, data.alloc, cb)
end)

-- NUI → pede prévia de score/tier para o alloc em rascunho (não persiste nada)
RegisterNUICallback('oficina:previewCalibrar', function(data, cb)
  local alloc = type(data) == 'table' and type(data.alloc) == 'table' and data.alloc or nil
  local service = VHubCustom.service
  if service and service.domain == 'oficina' and alloc then
    preview = VHubCustom.nextRequestId()
    TriggerServerEvent(E.OFICINA_PREVIEW, service.lease_id, alloc, preview)
  end
  cb('ok')
end)

-- NUI → instalar kit nitro (oficina cobra; vhub_nitro escreve o estado na placa — decisão #29)
RegisterNUICallback('oficina:instalarKitNitro', function(data, cb)
  enviarMutacao(E.OFICINA_NITRO_KIT, nil, cb)
end)

-- NUI → instalar PEÇA de engenharia por part_id do catálogo (ADR #82 F2.3). Server valida no
-- catálogo, cobra, toma item (se houver) e grava customization.parts (fonte única). A NUI NÃO é
-- autoridade — só dispara a intenção; o resultado autoritativo volta em OFICINA_INSTALL_PART_OK.
RegisterNUICallback('oficina:instalarParte', function(data, cb)
  local partId = type(data) == 'table' and type(data.part_id) == 'string' and data.part_id or ''
  if partId == '' then cb({ ok = false }); return end
  enviarMutacao(E.OFICINA_INSTALL_PART, partId, cb)
end)

-- NUI → remover PEÇA instalada (ADR #85 F2.5-A). Server valida posse do slot e reverte a peça +
-- projeção GTA/capability na mesma transação; resultado autoritativo volta em OFICINA_REMOVE_PART_OK.
RegisterNUICallback('oficina:removerParte', function(data, cb)
  local partId = type(data) == 'table' and type(data.part_id) == 'string' and data.part_id or ''
  if partId == '' then cb({ ok = false }); return end
  enviarMutacao(E.OFICINA_REMOVE_PART, partId, cb)
end)


-- ============================================================
-- RESPOSTA DO SERVIDOR
-- ============================================================
-- (OFICINA_CONFIRM/preview de stage REMOVIDOS — ADR #82 F2.3: o install é por PEÇA
--  server-authoritative; o visual GTA persiste em customization.mods e reaparece no respawn.
--  O handler OFICINA_TUNE segue no servidor em deprecação R15, sem consumidor client.)

-- resultado da redistribuição autorizada pela oficina; a NUI permanece aberta
RegisterNetEvent(E.OFICINA_RECALIBRATE_OK)
AddEventHandler(E.OFICINA_RECALIBRATE_OK, function(ok, msg, sheet, leaseId, requestId)
  if not respostaAtual(leaseId, requestId) then return end
  if msg and msg ~= '' then VHubCustom.notify(msg, ok and 'success' or 'error') end
  SendNUIMessage({ action = 'recalibrarResultado', ok = ok == true, data = sheet })
end)

-- prévia de ficha hipotética (alloc em rascunho) — sheet pode vir nil se inválido
RegisterNetEvent(E.OFICINA_PREVIEW_OK)
AddEventHandler(E.OFICINA_PREVIEW_OK, function(sheet, leaseId, previewId)
  local servico = VHubCustom.service
  if not VHubCustom.inMenu or not servico or servico.domain ~= 'oficina'
      or leaseId ~= servico.lease_id or previewId ~= preview then return end
  SendNUIMessage({ action = 'previewCalibrarResultado', data = sheet })
end)

-- (oficina:aplicarHandling + OFICINA_HANDLING_OK REMOVIDOS — ADR #82: handling_ext era zumbi.)

-- resultado da instalação do kit nitro (oficina) — só notifica; NUI permanece aberta
RegisterNetEvent(E.OFICINA_NITRO_KIT_OK)
AddEventHandler(E.OFICINA_NITRO_KIT_OK, function(ok, msg, leaseId, requestId)
  if not respostaAtual(leaseId, requestId) then return end
  if msg and msg ~= '' then VHubCustom.notify(msg, ok and 'success' or 'error') end
  SendNUIMessage({ action = 'nitroKitResultado', ok = ok == true })
end)

-- resultado da instalação de PEÇA (ADR #82 F2.3) — NUI permanece aberta e re-renderiza com o
-- estado AUTORITATIVO devolvido (installed_parts + sheet fresca). Sem 2ª verdade local (A-04).
RegisterNetEvent(E.OFICINA_INSTALL_PART_OK)
AddEventHandler(E.OFICINA_INSTALL_PART_OK, function(ok, msg, fresh, leaseId, requestId)
  if not respostaAtual(leaseId, requestId) then return end
  if msg and msg ~= '' then VHubCustom.notify(msg, ok and 'success' or 'error') end
  SendNUIMessage({
    action = 'instalarParteResultado',
    ok     = ok == true,
    data   = type(fresh) == 'table' and fresh or nil,
  })
end)

-- resultado da REMOÇÃO de peça (ADR #85 F2.5-A) — NUI permanece aberta e re-renderiza autoritativo
-- do estado fresco devolvido (installed_parts/parts_status + sheet). Mesma re-render do install (A-04).
RegisterNetEvent(E.OFICINA_REMOVE_PART_OK)
AddEventHandler(E.OFICINA_REMOVE_PART_OK, function(ok, msg, fresh, leaseId, requestId)
  if not respostaAtual(leaseId, requestId) then return end
  if msg and msg ~= '' then VHubCustom.notify(msg, ok and 'success' or 'error') end
  SendNUIMessage({
    action = 'removerParteResultado',
    ok     = ok == true,
    data   = type(fresh) == 'table' and fresh or nil,
  })
end)
