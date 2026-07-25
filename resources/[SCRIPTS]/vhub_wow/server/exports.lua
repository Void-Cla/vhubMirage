-- server/exports.lua — porta server-side validada e default-deny do vhub_wow

local E = VHubWOW.E
local operationAt = {}


-- ============================================================
-- GUARDS
-- ============================================================

local function finite(value, fallback)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then
    return fallback
  end
  return number
end

local function trusted_caller()
  local caller = GetInvokingResource()
  if type(caller) ~= 'string' then return nil end
  for _, trusted in ipairs(WOW_Config.TrustedResources) do
    if trusted == caller then return caller end
  end
  return nil
end

local function targets_of(raw)
  if type(raw) ~= 'table' then return {} end
  local out, seen = {}, {}
  local limit = math.min(#raw, 128)
  for index = 1, limit do
    local src = finite(raw[index])
    if src and src % 1 == 0 and src >= 1 and src <= 65535
        and not seen[src] and GetPlayerName(src) then
      seen[src] = true
      out[#out + 1] = src
    end
  end
  return out
end

local function call_allowed(action, targets)
  local caller = trusted_caller()
  local recipients = caller and targets_of(targets) or {}
  if #recipients == 0 then return nil end
  local now = GetGameTimer()
  local interval = action == 'volume' and 100 or WOW_Config.RateLimitMs
  local allowed = {}
  for _, src in ipairs(recipients) do
    local key = caller .. ':' .. action .. ':' .. tostring(src)
    local previous = operationAt[key]
    if not previous or now - previous >= interval then
      operationAt[key] = now
      allowed[#allowed + 1] = src
    end
  end
  return #allowed > 0 and allowed or nil
end

local function volume_of(value)
  return math.max(0.0, math.min(1.0, finite(value, 0.5)))
end

local function distance_of(value)
  return math.max(5.0, math.min(WOW_Config.MaxDistance,
    finite(value, WOW_Config.DefaultDistance)))
end

local function emit(recipients, event_name, ...)
  for _, src in ipairs(recipients) do TriggerClientEvent(event_name, src, ...) end
  return true
end


-- ============================================================
-- PLAYBACK
-- ============================================================

-- Toca som 2D nos jogadores validados.
local function Play(targets, sound_name, url, volume, loop)
  if not WOW_Config.isValidSoundName(sound_name) or not WOW_Config.isPlayableUrl(url) then return false end
  local recipients = call_allowed('play', targets)
  return recipients and emit(recipients, E.PLAY, sound_name, url, volume_of(volume), loop == true) or false
end
exports('Play', Play)

-- Toca som 3D ancorado em entidade de rede.
local function PlayAtEntity(targets, sound_name, url, volume, net_id, distance, loop)
  net_id = finite(net_id)
  if not WOW_Config.isValidSoundName(sound_name)
      or not WOW_Config.isPlayableUrl(url) or not net_id
      or net_id % 1 ~= 0 or net_id < 1 then return false end
  local entity = NetworkGetEntityFromNetworkId(net_id)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
  local recipients = call_allowed('play_entity', targets)
  return recipients and emit(recipients, E.PLAY_AT_ENTITY, sound_name, url, volume_of(volume),
    net_id, distance_of(distance), loop == true) or false
end
exports('PlayAtEntity', PlayAtEntity)

-- Toca som 3D ancorado em coordenada primitiva.
local function PlayAtCoords(targets, sound_name, url, volume, coords, distance, loop)
  if not WOW_Config.isValidSoundName(sound_name)
      or not WOW_Config.isPlayableUrl(url) or type(coords) ~= 'table' then return false end
  local x, y, z = finite(coords.x), finite(coords.y), finite(coords.z)
  if not x or not y or not z then return false end
  local recipients = call_allowed('play_coords', targets)
  return recipients and emit(recipients, E.PLAY_AT_COORDS, sound_name, url, volume_of(volume),
    { x = x, y = y, z = z }, distance_of(distance), loop == true) or false
end
exports('PlayAtCoords', PlayAtCoords)

-- Destroi um som nos jogadores validados.
local function Destroy(targets, sound_name)
  if not WOW_Config.isValidSoundName(sound_name) then return false end
  local recipients = call_allowed('destroy', targets)
  return recipients and emit(recipients, E.DESTROY, sound_name) or false
end
exports('Destroy', Destroy)


-- ============================================================
-- CONTROLES
-- ============================================================

-- Pausa um som existente.
local function Pause(targets, sound_name)
  if not WOW_Config.isValidSoundName(sound_name) then return false end
  local recipients = call_allowed('pause', targets)
  return recipients and emit(recipients, E.PAUSE, sound_name) or false
end
exports('Pause', Pause)

-- Retoma um som existente.
local function Resume(targets, sound_name)
  if not WOW_Config.isValidSoundName(sound_name) then return false end
  local recipients = call_allowed('resume', targets)
  return recipients and emit(recipients, E.RESUME, sound_name) or false
end
exports('Resume', Resume)

-- Define o volume-base sem incorporar atenuacao ou ducking.
local function SetVolume(targets, sound_name, volume)
  if not WOW_Config.isValidSoundName(sound_name) then return false end
  local recipients = call_allowed('volume', targets)
  return recipients and emit(recipients, E.SET_VOLUME, sound_name, volume_of(volume)) or false
end
exports('SetVolume', SetVolume)

-- Define o alcance espacial validado.
local function SetDistance(targets, sound_name, distance)
  if not WOW_Config.isValidSoundName(sound_name) then return false end
  local recipients = call_allowed('distance', targets)
  return recipients and emit(recipients, E.SET_DISTANCE, sound_name, distance_of(distance)) or false
end
exports('SetDistance', SetDistance)


-- ============================================================
-- MUSICA
-- ============================================================

-- Inicia busca e devolve resultados somente ao jogador solicitante.
local function RequestSearch(player_src, query)
  if not trusted_caller() then return false end
  player_src = finite(player_src)
  local accepted = WOW_Config.acceptSearchInput(query)
  if not player_src or player_src % 1 ~= 0 or not GetPlayerName(player_src)
      or not accepted then return false end

  if accepted.kind == 'video' then
    TriggerClientEvent(E.SEARCH_RESULTS, player_src, query, {
      {
        id = accepted.id,
        title = 'Link do YouTube',
        artist = 'YouTube',
        url = WOW_Config.buildEmbedUrl(accepted.id),
        duration = 0,
      },
    })
    return true
  end

  WOW_Music.searchTracks(accepted.q, function(items)
    if GetPlayerName(player_src) then
      TriggerClientEvent(E.SEARCH_RESULTS, player_src, query, items or {})
    end
  end)
  return true
end
exports('RequestSearch', RequestSearch)

-- Retorna uma faixa copiada do cache curado.
local function GetRadioTrack()
  if not trusted_caller() then return nil end
  return WOW_Music.radioTrackSync()
end
exports('GetRadioTrack', GetRadioTrack)

AddEventHandler('playerDropped', function()
  local suffix = ':' .. tostring(source)
  for key in pairs(operationAt) do
    if key:sub(-#suffix) == suffix then operationAt[key] = nil end
  end
end)
