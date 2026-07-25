-- server/exports.lua — API pública gated do vHub HSS

local State = nil
local Items = nil
local Cfg = nil
local ResolveCharacter = nil

local _rate = {}
local _handcuffed = {}


-- ============================================================
-- GUARDS
-- ============================================================

local function invoker_ok()
    if not State or not Cfg then return false end
    local caller = GetInvokingResource()
    return caller ~= nil and caller ~= '' and Cfg.TRUSTED[caller] == true
end

local function inventory_invoker_ok()
    return State ~= nil
        and Cfg ~= nil
        and GetInvokingResource() == 'vhub_inventory'
end

local function inventory_item_allowed(item_id)
    if type(item_id) ~= 'string' then return false end
    for _, configured in ipairs(Cfg.INVENTORY_USE) do
        if configured == item_id then return true end
    end
    return false
end

local function publish_item_fields(src, snapshot, changed)
    local player_state = Player(tonumber(src)).state
    for _, field in ipairs(changed) do
        player_state:set('hss_' .. field, snapshot[field], true)
    end
end

local function finite_number(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function rate_ok(export_name, src)
    local caller = GetInvokingResource() or ''
    local key = caller .. ':' .. export_name .. ':' .. tostring(src)
    local now = GetGameTimer()
    local limit = Cfg.RATE_LIMIT_MS[export_name] or 100
    local previous = _rate[key]
    if previous and (now - previous) < limit then return false end
    _rate[key] = now
    return true
end

local function resolve_char(src)
    src = tonumber(src)
    if not src or src < 1 or not GetPlayerName(src) then return nil end
    if not ResolveCharacter then return nil end
    local char_id = tonumber(ResolveCharacter(src))
    if not char_id or State.get_char_id(src) ~= char_id or not State.is_loaded(char_id) then return nil end
    return char_id
end

local function audit(char_id, reason, before, after)
    TriggerEvent(VHubHSS.E.STATE_CHANGED, char_id, {
        reason = reason,
        actor_resource = GetInvokingResource(),
        before = before,
        after = after,
        at = os.time(),
    })
end

local function mutate_export(export_name, src, field, delta)
    if not invoker_ok() then return false end
    src = tonumber(src)
    if not src or not rate_ok(export_name, src) then return false end
    local char_id = resolve_char(src)
    if not char_id then return false end

    local st = State.get(char_id)
    local before = st and st[field]
    local after, changed = State.mutate(char_id, field, delta)
    if changed then audit(char_id, export_name, before, after) end
    return changed == true
end

local function clear_rate(src)
    local suffix = ':' .. tostring(src)
    for key in pairs(_rate) do
        if key:sub(-#suffix) == suffix then _rate[key] = nil end
    end
end


-- ============================================================
-- EXPORTS
-- ============================================================

-- Adiciona adrenalina; delta público usa escala 0..100.
exports('addAdrenaline', function(src, delta)
    local number = finite_number(delta)
    if not number then return false end
    local normalized = math.max(-1.0, math.min(1.0, number / 100.0))
    return mutate_export('addAdrenaline', src, 'adrenaline', normalized)
end)

-- Adiciona estresse normalizado.
exports('addStress', function(src, delta)
    local number = finite_number(delta)
    if not number then return false end
    local normalized = math.max(-1.0, math.min(1.0, number))
    return mutate_export('addStress', src, 'stress', normalized)
end)

-- Adiciona dor normalizada.
exports('addPain', function(src, delta)
    local number = finite_number(delta)
    if not number then return false end
    local normalized = math.max(-1.0, math.min(1.0, number))
    return mutate_export('addPain', src, 'pain', normalized)
end)

-- Adiciona níveis de sangramento, com clamp interno 0..4.
exports('addBleeding', function(src, delta)
    local number = finite_number(delta)
    if not number then return false end
    local levels = math.floor(math.max(-4, math.min(4, number)))
    return mutate_export('addBleeding', src, 'bleeding', levels)
end)

-- Retorna snapshot profundo do personagem online.
exports('getState', function(src)
    if not invoker_ok() then return nil end
    local char_id = resolve_char(src)
    return char_id and State.snapshot(char_id) or nil
end)

-- Aplica efeito sem tocar no ownership do inventário.
exports('applyItem', function(src, item_id)
    if not invoker_ok() or type(item_id) ~= 'string' then return false end
    src = tonumber(src)
    if not src or not rate_ok('applyItem', src) then return false end
    local char_id = resolve_char(src)
    if not char_id then return false end

    local before = State.snapshot(char_id)
    local ok, changed = Items.apply(char_id, item_id)
    if not ok then return false end

    audit(char_id, 'applyItem:' .. item_id, before, State.snapshot(char_id))
    TriggerClientEvent(VHubHSS.E.ITEM_EFFECT, src, { item_id = item_id, changed = changed })
    return true
end)

-- Consome efeito solicitado exclusivamente pelo dispatcher autoritativo do inventário.
exports('useInventoryItem', function(src, item_id, _slot, _meta)
    if not inventory_invoker_ok() or not inventory_item_allowed(item_id) then return false end
    local char_id = resolve_char(src)
    if not char_id then return false end

    local before = State.snapshot(char_id)
    local ok, changed = Items.apply(char_id, item_id)
    if not ok then
        pcall(function()
            TriggerClientEvent(VHubHSS.E.NOTIFY, src, 'info', 'Este item não produz efeito agora.')
        end)
        return false
    end

    local after = State.snapshot(char_id)
    pcall(audit, char_id, 'inventory:' .. item_id, before, after)
    pcall(publish_item_fields, src, after, changed)
    pcall(function() TriggerClientEvent(VHubHSS.E.STATE_INIT, src, after) end)
    pcall(function()
        TriggerClientEvent(VHubHSS.E.ITEM_EFFECT, src, { item_id = item_id, changed = changed })
    end)
    pcall(function()
        TriggerClientEvent(
            VHubHSS.E.NOTIFY,
            src,
            'success',
            Cfg.ITEM_LABELS[item_id] or 'Item utilizado.'
        )
    end)
    return true
end)

-- Registra item externo validado durante o boot do chamador.
exports('registerItem', function(item_id, spec)
    if not invoker_ok() or not rate_ok('registerItem', 0) then return false end
    return Items.register(item_id, spec)
end)

-- Restaura fisiologia; vida/revive pertencem ao módulo de ped do HSS.
exports('fullHeal', function(src)
    if not invoker_ok() then return false end
    src = tonumber(src)
    if not src or not rate_ok('fullHeal', src) then return false end
    local char_id = resolve_char(src)
    if not char_id then return false end

    local before = State.snapshot(char_id)
    local st = State.get(char_id)
    State.mutate(char_id, 'food', 1.0 - st.food)
    State.mutate(char_id, 'water', 1.0 - st.water)
    State.mutate(char_id, 'energy', 1.0 - st.energy)
    State.mutate(char_id, 'blood', 1.0 - st.blood)
    State.mutate(char_id, 'bleeding', -(st.bleeding or 0))
    State.mutate(char_id, 'pain', -(st.pain or 0.0))
    State.mutate(char_id, 'stress', -(st.stress or 0.0))
    State.mutate(char_id, 'adrenaline', -(st.adrenaline or 0.0))
    State.mutate(char_id, 'body_temp', 37.0 - (st.body_temp or 37.0))
    State.mutate(char_id, 'consciousness', 'awake')
    State.clear_injuries(char_id)

    audit(char_id, 'fullHeal', before, State.snapshot(char_id))
    return true
end)


-- ============================================================
-- ALGEMAS
-- ============================================================

-- Define estado de algema; publica State Bag e aciona locker no client.
exports('setHandcuffed', function(src, state)
    if not invoker_ok() then return false end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end
    local active = state == true
    _handcuffed[src] = active or nil
    pcall(function() Player(src).state:set('hss_handcuffed', active, true) end)
    pcall(function() TriggerClientEvent(VHubHSS.E.HANDCUFF_SET, src, active) end)
    return true
end)

-- Retorna true se o player está algemado (leitura aberta).
exports('isHandcuffed', function(src)
    src = tonumber(src)
    return src ~= nil and _handcuffed[src] == true
end)

-- Retorna true se o personagem está consciente (leitura aberta).
exports('isConscious', function(src)
    src = tonumber(src)
    if not src or not State then return true end
    local char_id = State.get_char_id(src)
    if not char_id then return true end
    local st = State.get(char_id)
    return not st or st.consciousness ~= 'unconscious'
end)

-- Retorna tabela de bloqueios para o módulo de animação (leitura aberta).
exports('getAnimBlocks', function(src)
    src = tonumber(src)
    local none = { handcuffed = false, unconscious = false, weapon_drawn = false }
    if not src then return none end
    local handcuffed = _handcuffed[src] == true
    local unconscious = false
    if State then
        local char_id = State.get_char_id(src)
        if char_id then
            local st = State.get(char_id)
            unconscious = st ~= nil and st.consciousness == 'unconscious'
        end
    end
    local weapon_drawn = false
    local ped = GetPlayerPed(src)
    if DoesEntityExist(ped) then
        local _, wh = GetCurrentPedWeapon(ped, true)
        weapon_drawn = wh ~= 0xA2719263 -- WEAPON_UNARMED
    end
    return { handcuffed = handcuffed, unconscious = unconscious, weapon_drawn = weapon_drawn }
end)


-- ============================================================
-- SETUP
-- ============================================================

-- Injeta dependências após o schema estar pronto.
function HSS_Exports_setup(state_module, items_module, cfg, resolve_character)
    State = state_module
    Items = items_module
    Cfg = cfg
    ResolveCharacter = resolve_character
end

-- Limpa buckets de rate-limit da origem desconectada.
function HSS_Exports_clear_rate(src)
    clear_rate(src)
end

-- Limpa estado de algema ao desconectar; remove State Bag remota.
function HSS_Exports_clear_handcuff(src)
    _handcuffed[src] = nil
    pcall(function() Player(src).state:set('hss_handcuffed', false, true) end)
end
