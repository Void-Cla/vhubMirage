-- shared/utils.lua  utilit rios puros (sem side-effects)
---@diagnostic disable: undefined-global
VHubGarage = VHubGarage or {}
VHubGarage.U = VHubGarage.U or {}

-- timestamp Unix (segundos)
function VHubGarage.U.now() return os.time() end

-- formata dinheiro: 1234567   "R$ 1.234.567"
function VHubGarage.U.fmtMoney(n)
  local s, res, c = tostring(math.floor(n or 0)), '', 0
  for i = #s, 1, -1 do
    res = s:sub(i, i) .. res; c = c + 1
    if c % 3 == 0 and i > 1 then res = '.' .. res end
  end
  return 'R$ ' .. res
end

-- formata tempo restante: 3725s   "1h 02m"
function VHubGarage.U.fmtDur(secs)
  secs = math.max(0, math.floor(secs or 0))
  if secs >= 86400 then return ('%dd %02dh'):format(secs / 86400, (secs % 86400) / 3600) end
  if secs >= 3600  then return ('%dh %02dm'):format(secs / 3600,  (secs % 3600) / 60)  end
  if secs >= 60    then return ('%dm %02ds'):format(secs / 60,    secs % 60)            end
  return ('%ds'):format(secs)
end

-- valida e normaliza placa  retorna string upper trim ou nil
function VHubGarage.U.normalizePlate(plate)
  if type(plate) ~= 'string' then return nil end
  local p = plate:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  if not p or #p < 2 or #p > 8 then return nil end
  if not p:match('^[A-Z0-9][A-Z0-9 ]*[A-Z0-9]$') then return nil end
  return p
end

-- gera placa aleat ria padr o "LLL DDDD"
function VHubGarage.U.randomPlate()
  return string.format('%s%s%s %d%d%d%d',
    string.char(65 + math.random(0, 25)),
    string.char(65 + math.random(0, 25)),
    string.char(65 + math.random(0, 25)),
    math.random(0, 9), math.random(0, 9),
    math.random(0, 9), math.random(0, 9))
end

-- clamp num rico
function VHubGarage.U.clamp(v, mn, mx) return math.max(mn, math.min(mx, v)) end

-- cl one shallow de tabela
function VHubGarage.U.shallow(t)
  if type(t) ~= 'table' then return t end
  local out = {}; for k, v in pairs(t) do out[k] = v end; return out
end

-- json safe encode/decode com fallback
function VHubGarage.U.jenc(t)
  if t == nil then return nil end
  local ok, s = pcall(json.encode, t); return ok and s or nil
end

function VHubGarage.U.jdec(s)
  if type(s) ~= 'string' or s == '' then return nil end
  local ok, v = pcall(json.decode, s); return ok and v or nil
end

-- whitelist de chaves aceitas em customization (payload do cliente e hostil)
local CUST_KEYS = {
  colours = true, extra_colours = true, plate_index = true, wheel_type = true,
  window_tint = true, livery = true, turbo = true, smoke = true, xenon = true,
  mods = true, neons = true, neon_colour = true, model = true,
}

-- filtra customization vinda do cliente: whitelist de chaves + cap de 8 KB no JSON
function VHubGarage.U.sanitizeCustomization(c)
  if type(c) ~= 'table' then return nil end
  local out = {}
  for k, v in pairs(c) do
    if CUST_KEYS[k] then out[k] = v end
  end
  local j = VHubGarage.U.jenc(out)
  if not j or #j > 8192 then return nil end
  return out
end

-- número finito clampado, ou nil (rejeita NaN/±inf ANTES do clamp — payload hostil)
function VHubGarage.U.finiteNum(v, lo, hi)
  if type(v) ~= 'number' or v ~= v or math.abs(v) == math.huge then return nil end
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end

-- valida coords (anti-cheat client)
function VHubGarage.U.validCoords(p)
  if type(p) ~= 'table' then return false end
  local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
  if not (x and y and z) then return false end
  if math.abs(x) > 9000 or math.abs(y) > 9000 then return false end
  if z < -300 or z > 3500 then return false end
  return true
end

-- defensive deep copy (n vel max 3)
function VHubGarage.U.deep3(t, lvl)
  lvl = lvl or 0
  if type(t) ~= 'table' or lvl >= 3 then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = VHubGarage.U.deep3(v, lvl + 1) end
  return out
end
