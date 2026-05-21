-- shared/utils.lua  utilit rios puros
---@diagnostic disable: undefined-global
VHubAdmin   = VHubAdmin or {}
VHubAdmin.U = VHubAdmin.U or {}
local U     = VHubAdmin.U

function U.now() return os.time() end

function U.fmtDate(ts)
  if not ts or ts == 0 then return ' ' end
  return os.date('%d/%m %H:%M', tonumber(ts))
end

function U.fmtDur(secs)
  secs = math.max(0, math.floor(secs or 0))
  if secs >= 86400 then return ('%dd %02dh'):format(secs / 86400, (secs % 86400) / 3600) end
  if secs >= 3600  then return ('%dh %02dm'):format(secs / 3600, (secs % 3600) / 60)   end
  if secs >= 60    then return ('%dm %02ds'):format(secs / 60, secs % 60)              end
  return ('%ds'):format(secs)
end

function U.clamp(v, mn, mx) return math.max(mn, math.min(mx, v)) end

function U.trim(s)
  if type(s) ~= 'string' then return '' end
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- escapa string para uso em chat/feedpost (anti-XSS)
function U.safeText(s, maxlen)
  if type(s) ~= 'string' then s = tostring(s or '') end
  s = s:gsub('[<>&"\'\\]', ''):gsub('[%c]', ' ')
  if maxlen and #s > maxlen then s = s:sub(1, maxlen) end
  return s
end

-- valida ID server (1..1024 t pico FXServer)
function U.toSrc(v)
  local n = tonumber(v); if not n then return nil end
  if n < 1 or n > 4096 then return nil end
  return math.floor(n)
end

-- valida coords
function U.validCoords(p)
  if type(p) ~= 'table' then return false end
  local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
  if not (x and y and z) then return false end
  if math.abs(x) > 9000 or math.abs(y) > 9000 then return false end
  if z < -300 or z > 3500 then return false end
  return true
end

-- JSON safe
function U.jenc(t)
  if t == nil then return nil end
  local ok, s = pcall(json.encode, t); return ok and s or nil
end

function U.jdec(s)
  if type(s) ~= 'string' or s == '' then return nil end
  local ok, v = pcall(json.decode, s); return ok and v or nil
end
