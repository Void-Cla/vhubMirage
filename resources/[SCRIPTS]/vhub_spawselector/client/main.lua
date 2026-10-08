-- UI de eleicao de coordenada. Nao toca ped, bucket ou teleporte.

local E = VHubSpawnSelector.E
local _payload = nil
local _open = false
local _submitting = false
local _accepted = false
local _physicalReady = false

-- Reforça o cursor por uma janela curta após abrir (budget bounded, L-18): no handoff
-- login→selector o foco pode ser transitoriamente sobrescrito por outro resource fechando
-- a própria NUI no mesmo tick, deixando o CEF sem cursor. O callback 'ready' reasserta 1×;
-- este watchdog cobre a corrida vencendo a sobrescrita por ~1,2s (8 × 150ms), e para no
-- instante em que a NUI fecha. Gera nova geração a cada abertura (não acumula threads).
local _focusGuard = 0
local function guardCursor()
  _focusGuard = _focusGuard + 1
  local generation = _focusGuard
  Citizen.CreateThread(function()
    for _, delay in ipairs({ 0, 80, 260, 700 }) do
      Citizen.Wait(delay)
      if not _open or generation ~= _focusGuard then return end
      SetNuiFocus(false, false)
      Citizen.Wait(0)
      if not _open or generation ~= _focusGuard then return end
      if SetCursorLocation then SetCursorLocation(0.5, 0.5) end
      if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
      SetNuiFocus(true, true)
    end
  end)
end

local function openUI(payload)
  if type(payload) ~= "table" or type(payload.data) ~= "table" or #payload.data == 0 then return end
  _payload = payload
  _open = true
  _submitting = false
  _accepted = false
  _physicalReady = false
  ClearTimecycleModifier()
  if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
  if SetCursorLocation then SetCursorLocation(0.5, 0.5) end
  SetNuiFocus(true, true)
  guardCursor()
  SendNUIMessage({
    action = "open",
    data = payload.data,
    last = payload.last,
    canBack = payload.canBack == true,
  })
  Citizen.SetTimeout(50, function()
    if _open then DoScreenFadeIn(250) end
  end)
end

local function closeUI(preserveFocus, completed)
  if not _open then return end
  _open = false
  _submitting = false
  _accepted = false
  _physicalReady = false
  _focusGuard = _focusGuard + 1
  _payload = nil
  if not preserveFocus then
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
  end
  ClearTimecycleModifier()
  SendNUIMessage({ action = "close" })
  if completed then TriggerEvent(E.COMPLETE) end
end

local function completeWhenReady()
  if _open and _accepted and _physicalReady then closeUI(false, true) end
end

RegisterNetEvent(E.OPEN)
AddEventHandler(E.OPEN, openUI)

RegisterNetEvent(E.RESULT)
AddEventHandler(E.RESULT, function(result)
  if not _open or type(result) ~= "table" then return end
  if result.ok == true then
    _accepted = true
    SendNUIMessage({ action = "accepted" })
    -- O HSS revela o mundo no SPAWNED; aceitar depois não pode escurecer novamente.
    completeWhenReady()
    return
  end
  _submitting = false
  SendNUIMessage({ action = "result", ok = false, err = tostring(result.err or "spawn_recusado") })
end)

RegisterNetEvent(E.BACK)
AddEventHandler(E.BACK, function()
  closeUI(true, false)
end)

AddEventHandler(VHubHSS.E.SPAWNED, function()
  if not _open then return end
  _physicalReady = true
  completeWhenReady()
end)

exports("Open", function()
  TriggerServerEvent(E.REQUEST_OPEN)
end)

AddEventHandler("onClientResourceStart", function(resource)
  if resource ~= GetCurrentResourceName() then return end
  Citizen.SetTimeout(250, function()
    TriggerServerEvent(E.REQUEST_OPEN)
  end)
end)

RegisterNUICallback("teleport", function(data, cb)
  if not _open or _submitting or type(data) ~= "table" then
    cb({ ok = false })
    return
  end

  local useLast = data.useLast == true
  local canonical = nil
  if not useLast then
    local uiIndex = tonumber(data.index)
    local item = uiIndex and uiIndex % 1 == 0 and _payload.data[uiIndex] or nil
    canonical = item and tonumber(item.index) or nil
    if not canonical then
      cb({ ok = false })
      return
    end
  end

  _submitting = true
  SendNUIMessage({ action = "busy" })
  TriggerServerEvent(E.REQUEST_SPAWN, canonical, useLast)
  cb({ ok = true })
end)

-- O CEF pode ocultar o cursor quando o foco chega antes do body visivel.
RegisterNUICallback("ready", function(_, cb)
  if _open then
    if SetCursorLocation then SetCursorLocation(0.5, 0.5) end
    SetNuiFocus(true, true)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
  end
  cb({ ok = _open })
end)

RegisterNUICallback("back", function(_, cb)
  if not _open or _submitting or not _payload or _payload.canBack ~= true then
    cb({ ok = false })
    return
  end
  _submitting = true
  SendNUIMessage({ action = "busy", label = "RETORNANDO…" })
  TriggerServerEvent(E.REQUEST_BACK)
  cb({ ok = true })
end)

AddEventHandler("onResourceStop", function(resource)
  if resource ~= GetCurrentResourceName() then return end
  if _open then
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    ClearTimecycleModifier()
    DoScreenFadeIn(0)
    SendNUIMessage({ action = "close" })
  end
  _open = false
  _submitting = false
  _accepted = false
  _physicalReady = false
  _payload = nil
end)
