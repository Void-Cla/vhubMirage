-- client/engine.lua — VRAM local e atenuacao espacial do vhub_wow

local E = VHubWOW.E
local sounds = {}
local engineRunning = false

local NEAR_RADIUS = 4.0


-- ============================================================
-- VALIDACAO / NUI
-- ============================================================

local function finite(value, fallback)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then
    return fallback
  end
  return number
end

local function volume_of(value)
  return math.max(0.0, math.min(1.0, finite(value, 0.5)))
end

local function distance_of(value)
  return math.max(5.0, math.min(WOW_Config.MaxDistance,
    finite(value, WOW_Config.DefaultDistance)))
end

local function send(type_name, data)
  SendNUIMessage({ type = type_name, data = data or {} })
end

local function positional(data)
  return data and (data.netId ~= nil or data.coords ~= nil)
end

local function active_count()
  local count = 0
  for _, data in pairs(sounds) do
    if data.playing then count = count + 1 end
  end
  return count
end

local function has_active_positional()
  for _, data in pairs(sounds) do
    if data.playing and positional(data) then return true end
  end
  return false
end

local function replace_sound(name, data)
  sounds[name] = data
  VHubWOWClient.setSoundCount(active_count())
end

local function remove_sound(name)
  local data = sounds[name]
  if not data then return false end
  sounds[name] = nil
  VHubWOWClient.setSoundCount(active_count())
  return true
end


-- ============================================================
-- ATENUACAO
-- ============================================================

local function distance_factor(distance, maximum)
  if distance <= NEAR_RADIUS then return 1.0 end
  if distance >= maximum then return 0.0 end
  return 1.0 - ((distance - NEAR_RADIUS) / (maximum - NEAR_RADIUS))
end

local function source_coords(data)
  if data.netId then
    local entity = NetworkGetEntityFromNetworkId(data.netId)
    if entity == 0 or not DoesEntityExist(entity) then return nil end
    return GetEntityCoords(entity)
  end
  if data.coords then return data.coords end
  return nil
end

local function positional_volume(data)
  local coords = source_coords(data)
  if not coords then return 0.0 end
  local listener = PlayerPedId()
  if listener == 0 or not DoesEntityExist(listener) then return 0.0 end
  return data.baseVolume * distance_factor(#(GetEntityCoords(listener) - coords), data.distance)
end

local function start_engine()
  if engineRunning or not has_active_positional() then return end
  engineRunning = true

  CreateThread(function()
    while has_active_positional() do
      local listener = GetEntityCoords(PlayerPedId())

      for name, data in pairs(sounds) do
        if positional(data) and data.playing then
          local coords = source_coords(data)
          local source_volume = coords
            and data.baseVolume * distance_factor(#(listener - coords), data.distance) or 0.0
          local crossed_zero = data.lastSent ~= nil
            and ((source_volume == 0.0) ~= (data.lastSent == 0.0))
          if data.lastSent == nil or math.abs(source_volume - data.lastSent) > 0.02 or crossed_zero then
            data.lastSent = source_volume
            send('wow:audio:volume', { name = name, volume = source_volume })
          end
        end
      end
      Wait(150)
    end

    engineRunning = false
    if has_active_positional() then start_engine() end
  end)
end


-- ============================================================
-- PLAYBACK
-- ============================================================

local function valid_play(name, url)
  return WOW_Config.isValidSoundName(name) and WOW_Config.isPlayableUrl(url)
end

local function play_message(name, url, volume, loop)
  send('wow:audio:play', {
    name = name,
    url = url,
    volume = volume,
    loop = loop == true,
    streamer_mode = VHubWOWClient.isStreamerMode(),
  })
end

RegisterNetEvent(E.PLAY, function(name, url, volume, loop)
  if not valid_play(name, url) then return end
  local base = volume_of(volume)
  replace_sound(name, { url = url, baseVolume = base, loop = loop == true, playing = true })
  play_message(name, url, base, loop)
end)

RegisterNetEvent(E.PLAY_AT_ENTITY, function(name, url, volume, net_id, distance, loop)
  net_id = finite(net_id)
  if not valid_play(name, url) or not net_id or net_id % 1 ~= 0 or net_id < 1 then return end
  local base = volume_of(volume)
  local data = {
    url = url,
    baseVolume = base,
    distance = distance_of(distance),
    loop = loop == true,
    netId = net_id,
    playing = true,
    lastSent = nil,
  }
  replace_sound(name, data)
  local initial = positional_volume(data)
  data.lastSent = initial
  play_message(name, url, initial, loop)
  start_engine()
end)

RegisterNetEvent(E.PLAY_AT_COORDS, function(name, url, volume, coords, distance, loop)
  if not valid_play(name, url) or type(coords) ~= 'table' then return end
  local x, y, z = finite(coords.x), finite(coords.y), finite(coords.z)
  if not x or not y or not z then return end
  local base = volume_of(volume)
  local data = {
    url = url,
    baseVolume = base,
    distance = distance_of(distance),
    loop = loop == true,
    coords = vec3(x, y, z),
    playing = true,
    lastSent = nil,
  }
  replace_sound(name, data)
  local initial = positional_volume(data)
  data.lastSent = initial
  play_message(name, url, initial, loop)
  start_engine()
end)

RegisterNetEvent(E.DESTROY, function(name)
  if not WOW_Config.isValidSoundName(name) then return end
  remove_sound(name)
  send('wow:audio:destroy', { name = name })
end)

RegisterNetEvent(E.PAUSE, function(name)
  local data = sounds[name]
  if not data then return end
  data.playing = false
  VHubWOWClient.setSoundCount(active_count())
  send('wow:audio:pause', { name = name })
end)

RegisterNetEvent(E.RESUME, function(name)
  local data = sounds[name]
  if not data then return end
  data.playing = true
  if positional(data) then
    local initial = positional_volume(data)
    data.lastSent = initial
    send('wow:audio:volume', { name = name, volume = initial })
  else
    data.lastSent = nil
  end
  VHubWOWClient.setSoundCount(active_count())
  send('wow:audio:resume', { name = name })
  if positional(data) then start_engine() end
end)

RegisterNetEvent(E.SET_VOLUME, function(name, volume)
  local data = sounds[name]
  if not data then return end
  data.baseVolume = volume_of(volume)
  data.lastSent = nil
  if positional(data) and data.playing then
    local current = positional_volume(data)
    data.lastSent = current
    send('wow:audio:volume', { name = name, volume = current })
  elseif not positional(data) then
    send('wow:audio:volume', { name = name, volume = data.baseVolume })
  end
end)

RegisterNetEvent(E.SET_DISTANCE, function(name, distance)
  local data = sounds[name]
  if not data or not positional(data) then return end
  data.distance = distance_of(distance)
  data.lastSent = nil
end)

RegisterNUICallback('audioLifecycle', function(data, cb)
  local name = type(data) == 'table' and data.name
  local status = type(data) == 'table' and data.status
  if not WOW_Config.isValidSoundName(name) or (status ~= 'ended' and status ~= 'error') then
    cb({ ok = false, err = 'invalid_payload' })
    return
  end
  local removed = remove_sound(name)
  if removed then TriggerEvent(E.AUDIO_LIFECYCLE_LOCAL, name, status) end
  cb({ ok = removed, err = removed and nil or 'sound_not_found' })
end)


-- ============================================================
-- QUERIES
-- ============================================================

-- Verifica se um som existe na VRAM local.
exports('soundExists', function(name)
  return sounds[name] ~= nil
end)

-- Verifica se um som esta tocando.
exports('isPlaying', function(name)
  return sounds[name] ~= nil and sounds[name].playing == true
end)

-- Retorna copia somente-leitura do estado local do som.
exports('getInfo', function(name)
  local data = sounds[name]
  if not data then return nil end
  return {
    url = data.url,
    volume = data.baseVolume,
    distance = data.distance,
    loop = data.loop,
    playing = data.playing,
  }
end)
