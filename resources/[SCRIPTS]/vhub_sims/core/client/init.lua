-- init.lua — orquestração NUI e delegação física integral ao HSS
---@diagnostic disable: undefined-global

local E = VHubSims.E
local active = nil


-- ============================================================
-- HSS CLIENT CONTRACT
-- ============================================================

local function hss(method, ...)
  local args = { ... }
  local ok, result = pcall(function()
    return exports.vhub_hss[method](exports.vhub_hss, table.unpack(args))
  end)
  if not ok then return false end
  return result == true or (type(result) == 'table' and result.ok == true)
end

local function closeLocal(restore)
  local closing = active
  active = nil

  if closing then
    if restore then hss('restoreCustomizationPreview') end
    hss('endCustomizationPreview', restore == true)
  end

  SetNuiFocus(false, false)
  SendNUIMessage({ type = 'sims:close', data = {} })
end

local function failSafe()
  local sessionId = active and active.session_id
  closeLocal(true)
  if sessionId then TriggerServerEvent(E.SRV_CANCEL, { session_id = sessionId }) end
end

-- Controles bloqueados enquanto o estúdio está aberto: ataque/soco, mira, movimento, sprint,
-- pulo, entrar/sair de veículo, arma, olhar. NÃO inclui os controles de cursor (237–242),
-- para o mouse do CEF continuar visível e clicável.
local BLOCKED_CONTROLS = {
  24, 25, 257, 263, 264, 140, 141, 142, 143,   -- ataque / mira / soco
  1, 2,                                          -- olhar (câmera é via NUI)
  30, 31, 32, 33, 34, 35,                        -- movimento
  21, 22, 23, 44, 75,                            -- sprint / pulo / entrar / cover / sair
  37, 45, 47,                                    -- arma / reload / detonar
}

-- Trava os controles do jogo enquanto o estúdio está aberto: clique não vira soco e teclas não
-- vazam para o mundo, sem esconder o cursor. Encerra sozinha quando 'active' zera.
local function startControlLock()
  Citizen.CreateThread(function()
    while active do
      for index = 1, #BLOCKED_CONTROLS do
        DisableControlAction(0, BLOCKED_CONTROLS[index], true)
      end
      Citizen.Wait(0)
    end
  end)
end


-- ============================================================
-- PALETAS REAIS DE COR (leitura de natives, sem mutar entidade)
-- ============================================================

-- Consulta única às cores reais de cabelo/maquiagem do jogo (guia fiel da NUI; o ped continua
-- sendo a verdade). São valores estáticos → computa 1x e cacheia. Falha/ausência → NUI usa HSL.
local paletteCache = nil

local function hex(r, g, b)
  return ('#%02x%02x%02x'):format((r or 0) & 0xff, (g or 0) & 0xff, (b or 0) & 0xff)
end

local function readPalette(countFn, colorFn)
  local list = {}
  local ok, count = pcall(countFn)
  if not ok or type(count) ~= 'number' or count < 1 then return list end
  for index = 0, math.floor(count) - 1 do
    local okc, r, g, b = pcall(colorFn, index)
    if okc and type(r) == 'number' then list[index + 1] = hex(r, g, b) end
  end
  return list
end

local function buildPalettes()
  if paletteCache then return paletteCache end
  paletteCache = {
    hair = readPalette(GetNumHairColors, GetHairRgbColor),
    makeup = readPalette(GetNumMakeupColors, GetMakeupRgbColor),
  }
  return paletteCache
end


-- ============================================================
-- EVENTOS AUTORITATIVOS
-- ============================================================

RegisterNetEvent(E.CLI_STUDIO_OPEN, function(payload)
  if type(payload) ~= 'table' or type(payload.session_id) ~= 'string' then return end
  if active then closeLocal(true) end

  active = { session_id = payload.session_id, mode = payload.mode }
  local sessionId = payload.session_id

  -- Foco + trava de controles IMEDIATOS: cursor aparece e o jogo não recebe clique/tecla
  -- mesmo enquanto o estágio físico do HSS ainda monta (evita soco no mundo / tela sem cursor).
  SetNuiFocus(true, true)
  startControlLock()

  -- Aguarda o estágio HSS ficar pronto (model load + MovePed); câmera é best-effort.
  Citizen.CreateThread(function()
    local deadline = GetGameTimer() + 12000
    while active and active.session_id == sessionId and GetGameTimer() < deadline do
      if hss('beginCustomizationPreview', payload.current) then
        hss('setCustomizationCamera', payload.mode == 'barber' and 'head' or 'body')
        SetNuiFocus(true, true)   -- reassegura foco/cursor ao revelar a página (vence corrida do handoff)
        payload.palettes = buildPalettes()   -- cores reais do jogo como guia da NUI (cacheado)
        SendNUIMessage({ type = 'sims:open', data = payload })
        return
      end
      Citizen.Wait(50)
    end
    if active and active.session_id == sessionId then failSafe() end
  end)
end)

RegisterNetEvent(E.CLI_STUDIO_CLOSE, function(payload)
  closeLocal(type(payload) == 'table' and payload.restore == true)
end)

RegisterNetEvent(E.CLI_CHECKOUT_RESULT, function(payload)
  SendNUIMessage({ type = 'sims:result', data = payload })
end)

RegisterNetEvent(E.CLI_OUTFITS, function(payload)
  SendNUIMessage({ type = 'sims:outfits', data = payload })
end)


-- ============================================================
-- CALLBACKS NUI — SOMENTE INTENÇÕES
-- ============================================================

-- A NUI avisa quando a página ficou de fato visível (body perdeu a classe 'hidden'). SetNuiFocus
-- chamado enquanto o body está display:none pode não revelar o cursor no CEF do FiveM — este
-- reassert, disparado só quando há conteúdo renderizado sob o mouse, garante o cursor visível.
RegisterNUICallback('studioReady', function(_, cb)
  if active then SetNuiFocus(true, true) end
  cb({ ok = active ~= nil })
end)

RegisterNUICallback('preview', function(data, cb)
  if not active or type(data) ~= 'table' or data.session_id ~= active.session_id
    or type(data.patch) ~= 'table' or not hss('previewCustomization', data.patch) then
    cb({ ok = false })
    failSafe()
    return
  end
  cb({ ok = true })
end)

RegisterNUICallback('camera', function(data, cb)
  local views = { head = true, torso = true, chest = true, body = true, legs = true, feet = true }
  if not active or type(data) ~= 'table' or not views[data.view]
    or not hss('setCustomizationCamera', data.view) then
    cb({ ok = false })
    failSafe()
    return
  end
  cb({ ok = true })
end)

-- Órbita da câmera por deltas abstratos (drag/scroll); coalescido no cliente NUI (~20 Hz).
-- Alta frequência: falha transitória NÃO derruba o estúdio (sem failSafe).
RegisterNUICallback('orbit', function(data, cb)
  if not active or type(data) ~= 'table' then cb({ ok = false }); return end
  local dyaw = tonumber(data.dyaw) or 0.0
  local dpitch = tonumber(data.dpitch) or 0.0
  local dzoom = tonumber(data.dzoom) or 0.0
  if dyaw ~= dyaw or dpitch ~= dpitch or dzoom ~= dzoom then cb({ ok = false }); return end
  hss('updateCustomizationCamera', { dyaw = dyaw, dpitch = dpitch, dzoom = dzoom })
  cb({ ok = true })
end)

RegisterNUICallback('rotate', function(data, cb)
  local delta = type(data) == 'table' and tonumber(data.delta) or nil
  if not active or not delta or delta ~= delta or delta < -45 or delta > 45
    or not hss('rotateCustomizationPed', delta) then
    cb({ ok = false })
    failSafe()
    return
  end
  cb({ ok = true })
end)

RegisterNUICallback('checkout', function(data, cb)
  if not active or type(data) ~= 'table' or data.session_id ~= active.session_id
    or type(data.patch) ~= 'table' then
    cb({ ok = false })
    return
  end
  TriggerServerEvent(E.SRV_CHECKOUT, { session_id = active.session_id, patch = data.patch })
  cb({ ok = true })
end)

RegisterNUICallback('wizard', function(data, cb)
  if not active or active.mode ~= 'creator' or type(data) ~= 'table' then
    cb({ ok = false })
    return
  end
  data.session_id = active.session_id
  TriggerServerEvent(E.SRV_WIZARD_SUBMIT, data)
  cb({ ok = true })
end)

RegisterNUICallback('cancel', function(_, cb)
  if active then TriggerServerEvent(E.SRV_CANCEL, { session_id = active.session_id }) end
  cb({ ok = true })
end)

RegisterNUICallback('outfitList', function(_, cb)
  if active then TriggerServerEvent(E.SRV_OUTFIT_LIST, { session_id = active.session_id }) end
  cb({ ok = active ~= nil })
end)

RegisterNUICallback('outfitSave', function(data, cb)
  if not active or type(data) ~= 'table' or type(data.patch) ~= 'table' then
    cb({ ok = false })
    return
  end
  TriggerServerEvent(E.SRV_OUTFIT_SAVE, {
    session_id = active.session_id,
    label = data.label,
    patch = data.patch,
  })
  cb({ ok = true })
end)

RegisterNUICallback('outfitRename', function(data, cb)
  if active and type(data) == 'table' then
    TriggerServerEvent(E.SRV_OUTFIT_RENAME, {
      session_id = active.session_id,
      outfit_id = data.outfit_id,
      label = data.label,
    })
  end
  cb({ ok = active ~= nil })
end)

RegisterNUICallback('outfitDelete', function(data, cb)
  if active and type(data) == 'table' then
    TriggerServerEvent(E.SRV_OUTFIT_DELETE, {
      session_id = active.session_id,
      outfit_id = data.outfit_id,
    })
  end
  cb({ ok = active ~= nil })
end)

RegisterNUICallback('outfitApply', function(data, cb)
  if active and type(data) == 'table' then
    TriggerServerEvent(E.SRV_OUTFIT_APPLY, {
      session_id = active.session_id,
      outfit_id = data.outfit_id,
    })
  end
  cb({ ok = active ~= nil })
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddStateBagChangeHandler('hss_consciousness', nil, function(bagName, _, value)
  local localBag = ('player:%d'):format(GetPlayerServerId(PlayerId()))
  if active and bagName == localBag and value == 'unconscious' then
    TriggerServerEvent(E.SRV_CANCEL, { session_id = active.session_id })
  end
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource == GetCurrentResourceName() then closeLocal(true)
  elseif resource == 'vhub_hss' and active then closeLocal(false) end
end)
