-- server/audio.lua - audio 3D limitado, delegado ao owner vhub_wow

local CFG = VHubOutdoors.cfg
local Core = VHubOutdoors.Core
local heard = {}
local failures = {}
local running = true
local cached_revision = -1
local cached_sources = {}

local function sound_name(id)
  return ('vhub_outdoor_%d'):format(id)
end

local function media_url(item)
  if item.media_type == 'youtube' then
    return ('https://www.youtube.com/watch?v=%s'):format(item.source)
  end
  return item.media_type == 'video' and item.source or nil
end

local function center_of(item)
  return {
    x = (item.top_left.x + item.bottom_right.x) * 0.5,
    y = (item.top_left.y + item.bottom_right.y) * 0.5,
    z = (item.top_left.z + item.bottom_right.z) * 0.5,
  }
end

local function signature(item, url, center)
  return ('%s:%s:%.4f:%.4f:%.4f'):format(
    item.media_type, url, center.x, center.y, center.z
  )
end

local function destroy_for(src, id)
  local ok, result = pcall(function()
    return exports.vhub_wow:Destroy({ src }, sound_name(id))
  end)
  return ok and result == true
end

local function play_for(src, candidate)
  local ok, result = pcall(function()
    return exports.vhub_wow:PlayAtCoords(
      { src },
      sound_name(candidate.id),
      candidate.url,
      candidate.volume,
      candidate.center,
      CFG.audio.distance,
      true,
      CFG.audio.duck_strength
    )
  end)
  return ok and result == true
end

local function set_volume_for(src, id, volume)
  local ok, result = pcall(function()
    return exports.vhub_wow:SetVolume({ src }, sound_name(id), volume)
  end)
  return ok and result == true
end

local function schedule_retry(player_failures, id, now)
  local failure = player_failures[id] or { attempts = 0 }
  failure.attempts = math.min(failure.attempts + 1, 5)
  failure.retry_at = now + math.min(
    CFG.audio.retry_max_ms,
    CFG.audio.retry_base_ms * 2 ^ (failure.attempts - 1)
  )
  player_failures[id] = failure
end

local function sources()
  if cached_revision == Core.revision then return cached_sources end
  local list = {}
  for id, item in pairs(Core.active) do
    local url = media_url(item)
    if url then
      local center = center_of(item)
      list[#list + 1] = {
        id = id,
        url = url,
        center = center,
        volume = item.volume,
        signature = signature(item, url, center),
      }
    end
  end
  cached_revision = Core.revision
  cached_sources = list
  return cached_sources
end

local function player_coords(src)
  local ped = GetPlayerPed(src)
  if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
  local coords = GetEntityCoords(ped)
  if not coords then return nil end
  return coords
end

local function synchronize_player(src, available)
  local coords = player_coords(src)
  local current = heard[src] or {}
  local player_failures = failures[src] or {}
  if not coords then
    for id in pairs(current) do
      if destroy_for(src, id) then current[id] = nil end
    end
    heard[src] = next(current) and current or nil
    return
  end

  local candidates = {}
  for _, source in ipairs(available) do
    local dx = coords.x - source.center.x
    local dy = coords.y - source.center.y
    local dz = coords.z - source.center.z
    local distance_squared = dx * dx + dy * dy + dz * dz
    local limit = current[source.id]
      and CFG.audio.unload_distance
      or CFG.audio.activation_distance
    if distance_squared <= limit * limit then
      local candidate = {
        id = source.id,
        url = source.url,
        center = source.center,
        volume = source.volume,
        signature = source.signature,
        distance_squared = distance_squared,
      }
      local inserted = false
      for index = 1, #candidates do
        local current_candidate = candidates[index]
        if distance_squared < current_candidate.distance_squared
            or distance_squared == current_candidate.distance_squared
              and candidate.id < current_candidate.id then
          table.insert(candidates, index, candidate)
          inserted = true
          break
        end
      end
      if not inserted then candidates[#candidates + 1] = candidate end
      if #candidates > CFG.audio.max_sources then
        candidates[#candidates] = nil
      end
    end
  end

  local allowed = {}
  for _, candidate in ipairs(candidates) do
    allowed[candidate.id] = candidate
  end

  local now = GetGameTimer()
  for id, active in pairs(current) do
    local candidate = allowed[id]
    local old_signature = type(active) == 'table' and active.signature or active
    local pending_timeout = type(active) == 'table'
      and active.state == 'pending'
      and now >= active.deadline
    if not candidate or candidate.signature ~= old_signature then
      if destroy_for(src, id) then current[id] = nil end
    elseif pending_timeout and destroy_for(src, id) then
      current[id] = nil
      schedule_retry(player_failures, id, now)
    elseif type(active) == 'table'
        and math.abs((active.volume or -1.0) - candidate.volume) > 0.001
        and set_volume_for(src, id, candidate.volume) then
      active.volume = candidate.volume
    end
  end

  for id in pairs(player_failures) do
    if not allowed[id] then player_failures[id] = nil end
  end

  for id, candidate in pairs(allowed) do
    local failure = player_failures[id]
    if not current[id] and (not failure or now >= failure.retry_at)
        and play_for(src, candidate) then
      current[id] = {
        signature = candidate.signature,
        state = 'pending',
        deadline = now + CFG.audio.ready_timeout_ms,
        volume = candidate.volume,
      }
    end
  end
  heard[src] = next(current) and current or nil
  failures[src] = next(player_failures) and player_failures or nil
end

CreateThread(function()
  while running do
    local available = Core.ready and sources() or {}
    for _, raw_src in ipairs(GetPlayers()) do
      local src = tonumber(raw_src)
      if src then synchronize_player(src, available) end
    end
    Wait(#available > 0 and CFG.audio.active_check_ms or CFG.audio.idle_check_ms)
  end
end)

AddEventHandler('playerDropped', function()
  heard[source] = nil
  failures[source] = nil
end)

AddEventHandler('onResourceStart', function(resource)
  if resource == 'vhub_wow' then
    heard = {}
    failures = {}
    cached_revision = -1
  end
end)

AddEventHandler('vhub_wow:server:audioLifecycle', function(src, name, status)
  src = tonumber(src)
  local id = type(name) == 'string'
    and tonumber(name:match('^vhub_outdoor_(%d+)$'))
    or nil
  local current = src and heard[src] or nil
  if not id or not current or not current[id] then return end
  if status == 'ready' then
    local active = current[id]
    if type(active) == 'table' then
      active.state = 'ready'
      active.deadline = nil
    end
    local by_source = failures[src]
    if by_source then
      by_source[id] = nil
      failures[src] = next(by_source) and by_source or nil
    end
    return
  end
  if status ~= 'error' then return end

  current[id] = nil
  heard[src] = next(current) and current or nil
  local by_source = failures[src] or {}
  schedule_retry(by_source, id, GetGameTimer())
  failures[src] = by_source
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  running = false
  for src, active in pairs(heard) do
    for id in pairs(active) do destroy_for(src, id) end
  end
  heard = {}
  failures = {}
end)
