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
    DisplayRadar(false)
    DisplayHud(false)
  else
    SetEveryoneIgnorePlayer(PlayerId(), false)
    SetPoliceIgnorePlayer(PlayerId(), false)
    DisplayRadar(true)
    DisplayHud(true)
  end
end

local _awaitSel = false

-- entrega o controle ao SELECTOR (RequestOpen preserva o _pending/hold do
-- HSS, que troca o bucket 999→1 no spawn confirmado). Watchdog: se o
-- selector não abrir em 6s (evento perdido / selector sem ensure), tenta 1x mais —
-- evita o player preso no mundo congelado sem NUI. (5s de throttle já passou.)
local function handoffSelector()
  setFocus(false)
  setGateEnvironment(false)
  ClearTimecycleModifier()
  DoScreenFadeIn(0)
  _awaitSel = true
  TriggerServerEvent(E.SELECTOR_REQUEST_OPEN)
  Citizen.SetTimeout(6000, function()
    if _awaitSel then TriggerServerEvent(E.SELECTOR_REQUEST_OPEN) end
  end)
end

-- o selector abriu de fato → cancela o watchdog (observação read-only do evento dele)
RegisterNetEvent(E.SELECTOR_OPEN, function() _awaitSel = false end)


-- ============================================================
-- PED DE PREVIEW (char select — bucket 999, somente visual)
-- ============================================================

local _previewPed = 0
local PREVIEW_MODEL     = GetHashKey("mp_m_freemode_01")
local PREVIEW_ANIM_DICT = "amb@world_human_stand_impatient@male@base"
local PREVIEW_ANIM_NAME = "base"

-- destrói o ped de preview se existir
local function destroyPreviewPed()
  if _previewPed ~= 0 and DoesEntityExist(_previewPed) then
    StopEntityAnim(_previewPed, PREVIEW_ANIM_NAME, PREVIEW_ANIM_DICT)
    DeleteEntity(_previewPed)
  end
  _previewPed = 0
end

-- cria ped de preview à frente do player local (bucket 999 — sem rede)
local function spawnPreviewPed(charIndex)
  destroyPreviewPed()

  Citizen.CreateThread(function()
    local model = PREVIEW_MODEL
    if not IsModelInCdimage(model) or not IsModelValid(model) then return end

    RequestModel(model)
    local waited = 0
    while not HasModelLoaded(model) and waited < 5000 do
      Citizen.Wait(100)
      waited = waited + 100
    end
    if not HasModelLoaded(model) then return end

    local player = PlayerPedId()
    -- GetEntityCoords retorna nil/0,0,0 quando o ped ainda não existe (bucket 999).
    -- Aguarda até o ped estar fisicamente presente no mundo antes de posicionar.
    waited = 0
    while not DoesEntityExist(player) and waited < 5000 do
      Citizen.Wait(100)
      waited = waited + 100
      player = PlayerPedId()
    end
    if not DoesEntityExist(player) then
      SetModelAsNoLongerNeeded(model)
      return
    end

    local coords = GetEntityCoords(player)
    local px, py, pz = coords.x, coords.y, coords.z
    local heading = GetEntityHeading(player)

    -- posiciona 2m à frente e ligeiramente à direita (decorativo, sem colisão crítica)
    local rad = math.rad(heading)
    local ox = math.sin(-rad) * 2.2
    local oy = math.cos(-rad) * 2.2

    local ped = CreatePed(4, model, px + ox, py + oy, pz, heading + 180.0, false, false)

    if not DoesEntityExist(ped) then
      SetModelAsNoLongerNeeded(model)
      return
    end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, true, false)

    -- variação de componentes por índice (distingue os pilotos visualmente)
    local torso = (charIndex % 3) + 1
    SetPedComponentVariation(ped, 3, torso, 0, 0)  -- torso
    SetPedComponentVariation(ped, 11, 15, 0, 0)    -- acessório (capacete off)

    -- animação idle
    RequestAnimDict(PREVIEW_ANIM_DICT)
    waited = 0
    while not HasAnimDictLoaded(PREVIEW_ANIM_DICT) and waited < 3000 do
      Citizen.Wait(100)
      waited = waited + 100
    end
    if HasAnimDictLoaded(PREVIEW_ANIM_DICT) then
      TaskPlayAnim(ped, PREVIEW_ANIM_DICT, PREVIEW_ANIM_NAME, 8.0, -8.0, -1, 1, 0, false, false, false)
    end

    SetModelAsNoLongerNeeded(model)
    _previewPed = ped
  end)
end


-- ============================================================
-- EVENTOS DO SERVIDOR
-- ============================================================

-- abre a NUI de login (não autenticado); congela ped para silenciar o mundo
RegisterNetEvent(E.OPEN, function()
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
  spawnPreviewPed(0)
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

RegisterNetEvent(E.CHAR_OK, function()
  destroyPreviewPed()
  SendNUIMessage({ type = "login:close", data = {} })
  handoffSelector()
end)

RegisterNetEvent(E.CHAR_FAIL, function(err)
  SendNUIMessage({ type = "login:error", data = { err = tostring(err or "erro") } })
end)

-- já autenticado nesta sessão (reentrada) → pula login, vai direto ao selector
RegisterNetEvent(E.PROCEED_SPAWN, function()
  handoffSelector()
end)

-- entrega foco ao SIMS sem abrir o selector nem consumir o pending do HSS
RegisterNetEvent(E.CREATION_HANDOFF, function()
  destroyPreviewPed()
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
  spawnPreviewPed(0)
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

RegisterNUICallback("createChar", function(_, cb)
  TriggerServerEvent(E.REQUEST_CREATE)
  cb({ ok = true })
end)


-- ============================================================
-- CLEANUP (A-07)
-- ============================================================

AddEventHandler("onResourceStop", function(res)
  if res ~= GetCurrentResourceName() then return end
  if _focus then setFocus(false) end
  setGateEnvironment(false)
  destroyPreviewPed()
end)
