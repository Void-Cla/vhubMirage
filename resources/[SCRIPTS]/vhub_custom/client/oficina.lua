-- client/oficina.lua — L2 HAL: preview de stage de tuning e integração com NUI
-- Convenção de stage: 0=padrão/sem mod, 1/2/3=stages ativos.
-- Conversão: stage → GTA level = (stage - 1);  GTA level → stage = (level + 1).
---@diagnostic disable: undefined-global

local CFG = VHubCustom.cfg
local E   = VHubCustom.E

-- snapshot dos stages de performance antes do preview (para rollback)
local _snap_perf = nil

-- ficha real (vhub_vehcontrol) recebida junto da autorização, aguardando o fallback de catálogo
local _pendingSheet = nil


-- ============================================================
-- SNAPSHOT DE MODS DE PERFORMANCE (stage convention)
-- ============================================================

-- captura stages de performance do veículo atual (0=stock, 1/2/3=stage)
local function snapshotPerf(veh)
  if not DoesEntityExist(veh) or veh == 0 then return {} end
  local snap = {}
  for idx in pairs(CFG.performance_mods) do
    if idx == 18 then
      snap[idx] = IsToggleModOn(veh, 18) and 1 or 0
    else
      -- GetVehicleMod retorna -1 (stock) ou 0..N-1 (GTA level) → converte p/ stage
      snap[idx] = GetVehicleMod(veh, idx) + 1   -- -1→0, 0→1, 1→2, 2→3
    end
  end
  return snap
end

-- aplica snapshot de stages ao veículo (converte stage → GTA level)
local function applyPerfSnap(veh, snap)
  if not DoesEntityExist(veh) or veh == 0 then return end
  SetVehicleModKit(veh, 0)
  for idx, stage in pairs(snap) do
    if idx == 18 then
      ToggleVehicleMod(veh, 18, stage >= 1)
    else
      SetVehicleMod(veh, idx, stage - 1, false)  -- stage 0 → -1 (remove), 1 → 0, etc.
    end
  end
end


-- ============================================================
-- PREVIEW DE STAGE (efêmero, local)
-- ============================================================

-- aplica preview de tuning de performance no veículo local
function VHubCustom.previewTune(veh, mods)
  if not DoesEntityExist(veh) or veh == 0 then return end
  SetVehicleModKit(veh, 0)
  for idx, stage in pairs(mods) do
    if CFG.performance_mods[idx] then
      if idx == 18 then
        ToggleVehicleMod(veh, 18, stage >= 1)
      else
        SetVehicleMod(veh, idx, stage - 1, false)
      end
    end
  end
end


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- converte tabela de preços indexada por número em dict string-keyed
-- (previne confusão de 0-index no JS quando Lua envia como array msgpack)
local function priceDict(tbl)
  local out = {}
  if type(tbl) == 'table' then
    for k, v in pairs(tbl) do out[tostring(k)] = v end
  end
  return out
end

-- monta e despacha a mensagem openOficina para o NUI com os dados do catálogo + ficha real
local function dispatchOpenOficina(veh, plate, catEntry, sheet)
  local veh_class = GetVehicleClass(veh)
  local cap       = CFG.stage_cap_by_class[veh_class] or CFG.stage_cap_default
  local model     = GetEntityModel(veh)

  local nome      = catEntry.nome      or GetDisplayNameFromVehicleModel(model) or plate
  local categoria = catEntry.categoria or '—'

  local stages = {}
  for idx, stage in pairs(_snap_perf or {}) do
    stages[tostring(idx)] = stage
  end

  SendNUIMessage({
    action = 'openOficina',
    data   = {
      plate       = plate,
      nome        = nome,
      categoria   = categoria,
      classe_gta  = veh_class,
      stage_cap   = cap,
      sheet       = sheet,   -- ficha REAL (tier/score/budget/alloc/ranges) — vhub_vehcontrol é a fonte única
      stages      = stages,
      prices      = {
        engine_stage       = priceDict(CFG.prices.engine_stage),
        brakes_stage       = priceDict(CFG.prices.brakes_stage),
        transmission_stage = priceDict(CFG.prices.transmission_stage),
        suspension_stage   = priceDict(CFG.prices.suspension_stage),
        armor_stage        = priceDict(CFG.prices.armor_stage),
        turbo              = CFG.prices.turbo,
      },
    },
  })

  SetNuiFocus(true, true)
  VHubCustom.inMenu = true
end

-- abre menu de oficina: pré-checa acesso no servidor antes de exibir o NUI
-- se o veículo não estiver no sistema, mostra notificação e não abre
function VHubCustom.openOficina()
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then return end
  if VHubCustom.inMenu then return end

  -- normalização compatível com conce
  local plate = GetVehicleNumberPlateText(veh):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  _snap_perf = snapshotPerf(veh)

  TriggerServerEvent(E.OFICINA_AUTH, plate)
end

-- servidor autoriza (+ envia ficha real) → busca dados do catálogo e abre o NUI
RegisterNetEvent(E.OFICINA_AUTH_OK)
AddEventHandler(E.OFICINA_AUTH_OK, function(plate_sv, ok, err_msg, sheet)
  if not ok then
    _snap_perf = nil
    VHubCustom.notify(err_msg or 'Acesso negado.', 'error')
    return
  end

  local veh = VHubCustom.activeVeh
  if not veh or not DoesEntityExist(veh) or VHubCustom.inMenu then
    _snap_perf = nil; return
  end

  -- lookup no catálogo local (caminho quente) — só p/ nome/categoria visual, NUNCA stats
  local model    = GetEntityModel(veh)
  local dispName = string.lower(GetDisplayNameFromVehicleModel(model) or '')
  local catEntry = (VHubCustom.catalog or {})[dispName] or {}

  if catEntry.nome or catEntry.categoria then
    dispatchOpenOficina(veh, plate_sv, catEntry, sheet)
  else
    -- fallback: pede ao servidor via prontuário → catálogo (nome/categoria só)
    _pendingSheet = sheet
    TriggerServerEvent(E.REQ_VEH_DATA, plate_sv)
  end
end)

-- resposta do servidor com dados do catálogo por placa (fallback de lookup)
RegisterNetEvent(E.VEH_DATA)
AddEventHandler(E.VEH_DATA, function(plate_sv, data)
  local veh = VHubCustom.activeVeh
  if not veh or not DoesEntityExist(veh) or VHubCustom.inMenu then
    _snap_perf = nil; return
  end
  dispatchOpenOficina(veh, plate_sv, data or {}, _pendingSheet)
  _pendingSheet = nil
end)

-- fecha NUI de oficina (rollback visual quando não confirmado)
function VHubCustom.closeOficina(confirmed)
  if not confirmed then
    local veh = VHubCustom.activeVeh
    if veh and _snap_perf then applyPerfSnap(veh, _snap_perf) end
  end
  _snap_perf = nil
  VHubCustom.inMenu = false
  SetNuiFocus(false, false)
end


-- ============================================================
-- NUI CALLBACKS
-- ============================================================

-- NUI → fecha sem aplicar (botão Cancelar ou ESC)
RegisterNUICallback('oficina:fechar', function(_, cb)
  VHubCustom.closeOficina(false)
  cb('ok')
end)

-- NUI → envia seleção de stages ao servidor para validação e cobrança
RegisterNUICallback('oficina:aplicarTuning', function(data, cb)
  local plate  = type(data.plate)  == 'string' and data.plate  or ''
  local mods   = type(data.mods)   == 'table'  and data.mods   or {}
  local veh    = VHubCustom.activeVeh

  if VHubCustom.cfg.debug then
    local n = 0; for _ in pairs(mods) do n = n + 1 end
    VHubCustom.notify(('[DEBUG] NUI aplicarTuning: placa=%s mods=%d'):format(plate, n), 'info')
  end

  -- guarda de segurança: se veículo sumiu, fecha NUI imediatamente sem round-trip
  -- (sem isso a NUI ficaria presa com botões desabilitados até o timeout de 20s)
  if not plate or plate == '' or not DoesEntityExist(veh) or veh == 0 then
    if VHubCustom.cfg.debug then VHubCustom.notify('[DEBUG] veículo sumiu/placa vazia — abortou no client', 'error') end
    VHubCustom.closeOficina(false)
    SendNUIMessage({ action = 'fecharOficina' })
    cb({ ok = false })
    return
  end

  local veh_class = GetVehicleClass(veh)

  -- preview efêmero imediato: converte mods string-keyed → int-keyed
  local int_mods = {}
  for k, v in pairs(mods) do
    local idx = tonumber(k)
    if idx then int_mods[idx] = tonumber(v) or 0 end
  end
  VHubCustom.previewTune(veh, int_mods)

  if VHubCustom.cfg.debug then VHubCustom.notify('[DEBUG] enviando ao servidor (OFICINA_TUNE)...', 'info') end
  TriggerServerEvent(E.OFICINA_TUNE, plate, mods, veh_class)
  cb({ ok = true })
end)

-- NUI → redistribui pontos livres (mesmo motor do vhub_vehcontrol, porta 'oficina' cobra
-- dinheiro em vez de consumir item — decisão #27, único handler RECALIBRATE no servidor)
RegisterNUICallback('oficina:recalibrar', function(data, cb)
  local plate = type(data.plate) == 'string' and data.plate or ''
  local alloc = type(data.alloc) == 'table'  and data.alloc or nil
  if plate ~= '' and alloc then
    TriggerServerEvent('vhub_vehcontrol:recalibrate', plate, alloc, 'oficina')
  end
  cb('ok')
end)

-- NUI → pede prévia de score/tier para o alloc em rascunho (não persiste nada)
RegisterNUICallback('oficina:previewCalibrar', function(data, cb)
  local plate = type(data.plate) == 'string' and data.plate or ''
  local alloc = type(data.alloc) == 'table'  and data.alloc or nil
  if plate ~= '' and alloc then
    TriggerServerEvent(E.OFICINA_PREVIEW, plate, alloc)
  end
  cb('ok')
end)

-- NUI → instalar kit nitro (oficina cobra; vhub_nitro escreve o estado na placa — decisão #29)
RegisterNUICallback('oficina:instalarKitNitro', function(data, cb)
  local plate = type(data.plate) == 'string' and data.plate or ''
  if plate ~= '' then TriggerServerEvent(E.OFICINA_NITRO_KIT, plate) end
  cb('ok')
end)


-- ============================================================
-- RESPOSTA DO SERVIDOR
-- ============================================================

-- servidor confirma (ok=true) ou recusa (ok=false) o tuning
-- assinatura: (plate, ok, confirmedMods) — plate vem do servidor, não é usado no cliente
RegisterNetEvent(E.OFICINA_CONFIRM)
AddEventHandler(E.OFICINA_CONFIRM, function(_plate_sv, ok, confirmedMods)
  local veh = VHubCustom.activeVeh
  if not veh or not DoesEntityExist(veh) then
    VHubCustom.closeOficina(false)
    SendNUIMessage({ action = 'fecharOficina' })
    return
  end

  if ok and type(confirmedMods) == 'table' then
    -- converte chaves string (JSON) → int e aplica stages confirmados pelo servidor
    local int_mods = {}
    for k, v in pairs(confirmedMods) do
      local idx = tonumber(k)
      if idx then int_mods[idx] = tonumber(v) or 0 end
    end
    applyPerfSnap(veh, int_mods)
  else
    if _snap_perf then applyPerfSnap(veh, _snap_perf) end
  end

  VHubCustom.closeOficina(ok)
  SendNUIMessage({ action = 'fecharOficina' })
end)

-- resultado da redistribuição (porta 'oficina') — vem do vhub_vehcontrol, NUI permanece aberta
-- (diferente do tuning: redistribuir não altera peças instaladas, só realocação dos pontos livres)
RegisterNetEvent('vhub_vehcontrol:recalDone')
AddEventHandler('vhub_vehcontrol:recalDone', function(ok, msg, _kind, sheet)
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

-- resultado da instalação do kit nitro (oficina) — só notifica; NUI permanece aberta
RegisterNetEvent(E.OFICINA_NITRO_KIT_OK)
AddEventHandler(E.OFICINA_NITRO_KIT_OK, function(ok, msg)
  if msg and msg ~= '' then VHubCustom.notify(msg, ok and 'success' or 'error') end
  SendNUIMessage({ action = 'nitroKitResultado', ok = ok == true })
end)
