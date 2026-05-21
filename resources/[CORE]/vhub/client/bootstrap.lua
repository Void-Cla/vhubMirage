-- client/bootstrap.lua — Entry point client-side
-- Estratégia (padrão Mirage): aguarda `playerSpawned` natural; se não disparar,
-- usa nativas do GTA (NetworkResurrectLocalPlayer + ShutdownLoadingScreen) para
-- spawnar manualmente — não depende de `spawnmanager` externo.

local SPAWN_POS   = { x = -538.70, y = -214.91, z = 37.65, h = 0.0 }
local SPAWN_MODEL = "mp_m_freemode_01"
local FALLBACK_WINDOW_MS = 60000  -- janela total para detectar player ativo
local FALLBACK_DELAY_MS  = 2000   -- atraso após ativo para dar chance ao spawnmanager
local DEBOUNCE_MS        = 5000   -- evita duplo envio de ready (natural + fallback)

local _init_done   = false
local _ultimo_ready = -DEBOUNCE_MS  -- permite primeiro envio imediato

local function enviarReady()
  local agora = GetGameTimer()
  if agora - _ultimo_ready < DEBOUNCE_MS then return end
  _ultimo_ready = agora
  TriggerServerEvent("vHub:ready")
end

-- ── Caminho natural: spawnmanager (ou outro resource) dispara playerSpawned ──

AddEventHandler("playerSpawned", function()
  enviarReady()
end)

-- ── Fallback nativo: spawn via NetworkResurrectLocalPlayer ───────────────────

local function carregarModelo(hash)
  if not IsModelInCdimage(hash) or not IsModelValid(hash) then return false end
  RequestModel(hash)
  for _ = 1, 200 do
    if HasModelLoaded(hash) then return true end
    Citizen.Wait(10)
    RequestModel(hash)
  end
  return false
end

local function spawnNativo()
  local hash = GetHashKey(SPAWN_MODEL)
  DoScreenFadeOut(0)

  if carregarModelo(hash) then
    SetPlayerModel(PlayerId(), hash)
    SetPedDefaultComponentVariation(PlayerPedId())
    SetModelAsNoLongerNeeded(hash)
  end

  RequestCollisionAtCoord(SPAWN_POS.x, SPAWN_POS.y, SPAWN_POS.z)
  NetworkResurrectLocalPlayer(SPAWN_POS.x, SPAWN_POS.y, SPAWN_POS.z, SPAWN_POS.h, true, true, false)

  local ped = PlayerPedId()
  ClearPedTasksImmediately(ped)
  RemoveAllPedWeapons(ped, true)
  ClearPlayerWantedLevel(PlayerId())
  SetEntityCoordsNoOffset(ped, SPAWN_POS.x, SPAWN_POS.y, SPAWN_POS.z, false, false, false)
  SetEntityHeading(ped, SPAWN_POS.h)
  SetEntityHealth(ped, 200)
  SetEntityVisible(ped, true, false)
  FreezeEntityPosition(ped, false)
  SetPlayerInvincible(PlayerId(), false)

  -- Libera o cliente da tela "Awaiting scripts"
  if ShutdownLoadingScreen    then ShutdownLoadingScreen()    end
  if ShutdownLoadingScreenNui then ShutdownLoadingScreenNui() end

  DoScreenFadeIn(500)
end

Citizen.CreateThread(function()
  local limite = GetGameTimer() + FALLBACK_WINDOW_MS
  while GetGameTimer() < limite do
    Citizen.Wait(250)
    if _ultimo_ready > 0 then return end  -- playerSpawned natural cobriu
    if NetworkIsPlayerActive(PlayerId()) then
      Citizen.Wait(FALLBACK_DELAY_MS)
      if _ultimo_ready > 0 then return end
      print("[vHub][CLIENT] spawnmanager ausente — usando NetworkResurrectLocalPlayer")
      spawnNativo()
      enviarReady()
      return
    end
  end
  print("[vHub][CLIENT] spawn fallback expirou — player nunca ficou ativo")
end)

-- ── Retry: se em 15s não recebemos initDone, reenvia ─────────────────────────
Citizen.CreateThread(function()
  Citizen.Wait(15000)
  if not _init_done then
    print("[vHub][CLIENT] sem initDone em 15s — reenviando ready")
    _ultimo_ready = -DEBOUNCE_MS
    enviarReady()
  end
end)

-- ── Recebe confirmação do servidor ─────────────────────────────────────

RegisterNetEvent("vHub:initDone")
AddEventHandler("vHub:initDone", function(user_id, char_id, primeiro_spawn)
  _init_done = true

  -- Salva em State Bags para outros scripts lerem sem precisar do vHub
  if LocalPlayer and LocalPlayer.state then
    LocalPlayer.state:set("vhub_uid",            user_id,               true)
    LocalPlayer.state:set("vhub_user_id",        user_id,               true)  -- alias legado
    LocalPlayer.state:set("vhub_char_id",        char_id,               true)
    LocalPlayer.state:set("vhub_pronto",         true,                  true)
    LocalPlayer.state:set("vhub_primeiro_spawn", primeiro_spawn == true, true)
  end

  TriggerEvent("vHub:localReady", user_id, char_id, primeiro_spawn)
end)

-- ── Personagem ─────────────────────────────────────────────────────────

RegisterNetEvent("vHub:charSelected")
AddEventHandler("vHub:charSelected", function(char_id)
  if LocalPlayer and LocalPlayer.state then
    LocalPlayer.state:set("vhub_char_id", char_id, true)
  end
  TriggerEvent("vHub:localCharSelected", char_id)
end)

RegisterNetEvent("vHub:charSelectFailed")
AddEventHandler("vHub:charSelectFailed", function(reason)
  TriggerEvent("vHub:localCharFailed", reason)
end)
