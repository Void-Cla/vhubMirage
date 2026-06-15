-- shared/utils.lua — utilitários puros do vhub_conce (sem side-effects)
---@diagnostic disable: undefined-global, lowercase-global

VHubConce   = VHubConce or {}
VHubConce.U = VHubConce.U or {}

local U = VHubConce.U

-- timestamp Unix (segundos)
function U.now() return os.time() end

-- valida e normaliza placa → string upper trim ou nil
function U.normalizePlate(plate)
  if type(plate) ~= 'string' then return nil end
  local p = plate:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  if not p or #p < 2 or #p > 8 then return nil end
  if not p:match('^[A-Z0-9][A-Z0-9 ]*[A-Z0-9]$') then return nil end
  return p
end

-- gera placa aleatória padrão "LLL DDDD"
function U.randomPlate()
  return string.format('%s%s%s %d%d%d%d',
    string.char(65 + math.random(0, 25)),
    string.char(65 + math.random(0, 25)),
    string.char(65 + math.random(0, 25)),
    math.random(0, 9), math.random(0, 9),
    math.random(0, 9), math.random(0, 9))
end

-- json safe encode/decode com fallback
function U.jenc(t)
  if t == nil then return nil end
  local ok, s = pcall(json.encode, t); return ok and s or nil
end

function U.jdec(s)
  if type(s) ~= 'string' or s == '' then return nil end
  local ok, v = pcall(json.decode, s); return ok and v or nil
end
