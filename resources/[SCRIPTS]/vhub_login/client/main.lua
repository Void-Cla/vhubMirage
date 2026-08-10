-- client/main.lua — bridge da NUI do gate de entrada (L2/L3).
-- NÃO decide verdade: abre/fecha a NUI e repassa as ações ao servidor. O ped já
-- está em hold (invisível/congelado no bucket 999) pelo vhub_hss.

local _focus = false
local E = VHubLogin.E
local CFG = VHubLogin.Config

local function setFocus(on)
  _focus = on
  SetNuiFocus(on, on)
end

-- ajusta somente ambiente/HUD; estado físico do ped pertence ao HSS
local function setGateEnvironment(on)
  if on then
    SetEveryoneIgnorePlayer(PlayerId(), true)
    SetPoliceIgnorePlayer(PlayerId(), true)
  else
    SetEveryoneIgnorePlayer(PlayerId(), false)
    SetPoliceIgnorePlayer(PlayerId(), false)
  end
  local ok, applied = pcall(function()
    return exports.vhub_hss:setNativeHudSuppressed('hud', on)
  end)
  return ok and applied == true
end

local _awaitSel = false

-- entrega o controle ao SELECTOR (RequestOpen preserva o _pending/hold do
-- HSS, que troca o bucket 999→1 no spawn confirmado). Watchdog: se o
-- selector não abrir em 6s (evento perdido / selector sem ensure), tenta 1x mais —
-- evita o player preso no mundo congelado sem NUI. (5s de throttle já passou.)
local function handoffSelector()
  setFocus(false)
  ClearTimecycleModifier()
  DoScreenFadeIn(0)
  _awaitSel = true
  TriggerServerEvent(E.SELECTOR_REQUEST_OPEN)
  Citizen.SetTimeout(6000, function()
    if _awaitSel then TriggerServerEvent(E.SELECTOR_REQUEST_OPEN) end
  end)
end

local function handoffPreparedSelector(payload)
  if type(payload) ~= "table" or type(payload.data) ~= "table" then
    handoffSelector()
    return
  end
  _awaitSel = false
  SendNUIMessage({ type = "login:close", data = {} })
  _focus = false
  ClearTimecycleModifier()
  TriggerEvent(E.SELECTOR_OPEN, payload)
end

-- o selector abriu de fato → cancela o watchdog (observação read-only do evento dele)
RegisterNetEvent(E.SELECTOR_OPEN, function() _awaitSel = false end)


-- ============================================================
-- PALCO DE SELECAO (3 peds locais; estado persistido continua no HSS)
-- ============================================================

local _previewPeds = {}
local _previewCharacters = {}
local _selectionCam = 0
local _selectionCams = {}
local _selectionSlot = 1
local _focusedSlot = 0
local _previewGeneration = 0
local SELECTION = CFG.selection or {}
local PREVIEW_SCENARIOS = {
  "WORLD_HUMAN_STAND_IMPATIENT",
  "WORLD_HUMAN_GUARD_STAND",
  "WORLD_HUMAN_STAND_MOBILE",
}

local function destroyPreviewPeds(preserveExternalScene)
  _previewGeneration = _previewGeneration + 1
  local hadScene = next(_selectionCams) ~= nil or next(_previewPeds) ~= nil
  for _, ped in pairs(_previewPeds) do
    if DoesEntityExist(ped) then
      ClearPedTasksImmediately(ped)
      DeleteEntity(ped)
    end
  end
  _previewPeds = {}
  _focusedSlot = 0
  if next(_selectionCams) ~= nil then
    if not preserveExternalScene then RenderScriptCams(false, true, 350, true, true) end
    for cam in pairs(_selectionCams) do
      if DoesCamExist(cam) then DestroyCam(cam, false) end
    end
  end
  _selectionCams = {}
  _selectionCam = 0
  if hadScene and not preserveExternalScene then
    ClearFocus()
    NewLoadSceneStop()
  end
end

local function modelHash(name)
  if name ~= "mp_m_freemode_01" and name ~= "mp_f_freemode_01" then
    name = "mp_m_freemode_01"
  end
  local model = GetHashKey(name)
  if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end
  return model
end

local function requestPreviewModels(characters, generation)
  local models, requested = {}, {}
  for index = 1, math.min(#characters, 3) do
    local character = type(characters[index]) == "table" and characters[index] or {}
    local customization = type(character.customization) == "table" and character.customization or {}
    local model = modelHash(customization.model or character.model)
    models[index] = model
    if model and not requested[model] then
      requested[model] = true
      RequestModel(model)
    end
  end

  local deadline = GetGameTimer() + 5000
  while generation == _previewGeneration and GetGameTimer() < deadline do
    local ready = true
    for model in pairs(requested) do
      if not HasModelLoaded(model) then ready = false break end
    end
    if ready then break end
    Citizen.Wait(25)
  end
  for index, model in pairs(models) do
    if not HasModelLoaded(model) then models[index] = nil end
  end
  return models, requested
end

local function startSelectionCamera()
  local camera = SELECTION.camera
  local positions = SELECTION.positions
  if type(SELECTION.map_resource) ~= "string"
    or GetResourceState(SELECTION.map_resource) ~= "started"
    or type(camera) ~= "table" or type(positions) ~= "table" or type(positions[2]) ~= "table" then
    return false
  end
  local center = positions[2]
  RequestCollisionAtCoord(center.x, center.y, center.z)
  SetFocusPosAndVel(center.x, center.y, center.z, 0.0, 0.0, 0.0)
  NewLoadSceneStartSphere(center.x, center.y, center.z, 35.0, 0)
  _selectionCam = CreateCamWithParams(
    "DEFAULT_SCRIPTED_CAMERA",
    camera.x, camera.y, camera.z,
    0.0, 0.0, 0.0,
    camera.fov or 52.0,
    true, 2
  )
  if not _selectionCam or _selectionCam == 0 then
    ClearFocus()
    NewLoadSceneStop()
    return false
  end
  _selectionCams[_selectionCam] = _previewGeneration
  PointCamAtCoord(_selectionCam, camera.target_x, camera.target_y, camera.target_z)
  SetCamActive(_selectionCam, true)
  RenderScriptCams(true, true, 500, true, true)
  return true
end

local function focusSelectionCamera(slot)
  slot = math.floor(tonumber(slot) or 0)
  local camera = SELECTION.camera
  local position = type(SELECTION.positions) == "table" and SELECTION.positions[slot] or nil
  if slot < 1 or slot > #_previewCharacters or _selectionCam == 0
    or type(camera) ~= "table" or type(position) ~= "table" then return false end
  if slot == _focusedSlot then return true end

  local heading = math.rad(tonumber(position.heading) or 180.0)
  local distance = tonumber(camera.focus_distance) or 2.95
  local nextCam = CreateCamWithParams(
    "DEFAULT_SCRIPTED_CAMERA",
    position.x - math.sin(heading) * distance,
    position.y + math.cos(heading) * distance,
    position.z + (tonumber(camera.focus_height) or 1.02),
    0.0, 0.0, 0.0,
    tonumber(camera.focus_fov) or 44.0,
    false, 2
  )
  if not nextCam or nextCam == 0 then return false end

  PointCamAtCoord(nextCam, position.x, position.y,
    position.z + (tonumber(camera.focus_target_height) or 0.68))
  RequestCollisionAtCoord(position.x, position.y, position.z)

  local previousCam = _selectionCam
  local transition = math.max(150, math.min(1500, math.floor(tonumber(camera.transition_ms) or 850)))
  _selectionCam = nextCam
  local generation = _previewGeneration
  _selectionCams[nextCam] = generation
  _selectionSlot = slot
  _focusedSlot = slot
  SetCamActiveWithInterp(nextCam, previousCam, transition, 1, 1)
  RenderScriptCams(true, false, 0, true, true)

  Citizen.SetTimeout(transition + 50, function()
    if previousCam ~= 0 and previousCam ~= _selectionCam
      and _selectionCams[previousCam] == generation then
      if DoesCamExist(previousCam) then DestroyCam(previousCam, false) end
      _selectionCams[previousCam] = nil
    end
  end)
  return true
end

local function spawnPreviewPeds(characters)
  destroyPreviewPeds()
  characters = type(characters) == "table" and characters or {}
  _previewCharacters = characters
  if not startSelectionCamera() or #characters == 0 then return end

  local generation = _previewGeneration
  _selectionSlot = 1
  focusSelectionCamera(_selectionSlot)
  Citizen.CreateThread(function()
    local sceneDeadline = GetGameTimer() + 4000
    while generation == _previewGeneration and not IsNewLoadSceneLoaded()
      and GetGameTimer() < sceneDeadline do Citizen.Wait(50) end
    if generation ~= _previewGeneration then return end
    local models, requested = requestPreviewModels(characters, generation)
    if generation ~= _previewGeneration then
      for model in pairs(requested) do SetModelAsNoLongerNeeded(model) end
      return
    end

    for index = 1, math.min(#characters, 3) do
      if generation ~= _previewGeneration then
        for model in pairs(requested) do SetModelAsNoLongerNeeded(model) end
        return
      end
      local position = SELECTION.positions[index]
      local character = type(characters[index]) == "table" and characters[index] or {}
      local customization = type(character.customization) == "table" and character.customization or {}
      local model = models[index]
      if model then
        if generation ~= _previewGeneration then
          for requestedModel in pairs(requested) do SetModelAsNoLongerNeeded(requestedModel) end
          return
        end
        local ped = CreatePed(4, model, position.x, position.y, position.z,
          position.heading, false, false)
        if DoesEntityExist(ped) then
          SetEntityAsMissionEntity(ped, true, true)
          SetEntityInvincible(ped, true)
          SetBlockingOfNonTemporaryEvents(ped, true)
          SetPedCanRagdoll(ped, false)
          SetEntityVisible(ped, true, false)
          local applied, result = pcall(function()
            return exports.vhub_hss:applyPreviewCustomization(ped, customization)
          end)
          if not applied or result ~= true then SetPedDefaultComponentVariation(ped) end
          SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, false, false, false)
          SetEntityHeading(ped, position.heading)
          TaskStartScenarioInPlace(ped, PREVIEW_SCENARIOS[index], -1, true)
          FreezeEntityPosition(ped, true)
          _previewPeds[index] = ped
        end
      end
    end
    for model in pairs(requested) do SetModelAsNoLongerNeeded(model) end

    while generation == _previewGeneration and _selectionCam ~= 0 do
      local position = SELECTION.positions[_selectionSlot]
      if position and _previewPeds[_selectionSlot] then
        DrawMarker(1, position.x, position.y, position.z - 0.96,
          0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
          1.15, 1.15, 0.08, 232, 177, 73, 125,
          false, false, 2, false, nil, nil, false)
      end
      Citizen.Wait(0)
    end
  end)
end


-- ============================================================
-- EVENTOS DO SERVIDOR
-- ============================================================

-- abre a NUI de login (não autenticado); congela ped para silenciar o mundo
RegisterNetEvent(E.OPEN, function()
  destroyPreviewPeds()
  _previewCharacters = {}
  setGateEnvironment(true)
  setFocus(true)
  SendNUIMessage({
    type = "login:open",
    data = { view = "login", termsVersion = CFG.terms_version },
  })
end)

-- login/registro OK → lista de personagens + ped de preview do primeiro slot
RegisterNetEvent(E.AUTH_OK, function(chars)
  SendNUIMessage({ type = "login:chars", data = { chars = chars or {} } })
  SendNUIMessage({ type = "login:view", data = { view = "charselect" } })
  spawnPreviewPeds(chars)
end)

RegisterNetEvent(E.AUTH_FAIL, function(err)
  SendNUIMessage({ type = "login:error", data = { err = tostring(err or "erro") } })
end)

-- char selecionado (core já gravou) → fecha NUI e delega ao SELECTOR via
-- RequestOpen (NÃO RequestSpawn: preserva o _pending/hold do HSS, que é
-- o que troca o bucket 999→1 no spawn confirmado).
RegisterNetEvent(E.RECOVERY_DONE, function()
  SendNUIMessage({ type = "login:recoveryDone", data = {} })
end)

RegisterNetEvent(E.CHAR_OK, function(selector)
  handoffPreparedSelector(selector)
end)

RegisterNetEvent(E.CHAR_FAIL, function(err)
  SendNUIMessage({ type = "login:error", data = { err = tostring(err or "erro") } })
end)

-- já autenticado nesta sessão (reentrada) → pula login, vai direto ao selector
RegisterNetEvent(E.PROCEED_SPAWN, function(selector)
  setGateEnvironment(true)
  handoffPreparedSelector(selector)
end)

AddEventHandler(VHubSpawnSelector.E.COMPLETE, function()
  destroyPreviewPeds()
  _previewCharacters = {}
  setGateEnvironment(false)
  setFocus(false)
  if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
end)

RegisterNetEvent(VHubSpawnSelector.E.BACK, function(characters)
  characters = type(characters) == "table" and characters or {}
  _previewCharacters = characters
  setGateEnvironment(true)
  setFocus(true)
  SendNUIMessage({
    type = "login:creationReturn",
    data = { chars = characters },
  })
  if _selectionCam == 0 then spawnPreviewPeds(characters) end
end)

-- entrega foco ao SIMS sem abrir o selector nem consumir o pending do HSS
RegisterNetEvent(E.CREATION_HANDOFF, function()
  destroyPreviewPeds(true)
  setGateEnvironment(false)
  SendNUIMessage({ type = "login:close", data = {} })
  -- NÃO chamar SetNuiFocus(false) aqui: o SIMS assume o foco no CLI_STUDIO_OPEN e a ordem
  -- de chegada dos eventos (STAGE_BEGIN → STUDIO_OPEN foca true → HANDOFF) faria este false
  -- roubar o foco do criador (NUI abre mas não clica). O HANDOFF só dispara quando o SIMS ESTÁ
  -- abrindo; se o SIMS falhar, ele mesmo devolve o foco (failSafe → SetNuiFocus false).
  _focus = false
end)

-- conclusão/falha do criador → reabre a seleção e atualiza os cards
RegisterNetEvent(E.CREATION_RETURN, function(chars, err)
  setFocus(true)
  SendNUIMessage({
    type = "login:creationReturn",
    data = { chars = chars or {}, err = err },
  })
  spawnPreviewPeds(chars)
end)


-- ============================================================
-- CALLBACKS DA NUI (cliente → servidor)
-- ============================================================

RegisterNUICallback("login", function(d, cb)
  d = type(d) == "table" and d or {}
  TriggerServerEvent(E.TRY_LOGIN, d.username, d.password)
  cb({ ok = true })
end)

RegisterNUICallback("register", function(d, cb)
  d = type(d) == "table" and d or {}
  TriggerServerEvent(E.TRY_REGISTER_V2, {
    username = d.username,
    password = d.password,
    password_confirmation = d.password_confirmation,
    email = d.email,
    whatsapp = d.whatsapp,
    terms_accepted = d.terms_accepted == true,
    age_18 = d.age_18 == true,
    terms_version = d.terms_version,
  })
  cb({ ok = true })
end)

RegisterNUICallback("recovery", function(d, cb)
  d = type(d) == "table" and d or {}
  TriggerServerEvent(E.TRY_RECOVERY, {
    contact = d.contact,
    password = d.password,
    password_confirmation = d.password_confirmation,
  })
  cb({ ok = true })
end)

RegisterNUICallback("pickChar", function(d, cb)
  d = type(d) == "table" and d or {}
  TriggerServerEvent(E.PICK_CHAR, d.cid)
  cb({ ok = true })
end)

RegisterNUICallback("focusChar", function(d, cb)
  d = type(d) == "table" and d or {}
  local slot = tonumber(d.slot)
  if not slot or slot % 1 ~= 0 or not focusSelectionCamera(slot) then
    cb({ ok = false })
    return
  end
  cb({ ok = true })
end)

RegisterNUICallback("createChar", function(_, cb)
  TriggerServerEvent(E.REQUEST_CREATE)
  cb({ ok = true })
end)


-- ============================================================
-- CLEANUP (A-07)
-- ============================================================

AddEventHandler("onResourceStop", function(res)
  if res ~= GetCurrentResourceName() then return end
  destroyPreviewPeds()
  if _focus then setFocus(false) end
  setGateEnvironment(false)
end)
