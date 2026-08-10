-- client/remote.lua - ponte NUI do controle remoto

local CFG = VHubOutdoors.cfg
local E = VHubOutdoors.E
local state = nil

local function close_remote()
  if not state then return end
  state = nil
  SetNuiFocus(false, false)
  SendNUIMessage({ type = 'remote:close', data = {} })
end

local function valid_payload(payload)
  if type(payload) ~= 'table'
      or type(payload.token) ~= 'string'
      or #payload.token ~= 32
      or not payload.token:match('^%x+$')
      or type(payload.title) ~= 'string'
      or #payload.title > CFG.limits.max_title
      or type(payload.url) ~= 'string'
      or #payload.url > CFG.limits.max_url then
    return false
  end
  local id = VHubOutdoors.finite(payload.id)
  local volume = VHubOutdoors.finite(payload.volume)
  return id and id % 1 == 0 and id >= 1
    and volume and volume % 1 == 0 and volume >= 0 and volume <= 100
end

RegisterNetEvent(E.OPEN_REMOTE_UI, function(payload)
  if not valid_payload(payload) then return end
  TriggerEvent('vhub_outdoors:client:closeCreator')
  state = { token = payload.token }
  SetNuiFocus(true, true)
  SendNUIMessage({ type = 'remote:open', data = payload })
end)

RegisterNetEvent(E.UPDATE_REMOTE_UI, function(payload)
  if not state or type(payload) ~= 'table'
      or payload.token ~= state.token
      or type(payload.action) ~= 'string' then
    return
  end
  local item = payload.item
  if item ~= nil and not valid_payload(item) then item = nil end
  SendNUIMessage({
    type = 'remote:update',
    data = {
      action = payload.action,
      ok = payload.ok == true,
      err = type(payload.err) == 'string' and payload.err or nil,
      item = item,
    },
  })
end)

AddEventHandler('vhub_outdoors:client:closeRemote', close_remote)

RegisterNUICallback('remoteClose', function(_, cb)
  close_remote()
  cb({ ok = true })
end)

RegisterNUICallback('remoteSetMedia', function(data, cb)
  if not state or type(data) ~= 'table' then
    cb({ ok = false, err = 'invalid_state' })
    return
  end
  for key in pairs(data) do
    if key ~= 'url' then
      cb({ ok = false, err = 'invalid_payload' })
      return
    end
  end
  if type(data.url) ~= 'string' or #data.url > CFG.limits.max_url
      or not VHubOutdoors.parseMedia(data.url) then
    cb({ ok = false, err = 'invalid_media' })
    return
  end
  TriggerServerEvent(E.REMOTE_SET_MEDIA, {
    token = state.token,
    url = data.url,
  })
  cb({ ok = true })
end)

RegisterNUICallback('remoteSetVolume', function(data, cb)
  local volume = type(data) == 'table' and VHubOutdoors.finite(data.volume) or nil
  if not state or not volume or volume % 1 ~= 0
      or volume < 0 or volume > 100 then
    cb({ ok = false, err = 'invalid_volume' })
    return
  end
  TriggerServerEvent(E.REMOTE_SET_VOLUME, {
    token = state.token,
    volume = volume,
  })
  cb({ ok = true })
end)

RegisterNUICallback('remoteMove', function(_, cb)
  if not state then
    cb({ ok = false, err = 'invalid_state' })
    return
  end
  local token = state.token
  close_remote()
  TriggerServerEvent(E.REMOTE_REQUEST_MOVE, { token = token })
  cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then close_remote() end
end)
