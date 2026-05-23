-- shared/utils.lua - utilitarios puros do vhub_racha.

VHubRachaUtils = {}
local U = VHubRachaUtils

-- Retorna inteiro limitado ao intervalo informado.
function U.clamp_int(value, min, max)
  local n = math.floor(tonumber(value) or min)
  if n < min then return min end
  if n > max then return max end
  return n
end

-- Sanitiza identificadores internos.
function U.sanitize_id(value)
  if type(value) ~= 'string' then return '' end
  return value:lower():gsub('[^a-z0-9_%-]', ''):sub(1, 48)
end

-- Sanitiza apelido de ranking.
function U.sanitize_nick(value)
  if type(value) ~= 'string' then return '' end
  local s = value:gsub('[\r\n\t]', ' '):gsub('[^%w%s_%-%.]', ''):gsub('%s+', ' ')
  s = s:match('^%s*(.-)%s*$') or ''
  return s:sub(1, 24)
end

-- Formata milissegundos como mm:ss.mmm.
function U.time_ms(ms)
  local n = math.max(0, math.floor(tonumber(ms) or 0))
  return ('%02d:%02d.%03d'):format(math.floor(n / 60000), math.floor((n % 60000) / 1000), n % 1000)
end

-- Retorna pista por id.
function U.track_by_id(track_id)
  local id = U.sanitize_id(track_id)
  for _, track in ipairs(VHubRachaTracks or {}) do
    if track.id == id then return track end
  end
  return nil
end

-- Copia uma pista para payload client-safe.
function U.public_track(track)
  if type(track) ~= 'table' then return nil end
  local checkpoints, grid = {}, {}
  for i, p in ipairs(track.checkpoints or {}) do checkpoints[i] = { x = p.x, y = p.y, z = p.z } end
  for i, p in ipairs(track.grid or {}) do grid[i] = { x = p.x, y = p.y, z = p.z, h = p.h or 0.0 } end
  return {
    id = track.id, label = track.label, district = track.district, kind = track.kind,
    illegal = track.illegal == true, start = track.start, grid = grid, checkpoints = checkpoints,
    laps = track.laps or 1, min_players = track.min_players or 1,
    max_players = track.max_players or #grid, limit_seconds = track.limit_seconds or 300,
    default_fee = track.default_fee or 0,
    checkpoint_radius = track.checkpoint_radius or VHubRachaCfg.CHECKPOINT_RADIUS,
    color = track.color or VHubRachaCfg.COLOR,
  }
end

-- Retorna catalogo publico de pistas.
function U.public_tracks()
  local out = {}
  for i, track in ipairs(VHubRachaTracks or {}) do out[i] = U.public_track(track) end
  return out
end

-- Valida classe de veiculo contra a pista.
function U.vehicle_allowed(track, class)
  local allowed = track and track.vehicle_classes
  if type(allowed) ~= 'table' or next(allowed) == nil then return true end
  return allowed[tonumber(class) or -1] == true
end
