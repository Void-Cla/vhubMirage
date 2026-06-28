-- client/main.lua — bridge da NUI do gate de entrada (L2/L3).
-- NÃO decide verdade: abre/fecha a NUI e repassa as ações ao servidor. O ped já
-- está em hold (invisível/congelado no bucket 999) pelo vhub_player_state.

local _focus = false

local function setFocus(on)
  _focus = on
  SetNuiFocus(on, on)
end

local _awaitSel = false

-- entrega o controle ao SELECTOR (RequestOpen preserva o _pending/hold do
-- player_state, que troca o bucket 999→1 no spawn confirmado). Watchdog: se o
-- selector não abrir em 6s (evento perdido / selector sem ensure), tenta 1x mais —
-- evita o player preso no mundo congelado sem NUI. (5s de throttle já passou.)
local function handoffSelector()
  setFocus(false)
  _awaitSel = true
  TriggerServerEvent("vhub_spawselector:server:RequestOpen")
  Citizen.SetTimeout(6000, function()
    if _awaitSel then TriggerServerEvent("vhub_spawselector:server:RequestOpen") end
  end)
end

-- o selector abriu de fato → cancela o watchdog (observação read-only do evento dele)
RegisterNetEvent("vhub_spawselector:client:Open", function() _awaitSel = false end)


-- ============================================================
-- EVENTOS DO SERVIDOR
-- ============================================================

-- abre a NUI de login (não autenticado)
RegisterNetEvent("vhub_login:open", function()
  setFocus(true)
  SendNUIMessage({ action = "open", view = "login" })
end)

-- login/registro OK → lista de personagens
RegisterNetEvent("vhub_login:authOK", function(chars)
  SendNUIMessage({ action = "chars", chars = chars or {} })
  SendNUIMessage({ action = "view",  view  = "charselect" })
end)

RegisterNetEvent("vhub_login:authFail", function(err)
  SendNUIMessage({ action = "error", err = tostring(err or "erro") })
end)

-- char selecionado (core já gravou) → fecha NUI e delega ao SELECTOR via
-- RequestOpen (NÃO RequestSpawn: preserva o _pending/hold do player_state, que é
-- o que troca o bucket 999→1 no spawn confirmado).
RegisterNetEvent("vhub_login:charOK", function()
  SendNUIMessage({ action = "close" })
  handoffSelector()
end)

RegisterNetEvent("vhub_login:charFail", function(err)
  SendNUIMessage({ action = "error", err = tostring(err or "erro") })
end)

-- já autenticado nesta sessão (reentrada) → pula login, vai direto ao selector
RegisterNetEvent("vhub_login:proceedSpawn", function()
  handoffSelector()
end)

RegisterNetEvent("vhub_login:createUnavailable", function()
  SendNUIMessage({ action = "error", err = "criacao_indisponivel" })
end)


-- ============================================================
-- CALLBACKS DA NUI (cliente → servidor)
-- ============================================================

RegisterNUICallback("login", function(d, cb)
  TriggerServerEvent("vhub_login:tryLogin", d.username, d.password)
  cb({ ok = true })
end)

RegisterNUICallback("register", function(d, cb)
  TriggerServerEvent("vhub_login:tryRegister", d.username, d.password)
  cb({ ok = true })
end)

RegisterNUICallback("pickChar", function(d, cb)
  TriggerServerEvent("vhub_login:pickChar", d.cid)
  cb({ ok = true })
end)

RegisterNUICallback("createChar", function(_, cb)
  TriggerServerEvent("vhub_login:requestCreate")
  cb({ ok = true })
end)


-- ============================================================
-- CLEANUP (A-07)
-- ============================================================

AddEventHandler("onResourceStop", function(res)
  if res == GetCurrentResourceName() and _focus then setFocus(false) end
end)
