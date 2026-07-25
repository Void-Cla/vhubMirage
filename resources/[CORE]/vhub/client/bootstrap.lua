-- client/bootstrap.lua — Entry point client-side
-- Estratégia (padrão Mirage): aguarda `playerSpawned` natural; se não disparar,
-- apenas sinaliza prontidão. O vhub_hss é o único escritor físico do spawn.

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

-- ── Fallback de prontidão: sem escrita física ────────────────────────────────

Citizen.CreateThread(function()
  local limite = GetGameTimer() + FALLBACK_WINDOW_MS
  while GetGameTimer() < limite do
    Citizen.Wait(250)
    if _ultimo_ready > 0 then return end  -- playerSpawned natural cobriu
    if NetworkIsPlayerActive(PlayerId()) then
      Citizen.Wait(FALLBACK_DELAY_MS)
      if _ultimo_ready > 0 then return end
      vHub.Logger:info("client", "playerSpawned ausente — sinalizando prontidão ao HSS")
      enviarReady()
      return
    end
  end
  vHub.Logger:warn("client", "spawn fallback expirou — player nunca ficou ativo")
end)

-- ── Retry: se em 15s não recebemos initDone, reenvia ─────────────────────────
Citizen.CreateThread(function()
  Citizen.Wait(15000)
  if not _init_done then
    vHub.Logger:warn("client", "sem initDone em 15s — reenviando ready")
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
