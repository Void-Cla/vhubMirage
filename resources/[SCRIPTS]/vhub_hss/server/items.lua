-- server/items.lua — efeitos fisiológicos dos consumíveis HSS

VHubHSS_Items = {}
local Items = VHubHSS_Items

local State = nil
local Cfg = nil

local ALLOWED_FIELDS = {
    food = true,
    water = true,
    energy = true,
    stress = true,
    adrenaline = true,
    blood = true,
    bleeding = true,
    pain = true,
    body_temp = true,
    trauma = true,
}

local function finite(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end


-- ============================================================
-- API
-- ============================================================

-- Injeta dependências do domínio.
function Items.init(state_module, cfg)
    State = state_module
    Cfg = cfg
end

local function apply_field(char_id, field, delta)
    if not ALLOWED_FIELDS[field] then return false end
    local _, changed
    if field == 'trauma' then
        _, changed = State.mutate_trauma(char_id, delta)
    else
        _, changed = State.mutate(char_id, field, delta)
    end
    return changed == true
end

local function rollback_fields(char_id, before, changed)
    for index = #changed, 1, -1 do
        local field = changed[index]
        local snapshot = State.snapshot(char_id)
        local current = snapshot and tonumber(snapshot[field])
        local previous = tonumber(before[field])
        if current and previous then
            if field == 'trauma' then
                State.mutate_trauma(char_id, previous - current)
            else
                State.mutate(char_id, field, previous - current)
            end
        end
    end
end

-- Aplica item e retorna apenas campos realmente alterados.
function Items.apply(char_id, item_id)
    local spec = type(item_id) == 'string' and Cfg.ITEMS[item_id]
    if not spec then return false, 'item_unknown' end
    if not State.is_loaded(char_id) then return false, 'char_not_loaded' end

    local before = State.snapshot(char_id)
    local changed = {}
    local ok = pcall(function()
        if spec.effect == 'multi' then
            local fields = {}
            for field in pairs(spec.multi or {}) do fields[#fields + 1] = field end
            table.sort(fields)
            for _, field in ipairs(fields) do
                local delta = spec.multi[field]
                if apply_field(char_id, field, delta) then changed[#changed + 1] = field end
            end
        elseif apply_field(char_id, spec.effect, spec.delta) then
            changed[1] = spec.effect
        end
    end)

    if not ok then
        rollback_fields(char_id, before or {}, changed)
        return false, 'internal_error'
    end
    if #changed == 0 then return false, 'no_effect' end
    table.sort(changed)
    return true, changed
end

-- Registra especificação externa validada sem sobrescrever built-ins.
function Items.register(item_id, spec)
    if type(item_id) ~= 'string' or #item_id < 1 or #item_id > 64 then return false end
    if type(spec) ~= 'table' or Cfg.ITEMS[item_id] then return false end

    if spec.effect == 'multi' then
        if type(spec.multi) ~= 'table' or next(spec.multi) == nil then return false end
        for field, delta in pairs(spec.multi) do
            if not ALLOWED_FIELDS[field] or not finite(delta) then return false end
        end
    elseif not ALLOWED_FIELDS[spec.effect] or not finite(spec.delta) then
        return false
    end

    Cfg.ITEMS[item_id] = spec
    return true
end
