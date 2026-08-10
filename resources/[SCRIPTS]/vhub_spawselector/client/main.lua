-- UI de eleicao de coordenada. Nao toca ped, bucket ou teleporte.

local E = VHubSpawnSelector.E
local _payload = nil
local _open = false
local _submitting = false
local _accepted = false
local _physicalReady = false

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
  Citizen.SetTimeout(750, function()
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
