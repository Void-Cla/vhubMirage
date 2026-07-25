-- apshape.lua — política de domínio SIMS e operações puras sobre APV2

VHubSims.APShape = VHubSims.APShape or {}

local A = VHubSims.APShape
local CFG = VHubSims.cfg

local MODE_KEYS = {
  creator = { model = true, apv = true, heritage = true, face = true, drawable = true,
    prop = true, overlay = true, hair_color = true, eye_color = true, tattoos = true },
  barber = { drawable = true, overlay = true, hair_color = true },
  tattoo = { tattoos = true },
  clothes = { drawable = true, prop = true },
  surgeon = { heritage = true, face = true, eye_color = true },
}


-- ============================================================
-- PRIMITIVOS
-- ============================================================

local function copy(value, depth)
  if type(value) ~= 'table' then return value end
  if (depth or 0) >= 5 then return nil end
  local output = {}
  for key, child in pairs(value) do output[key] = copy(child, (depth or 0) + 1) end
  return output
end

local function equal(left, right, depth)
  if type(left) ~= type(right) then return false end
  if type(left) ~= 'table' then return left == right end
  if (depth or 0) >= 5 then return false end
  for key, value in pairs(left) do
    if not equal(value, right[key], (depth or 0) + 1) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

local function root_kind(key)
  if type(key) ~= 'string' then return nil end
  if key:match('^face:%d+$') then return 'face' end
  if key:match('^drawable:%d+$') then return 'drawable' end
  if key:match('^prop:%d+$') then return 'prop' end
  if key:match('^overlay:%d+$') then return 'overlay' end
  return key
end

local function valid_size(value)
  local ok, encoded = pcall(json.encode, value)
  return ok and type(encoded) == 'string' and #encoded <= CFG.max_payload_bytes
end


-- ============================================================
-- POLÍTICA DE DOMÍNIO
-- ============================================================

-- filtra chaves autorizadas pelo modo; o HSS normaliza valores e shape
function A.filterMode(payload, mode)
  if type(payload) ~= 'table' or type(mode) ~= 'string' or not MODE_KEYS[mode]
    or not valid_size(payload) then return nil, 'invalid_patch' end

  local output, count = {}, 0
  for key, value in pairs(payload) do
    local kind = root_kind(key)
    if not MODE_KEYS[mode][kind] then return nil, 'invalid_patch' end
    if kind == 'drawable' and mode == 'barber' and key ~= 'drawable:2' then
      return nil, 'invalid_patch'
    end
    output[key] = copy(value, 0)
    if output[key] == nil and value ~= nil then return nil, 'invalid_patch' end
    count = count + 1
  end
  if count == 0 then return nil, 'invalid_patch' end
  return output
end

-- aceita perfil canônico retornado pelo HSS sem duplicar sua normalização
function A.profile(value)
  if type(value) ~= 'table' or tonumber(value.apv) ~= 2 or not valid_size(value) then return nil end
  return copy(value, 0)
end


-- ============================================================
-- CÓPIA, MERGE, DIFF E DIGEST
-- ============================================================

-- retorna uma cópia limitada do shape
function A.copy(value)
  return copy(value, 0)
end

-- aplica patch sem mutar o snapshot de origem
function A.merge(base, patch)
  local output = copy(type(base) == 'table' and base or {}, 0) or {}
  for key, value in pairs(patch or {}) do output[key] = copy(value, 0) end
  return output
end

-- retorna as chaves-raiz alteradas entre dois shapes
function A.diff(before, after)
  local changed = {}
  before = type(before) == 'table' and before or {}
  after = type(after) == 'table' and after or {}
  for key, value in pairs(after) do
    if not equal(before[key], value, 0) then changed[#changed + 1] = key end
  end
  for key in pairs(before) do
    if after[key] == nil then changed[#changed + 1] = key end
  end
  table.sort(changed, function(left, right) return tostring(left) < tostring(right) end)
  return changed
end

local function canonical(value, depth)
  local kind = type(value)
  if kind == 'nil' then return 'null' end
  if kind == 'boolean' then return value and 'true' or 'false' end
  if kind == 'number' then
    return value == value and value ~= math.huge and value ~= -math.huge and ('%.17g'):format(value)
      or 'null'
  end
  if kind == 'string' then return json.encode(value) end
  if kind ~= 'table' or (depth or 0) >= 6 then return 'null' end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  local chunks = {}
  for _, key in ipairs(keys) do
    chunks[#chunks + 1] = json.encode(tostring(key)) .. ':' .. canonical(value[key], (depth or 0) + 1)
  end
  return '{' .. table.concat(chunks, ',') .. '}'
end

local function fnv(text, seed)
  local hash = seed
  for index = 1, #text do hash = ((hash ~ text:byte(index)) * 16777619) & 0xffffffff end
  return ('%08x'):format(hash)
end

-- serializa de forma determinística para idempotência durável
function A.canonical(value)
  return canonical(value, 0)
end

-- calcula digest estável de 64 caracteres
function A.digest(value)
  local encoded = canonical(value, 0)
  local seeds = { 2166136261, 2654435761, 2246822519, 3266489917,
    668265263, 374761393, 1274126177, 42595009 }
  local chunks = {}
  for index, seed in ipairs(seeds) do chunks[index] = fnv(encoded, seed) end
  return table.concat(chunks), encoded
end

-- reduz um shape para vestuário persistível em outfit
function A.outfitOnly(value)
  local output = {}
  for key, child in pairs(type(value) == 'table' and value or {}) do
    local kind = root_kind(key)
    if kind == 'drawable' or kind == 'prop' then output[key] = copy(child, 0) end
  end
  return output
end
