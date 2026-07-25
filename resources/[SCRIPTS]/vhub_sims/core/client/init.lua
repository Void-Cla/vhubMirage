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


-- ============================================================
-- EVENTOS AUTORITATIVOS
-- ============================================================

RegisterNetEvent(E.CLI_STUDIO_OPEN, function(payload)
  if type(payload) ~= 'table' or type(payload.session_id) ~= 'string' then return end
  if active then closeLocal(true) end

  active = { session_id = payload.session_id, mode = payload.mode }
  local sessionId = payload.session_id

  -- Budget: 20 Hz por no máximo 10 s; aguarda estágio HSS (model load 5s + MovePed 3s + margem).
  Citizen.CreateThread(function()
    local deadline = GetGameTimer() + 10000
    while active and active.session_id == sessionId and GetGameTimer() < deadline do
      if hss('beginCustomizationPreview', payload.current) then
        if not hss('setCustomizationCamera', payload.mode == 'barber' and 'head' or 'body', 0.0) then
          failSafe()
          return
        end
        SetNuiFocus(true, true)
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
  local views = { head = true, torso = true, body = true, legs = true, feet = true }
  local heading = type(data) == 'table' and tonumber(data.heading) or nil
  if not active or type(data) ~= 'table' or not views[data.view]
    or not heading or heading ~= heading or heading < -180 or heading > 180
    or not hss('setCustomizationCamera', data.view, heading) then
    cb({ ok = false })
    failSafe()
    return
  end
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
