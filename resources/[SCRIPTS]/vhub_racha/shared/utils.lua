-- shared/utils.lua — utilitarios puros (sem natives, sem IO).

VHubRachaUtils = {}
local U = VHubRachaUtils

function U.clamp_int(value, min, max)
  local n = math.floor(tonumber(value) or min)
  if n < min then return min end
  if n > max then return max end
  return n
end

function U.sanitize_id(value)
  if type(value) ~= 'string' then return '' end
  return value:lower():gsub('[^a-z0-9_%-]', ''):sub(1, 48)
end

function U.sanitize_label(value)
  if type(value) ~= 'string' then return '' end
  local s = value:gsub('[\r\n\t]', ' '):gsub('%s+', ' ')
  s = s:match('^%s*(.-)%s*$') or ''
  return s:sub(1, 80)
end

function U.sanitize_nick(value)
  if type(value) ~= 'string' then return '' end
  local s = value:gsub('[\r\n\t]', ' ')
  s = s:gsub('[^%w%sÀ-ÿ_%-%.]', ''):gsub('%s+', ' ')
  s = s:match('^%s*(.-)%s*$') or ''
  return s:sub(1, 48)
end

function U.time_ms(ms)
  local n = math.max(0, math.floor(tonumber(ms) or 0))
  return ('%02d:%02d.%03d'):format(
    math.floor(n / 60000),
    math.floor((n % 60000) / 1000),
    n % 1000)
end

function U.time_short_ms(ms)
  local n = math.max(0, math.floor(tonumber(ms) or 0))
  return ('%d:%02d.%02d'):format(
    math.floor(n / 60000),
    math.floor((n % 60000) / 1000),
    math.floor((n % 1000) / 10))
end

function U.fmt_num(n, sep)
  sep = sep or '.'
  local s = tostring(math.floor(tonumber(n) or 0))
  local out, c = '', 0
  for i = #s, 1, -1 do
    out = s:sub(i, i) .. out; c = c + 1
    if c % 3 == 0 and i > 1 then out = sep .. out end
  end
  return out
end

function U.short_id()
  local chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
  local out = ''
  for _ = 1, 8 do
    local i = math.random(1, #chars)
    out = out .. chars:sub(i, i)
  end
  return out
end

function U.copy(t)
  if type(t) ~= 'table' then return t end
  local out = {}; for k, v in pairs(t) do out[k] = v end; return out
end

function U.deep_copy(t, seen)
  if type(t) ~= 'table' then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}; seen[t] = out
  for k, v in pairs(t) do out[U.deep_copy(k, seen)] = U.deep_copy(v, seen) end
  return out
end

-- Encontra track no catalogo carregado (server) ou config (client)
function U.find_track(track_id, catalog)
  if not track_id or track_id == '' then return nil end
  if type(catalog) == 'table' then
    if catalog[track_id] then return catalog[track_id] end
    for _, t in pairs(catalog) do
      if t.id == track_id then return t end
    end
  end
  if type(VHubRachaTracks) == 'table' then
    for _, t in ipairs(VHubRachaTracks) do
      if t.id == track_id then return t end
    end
  end
  return nil
end
