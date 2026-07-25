-- shared/appearance.lua — shape APV2 canônico e único do HSS

VHubHSS = VHubHSS or {}
VHubHSS.Appearance = VHubHSS.Appearance or {}

local Appearance = VHubHSS.Appearance


-- ============================================================
-- PRIMITIVOS
-- ============================================================

local function finite(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function integer(value, minimum, maximum, fallback)
    local number = finite(value)
    if not number then return fallback end
    return math.floor(clamp(number, minimum, maximum))
end

local function tuple_value(tuple, index, name)
    return tuple[index] ~= nil and tuple[index] or tuple[name]
end

local function valid_hash_name(value)
    return type(value) == 'string'
        and #value >= 1
        and #value <= 64
        and value:match('^[a-zA-Z0-9_]+$') ~= nil
end

local function copy_table(value)
    local out = {}
    if type(value) ~= 'table' then return out end
    for key, item in pairs(value) do
        out[key] = type(item) == 'table' and copy_table(item) or item
    end
    return out
end


-- ============================================================
-- NORMALIZAÇÃO APV2
-- ============================================================

local function clean_heritage(value)
    if type(value) ~= 'table' then return nil end
    return {
        shape_first = integer(value.shape_first, 0, 45, 0),
        shape_second = integer(value.shape_second, 0, 45, 0),
        skin_first = integer(value.skin_first, 0, 45, 0),
        skin_second = integer(value.skin_second, 0, 45, 0),
        shape_mix = clamp(finite(value.shape_mix) or 0.5, 0.0, 1.0),
        skin_mix = clamp(finite(value.skin_mix) or 0.5, 0.0, 1.0),
    }
end

local function clean_tuple(family, value)
    if type(value) ~= 'table' then return nil end
    if family == 'drawable' then
        return {
            integer(tuple_value(value, 1, 'd'), 0, 255, 0),
            integer(tuple_value(value, 2, 't'), 0, 255, 0),
            integer(tuple_value(value, 3, 'palette'), 0, 3, 0),
        }
    end
    if family == 'prop' then
        return {
            integer(tuple_value(value, 1, 'd'), -1, 255, -1),
            integer(tuple_value(value, 2, 't'), 0, 255, 0),
        }
    end
    return {
        integer(tuple_value(value, 1, 'value'), 0, 255, 0),
        integer(tuple_value(value, 2, 'c1'), 0, 63, 0),
        integer(tuple_value(value, 3, 'c2'), 0, 63, 0),
        clamp(finite(tuple_value(value, 4, 'opacity')) or 1.0, 0.0, 1.0),
    }
end

local function clean_tattoos(value)
    if type(value) ~= 'table' then return nil end
    local out, seen = {}, {}
    for index = 1, math.min(#value, 40) do
        local item = value[index]
        if type(item) == 'table'
            and valid_hash_name(item.dlc)
            and valid_hash_name(item.hash) then
            local key = item.dlc .. ':' .. item.hash
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = {
                    dlc = item.dlc,
                    hash = item.hash,
                    zone = integer(item.zone, 0, 7, 0),
                }
            end
        end
    end
    return out
end

local function sanitize(value, patch_only)
    if type(value) ~= 'table' then return nil, 'invalid_patch' end
    local count = 0
    for _ in pairs(value) do
        count = count + 1
        if count > 96 then return nil, 'invalid_patch' end
    end

    local out = patch_only and {} or {
        apv = 2,
        model = VHubHSS.Cfg.PED.default_model,
    }
    local accepted = 0

    if value.apv ~= nil then
        if tonumber(value.apv) ~= 2 then return nil, 'invalid_patch' end
        out.apv = 2
        accepted = accepted + 1
    elseif not patch_only then
        out.apv = 2
    end

    if value.model ~= nil then
        if type(value.model) ~= 'string' or not VHubHSS.Cfg.PED.allowed_models[value.model] then
            return nil, 'invalid_patch'
        end
        out.model = value.model
        accepted = accepted + 1
    end

    if value.heritage ~= nil then
        local heritage = clean_heritage(value.heritage)
        if not heritage then return nil, 'invalid_patch' end
        out.heritage = heritage
        accepted = accepted + 1
    end

    if value.eye_color ~= nil then
        local eye_color = integer(value.eye_color, 0, 31)
        if eye_color == nil then return nil, 'invalid_patch' end
        out.eye_color = eye_color
        accepted = accepted + 1
    end

    if value.hair_color ~= nil then
        if type(value.hair_color) ~= 'table' then return nil, 'invalid_patch' end
        out.hair_color = {
            integer(tuple_value(value.hair_color, 1, 'c1'), 0, 63, 0),
            integer(tuple_value(value.hair_color, 2, 'c2'), 0, 63, 0),
        }
        accepted = accepted + 1
    end

    if value.tattoos ~= nil then
        local tattoos = clean_tattoos(value.tattoos)
        if not tattoos then return nil, 'invalid_patch' end
        out.tattoos = tattoos
        accepted = accepted + 1
    end

    for key, item in pairs(value) do
        if type(key) == 'string' then
            local face_index = tonumber(key:match('^face:(%d+)$'))
            if face_index and face_index <= 19 then
                local feature = finite(item)
                if not feature then return nil, 'invalid_patch' end
                out[key] = clamp(feature, -1.0, 1.0)
                accepted = accepted + 1
            else
                local family, raw_index = key:match('^(drawable):(%d+)$')
                if not family then family, raw_index = key:match('^(prop):(%d+)$') end
                if not family then family, raw_index = key:match('^(overlay):(%d+)$') end
                local index = tonumber(raw_index)
                local maximum = family == 'drawable' and 11 or family == 'prop' and 7 or 12
                if family and index and index <= maximum then
                    local tuple = clean_tuple(family, item)
                    if not tuple then return nil, 'invalid_patch' end
                    out[key] = tuple
                    accepted = accepted + 1
                end
            end
        end
    end

    if patch_only and accepted == 0 then return nil, 'invalid_patch' end
    return out
end


-- ============================================================
-- API COMPARTILHADA
-- ============================================================

-- Retorna cópia profunda sem conservar referência externa.
function Appearance.copy(value)
    return copy_table(value)
end

-- Sanitiza um perfil completo no shape APV2.
function Appearance.sanitize(value)
    local clean = sanitize(type(value) == 'table' and value or {}, false)
    return clean or { apv = 2, model = VHubHSS.Cfg.PED.default_model }
end

-- Sanitiza patch parcial; payload vazio ou estruturalmente inválido falha fechado.
function Appearance.sanitizePatch(value)
    return sanitize(value, true)
end

-- Mescla patch APV2 já sanitizado sobre snapshot canônico.
function Appearance.merge(current, patch)
    local out = Appearance.sanitize(current)
    for key, value in pairs(type(patch) == 'table' and patch or {}) do
        out[key] = type(value) == 'table' and copy_table(value) or value
    end
    out.apv = 2
    return out
end

