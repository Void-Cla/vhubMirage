-- client/oficina.lua — L2 HAL: integração da NUI da oficina (modelo de PEÇAS, ADR #82 F2.3).
-- Install por part_id do catálogo (server-authoritative). O visual GTA da peça persiste em
-- customization.mods e reaparece no respawn (garage re-aplica) — sem preview efêmero client.
---@diagnostic disable: undefined-global

local E   = VHubCustom.E


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
  local alloc = type(data.alloc) == 'table'  and data.alloc or nil
  local service = VHubCustom.service
  if service and service.domain == 'oficina' and alloc then
    TriggerServerEvent(E.OFICINA_RECALIBRATE, service.lease_id, VHubCustom.nextRequestId(), alloc)
  end
  cb('ok')
end)

-- NUI → pede prévia de score/tier para o alloc em rascunho (não persiste nada)
RegisterNUICallback('oficina:previewCalibrar', function(data, cb)
  local alloc = type(data.alloc) == 'table'  and data.alloc or nil
  local service = VHubCustom.service
  if service and service.domain == 'oficina' and alloc then
    TriggerServerEvent(E.OFICINA_PREVIEW, service.lease_id, alloc)
  end
  cb('ok')
end)

-- NUI → instalar kit nitro (oficina cobra; vhub_nitro escreve o estado na placa — decisão #29)
RegisterNUICallback('oficina:instalarKitNitro', function(data, cb)
  local service = VHubCustom.service
  if service and service.domain == 'oficina' then
    TriggerServerEvent(E.OFICINA_NITRO_KIT, service.lease_id, VHubCustom.nextRequestId())
  end
  cb('ok')
end)

-- NUI → instalar PEÇA de engenharia por part_id do catálogo (ADR #82 F2.3). Server valida no
-- catálogo, cobra, toma item (se houver) e grava customization.parts (fonte única). A NUI NÃO é
-- autoridade — só dispara a intenção; o resultado autoritativo volta em OFICINA_INSTALL_PART_OK.
RegisterNUICallback('oficina:instalarParte', function(data, cb)
  local partId  = type(data.part_id) == 'string' and data.part_id or ''
  local service = VHubCustom.service
  if partId ~= '' and service and service.domain == 'oficina' then
    TriggerServerEvent(E.OFICINA_INSTALL_PART, service.lease_id, VHubCustom.nextRequestId(), partId)
  end
  cb('ok')
end)

-- NUI → remover PEÇA instalada (ADR #85 F2.5-A). Server valida posse do slot e reverte a peça +
-- projeção GTA/capability na mesma transação; resultado autoritativo volta em OFICINA_REMOVE_PART_OK.
RegisterNUICallback('oficina:removerParte', function(data, cb)
  local partId  = type(data.part_id) == 'string' and data.part_id or ''
  local service = VHubCustom.service
  if partId ~= '' and service and service.domain == 'oficina' then
    TriggerServerEvent(E.OFICINA_REMOVE_PART, service.lease_id, VHubCustom.nextRequestId(), partId)
  end
  cb('ok')
end)


-- ============================================================
-- RESPOSTA DO SERVIDOR
-- ============================================================
-- (OFICINA_CONFIRM/preview de stage REMOVIDOS — ADR #82 F2.3: o install é por PEÇA
--  server-authoritative; o visual GTA persiste em customization.mods e reaparece no respawn.
--  O handler OFICINA_TUNE segue no servidor em deprecação R15, sem consumidor client.)

-- resultado da redistribuição autorizada pela oficina; a NUI permanece aberta
RegisterNetEvent(E.OFICINA_RECALIBRATE_OK)
AddEventHandler(E.OFICINA_RECALIBRATE_OK, function(ok, msg, sheet)
  if not VHubCustom.inMenu then return end
  if msg and msg ~= '' then VHubCustom.notify(msg, ok and 'success' or 'error') end
  SendNUIMessage({ action = 'recalibrarResultado', ok = ok == true, data = sheet })
end)

-- prévia de ficha hipotética (alloc em rascunho) — sheet pode vir nil se inválido
RegisterNetEvent(E.OFICINA_PREVIEW_OK)
AddEventHandler(E.OFICINA_PREVIEW_OK, function(sheet)
  if not VHubCustom.inMenu then return end
  SendNUIMessage({ action = 'previewCalibrarResultado', data = sheet })
end)

-- (oficina:aplicarHandling + OFICINA_HANDLING_OK REMOVIDOS — ADR #82: handling_ext era zumbi.)

-- resultado da instalação do kit nitro (oficina) — só notifica; NUI permanece aberta
RegisterNetEvent(E.OFICINA_NITRO_KIT_OK)
AddEventHandler(E.OFICINA_NITRO_KIT_OK, function(ok, msg)
  if msg and msg ~= '' then VHubCustom.notify(msg, ok and 'success' or 'error') end
  SendNUIMessage({ action = 'nitroKitResultado', ok = ok == true })
end)

-- resultado da instalação de PEÇA (ADR #82 F2.3) — NUI permanece aberta e re-renderiza com o
-- estado AUTORITATIVO devolvido (installed_parts + sheet fresca). Sem 2ª verdade local (A-04).
RegisterNetEvent(E.OFICINA_INSTALL_PART_OK)
AddEventHandler(E.OFICINA_INSTALL_PART_OK, function(ok, msg, fresh)
  if not VHubCustom.inMenu then return end
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
AddEventHandler(E.OFICINA_REMOVE_PART_OK, function(ok, msg, fresh)
  if not VHubCustom.inMenu then return end
  if msg and msg ~= '' then VHubCustom.notify(msg, ok and 'success' or 'error') end
  SendNUIMessage({
    action = 'removerParteResultado',
    ok     = ok == true,
    data   = type(fresh) == 'table' and fresh or nil,
  })
end)
