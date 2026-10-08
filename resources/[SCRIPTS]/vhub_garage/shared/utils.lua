-- shared/utils.lua  utilit rios puros (sem side-effects)
---@diagnostic disable: undefined-global
VHubGarage = VHubGarage or {}
VHubGarage.U = VHubGarage.U or {}

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
-- ESPELHA o CUST_KEYS de vhub_conce/server/vstate.lua (defesa em profundidade). VISUAL persistente
-- (stance/exhaust_fx/glass_armor) + extras: dono = vhub_custom; aqui só p/ não estripar no store.
local CUST_KEYS = {
  colours = true, extra_colours = true, plate_index = true, wheel_type = true,
  window_tint = true, livery = true, turbo = true, smoke = true, xenon = true,
  mods = true, neons = true, neon_colour = true, model = true,
  stance = true, exhaust_fx = true, glass_armor = true, extras = true,
  interior_color = true, dashboard_color = true,
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
  if not (x and y and z) or x ~= x or y ~= y or z ~= z
      or math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then return false end
  if math.abs(x) > 9000 or math.abs(y) > 9000 then return false end
  if z < -300 or z > 3500 then return false end
  return true
end
