-- client/bennys.lua — L2 HAL: preview cosmético efêmero, câmera, coleta e rollback
-- Preview: aplica nativos localmente (sem persistência). Confirmar → envia intenção ao servidor.
-- Rollback: re-aplica estado salvo pelo servidor em caso de falha.
---@diagnostic disable: undefined-global

local CFG = VHubCustom.cfg
local E   = VHubCustom.E

-- snapshot do estado cosmético antes do preview (para rollback)
local _snapshot = nil
-- câmera de preview
local _cam = nil


-- ============================================================
-- CÂMERA DE PREVIEW (L2 HAL — destruída no cleanup)
-- ============================================================

local function startCam(veh)
  if _cam then return end
  if not DoesEntityExist(veh) or veh == 0 then return end
  _cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
  local pos = GetEntityCoords(veh)
  SetCamCoord(_cam, pos.x + 4.0, pos.y, pos.z + 1.5)
  PointCamAtEntity(_cam, veh, 0.0, 0.0, 0.0, true)
  SetCamFov(_cam, 60.0)
  SetCamActive(_cam, true)
  RenderScriptCams(true, true, 500, true, false)
end

local function stopCam()
  if not _cam then return end
  SetCamActive(_cam, false)
  RenderScriptCams(false, true, 500, true, false)
  DestroyCam(_cam, false)
  _cam = nil
end


-- ============================================================
-- SNAPSHOT DO ESTADO COSMÉTICO (para rollback em falha)
-- ============================================================

local function snapshotVeh(veh)
  if not DoesEntityExist(veh) or veh == 0 then return {} end
  local mods = {}
  for i = 0, 49 do mods[i] = GetVehicleMod(veh, i) end
  local p, s = GetVehicleColours(veh)
  local pearl, wheel = GetVehicleExtraColours(veh)
  local nr, ng, nb = GetVehicleNeonLightsColour(veh)
  local neons = {}
  for i = 0, 3 do neons[i] = IsVehicleNeonLightEnabled(veh, i) end
  return {
    mods        = mods,
    colours     = { p, s },
    extra_colours = { pearl, wheel },
    neons       = neons,
    neon_colour = { nr, ng, nb },
    window_tint = GetVehicleWindowTint(veh),
    wheel_type  = GetVehicleWheelType(veh),
    livery      = GetVehicleLivery(veh),
    smoke       = IsToggleModOn(veh, 20),
    xenon       = IsToggleModOn(veh, 22),
    -- turbo (18) NÃO é coletado: é chave exclusiva da oficina (performance)
  }
end

-- aplica snapshot (rollback ou confirmação final)
local function applySnapshot(veh, snap)
  if not DoesEntityExist(veh) or veh == 0 then return end
  SetVehicleModKit(veh, 0)
  if snap.mods then
    for i, lvl in pairs(snap.mods) do SetVehicleMod(veh, i, lvl, false) end
  end
  if snap.colours then SetVehicleColours(veh, snap.colours[1], snap.colours[2]) end
  if snap.extra_colours then SetVehicleExtraColours(veh, snap.extra_colours[1], snap.extra_colours[2]) end
  if snap.neons then
    for i, v in pairs(snap.neons) do SetVehicleNeonLightEnabled(veh, i, v) end
  end
  if snap.neon_colour then SetVehicleNeonLightsColour(veh, snap.neon_colour[1], snap.neon_colour[2], snap.neon_colour[3]) end
  if snap.window_tint ~= nil then SetVehicleWindowTint(veh, snap.window_tint) end
  if snap.wheel_type  ~= nil then SetVehicleWheelType(veh, snap.wheel_type) end
  if snap.livery      ~= nil then SetVehicleLivery(veh, snap.livery) end
  ToggleVehicleMod(veh, 20, snap.smoke  == true)
  ToggleVehicleMod(veh, 22, snap.xenon  == true)
  -- turbo (18) intocado no rollback do bennys: pertence à oficina
end


-- ============================================================
-- PREVIEW EFÊMERO (zero persistência — aplica no veh local)
-- ============================================================

-- aplica preview cosmético efêmero no veículo local
function VHubCustom.previewCosmetic(veh, patch)
  if not DoesEntityExist(veh) or veh == 0 then return end
  SetVehicleModKit(veh, 0)
  if patch.colours     then SetVehicleColours(veh, patch.colours[1], patch.colours[2]) end
  if patch.extra_colours then SetVehicleExtraColours(veh, patch.extra_colours[1], patch.extra_colours[2]) end
  if patch.neons then
    for i, v in pairs(patch.neons) do SetVehicleNeonLightEnabled(veh, i, v) end
  end
  if patch.neon_colour then SetVehicleNeonLightsColour(veh, patch.neon_colour[1], patch.neon_colour[2], patch.neon_colour[3]) end
  if patch.window_tint ~= nil then SetVehicleWindowTint(veh, patch.window_tint) end
  if patch.wheel_type  ~= nil then SetVehicleWheelType(veh, patch.wheel_type) end
  if patch.livery      ~= nil then SetVehicleLivery(veh, patch.livery) end
  if patch.smoke  ~= nil then ToggleVehicleMod(veh, 20, patch.smoke) end
  if patch.xenon  ~= nil then ToggleVehicleMod(veh, 22, patch.xenon) end
  -- turbo (18) não é aplicado pelo bennys: chave exclusiva da oficina
  if patch.mods then
    for idx, lvl in pairs(patch.mods) do
      -- só aplica cosméticos no preview (nunca performance)
      if CFG.cosmetic_mods[idx] then SetVehicleMod(veh, idx, lvl, false) end
    end
  end
end


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- converte tabela de preços indexada por número em dict string-keyed (msgpack-safe)
local function priceDict(tbl)
  local out = {}
  if type(tbl) == 'table' then
    for k, v in pairs(tbl) do out[tostring(k)] = v end
  end
  return out
end

-- abre o menu bennys para o veículo ativo na zona
function VHubCustom.openBennys()
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then return end
  if VHubCustom.inMenu then return end

  -- snapshot ANTES de qualquer preview
  _snapshot = snapshotVeh(veh)
  startCam(veh)
  VHubCustom.inMenu = true

  local plate = GetVehicleNumberPlateText(veh):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  local model = GetEntityModel(veh)

  local dispName = string.lower(GetDisplayNameFromVehicleModel(model) or '')
  local catEntry = (VHubCustom.catalog or {})[dispName] or {}

  SendNUIMessage({
    action = 'openBennys',
    data   = {
      plate     = plate,
      nome      = catEntry.nome or GetDisplayNameFromVehicleModel(model) or plate,
      categoria = catEntry.categoria or '—',
      prices    = priceDict(CFG.prices),
    },
  })

  SetNuiFocus(true, true)
end

-- fecha o menu (rollback visual se não confirmado)
function VHubCustom.closeBennys(confirmed)
  if not confirmed then
    local veh = VHubCustom.activeVeh
    if veh and _snapshot then applySnapshot(veh, _snapshot) end
  end
  stopCam()
  _snapshot = nil
  VHubCustom.inMenu = false
  SetNuiFocus(false, false)
end


-- ============================================================
-- HANDLERS DE RESPOSTA DO SERVIDOR
-- ============================================================

-- servidor confirma (ok=true) ou rejeita (ok=false) aplicação cosmética
RegisterNetEvent(E.BENNYS_CONFIRM)
AddEventHandler(E.BENNYS_CONFIRM, function(_, ok, custPatch)
  local veh = VHubCustom.activeVeh
  if not veh or not DoesEntityExist(veh) then
    VHubCustom.closeBennys(false)
    SendNUIMessage({ action = 'fecharBennys' })
    return
  end

  if ok and type(custPatch) == 'table' then
    -- aplica estado definitivo confirmado pelo servidor
    applySnapshot(veh, custPatch)
  else
    -- rollback para estado anterior
    if _snapshot then applySnapshot(veh, _snapshot) end
  end
  VHubCustom.closeBennys(ok)
  SendNUIMessage({ action = 'fecharBennys' })
end)


-- ============================================================
-- NUI CALLBACKS
-- ============================================================

-- NUI → fecha sem aplicar (botão Cancelar/✕ ou timeout de 20s)
RegisterNUICallback('bennys:fechar', function(_, cb)
  VHubCustom.closeBennys(false)
  cb('ok')
end)

-- NUI → aplica preview efêmero local (sem custo, sem persistência) a cada seleção
RegisterNUICallback('bennys:preview', function(patch, cb)
  local veh = VHubCustom.activeVeh
  if DoesEntityExist(veh) and veh ~= 0 and type(patch) == 'table' then
    VHubCustom.previewCosmetic(veh, patch)
  end
  cb('ok')
end)

-- NUI → envia patch final ao servidor para validação, cobrança e persistência
RegisterNUICallback('bennys:aplicar', function(data, cb)
  local plate   = type(data.plate)   == 'string' and data.plate   or ''
  local payload = type(data.payload) == 'table'  and data.payload or {}
  local veh     = VHubCustom.activeVeh

  if not plate or plate == '' or not DoesEntityExist(veh) or veh == 0 then
    VHubCustom.closeBennys(false)
    SendNUIMessage({ action = 'fecharBennys' })
    cb({ ok = false })
    return
  end

  TriggerServerEvent(E.BENNYS_APPLY, plate, payload)
  cb({ ok = true })
end)
