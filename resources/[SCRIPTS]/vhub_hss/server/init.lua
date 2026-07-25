---@diagnostic disable: undefined-global, lowercase-global

-- server/init.lua — composição e lifecycle do vHub HSS

local SQL = VHubHSS_SQL
local State = VHubHSS_State
local Engine = VHubHSS_Engine
local Items = VHubHSS_Items
local Damage = VHubHSS_Damage
local Buckets = VHubHSS_Buckets
local Monitor = VHubHSS_Monitor
local Ped = VHubHSS_Ped
local Customization = VHubHSS_Customization
local Cfg = VHubHSS.Cfg

local _ped_ready = false
local _state_ready = false
local _running = true
local _seen = {}
local _loading = {}
local _init_rate = {}
local _inventory_generation = 0
local _pending_first_spawn = {}
local _test_sequence = 0
local _test_results = {}
local _test_running = false


-- ============================================================
-- CORE ESCALAR / LOG
-- ============================================================

local function resolve_character(src)
    src = tonumber(src)
    if not src or src < 1 then return nil end
    local ok, char_id = pcall(function() return exports.vhub:getCharacterId(src) end)
    return ok and tonumber(char_id) or nil
end

local function log(level, message, meta)
    pcall(function() exports.vhub:log(level, 'hss', message, meta) end)
end

local function copy_table(value)
    local out = {}
    if type(value) ~= 'table' then return out end
    for key, item in pairs(value) do
        out[key] = type(item) == 'table' and copy_table(item) or item
    end
    return out
end

local function read_bootstrap(src, char_id)
    if resolve_character(src) ~= char_id then return nil end
    local ok, snapshot = pcall(function() return exports.vhub:getCharacterBootstrap(src) end)
    if not ok or type(snapshot) ~= 'table' or tonumber(snapshot.char_id) ~= char_id then return nil end
    return snapshot
end

local function read_legacy(src, char_id)
    local snapshot = read_bootstrap(src, char_id)
    if not snapshot then return nil end
    return {
        vitals = copy_table(snapshot.vitals),
        state = copy_table(snapshot.state),
    }
end

local function read_spawn_counter(src, char_id)
    local snapshot = read_bootstrap(src, char_id)
    return snapshot and math.max(0, tonumber(snapshot.spawns) or 0) or nil
end

local function notify(src, kind, message)
    TriggerClientEvent(VHubHSS.E.NOTIFY, src, kind, message)
end


-- ============================================================
-- SESSÃO FISIOLÓGICA
-- ============================================================

local function send_snapshot(src, char_id)
    if not GetPlayerName(src) then return end
    local snapshot = State.snapshot(char_id)
    if snapshot then TriggerClientEvent(VHubHSS.E.STATE_INIT, src, snapshot) end
end

local function remove_session(src)
    local char_id = State.get_char_id(src)
    if char_id then
        Engine.remove(char_id)
        Damage.unregister(src)
        State.unregister(src)
    end
    _seen[src] = nil
    _loading[src] = nil
end

local function register_session(src, char_id)
    src, char_id = tonumber(src), tonumber(char_id)
    if not _state_ready or not src or not char_id or resolve_character(src) ~= char_id then return false end

    if _seen[src] == char_id and State.is_loaded(char_id) then
        Ped.handle_profile_loaded(src, char_id)
        send_snapshot(src, char_id)
        return true
    end
    local pending = _loading[src]
    if pending and pending.char_id == char_id and GetGameTimer() - pending.at < 10000 then return true end

    local old_char = State.get_char_id(src)
    if old_char and old_char ~= char_id then remove_session(src) end
    _seen[src] = char_id
    _loading[src] = { char_id = char_id, at = GetGameTimer() }

    local accepted = State.register(src, char_id, read_legacy(src, char_id), function(st, load_error)
        if resolve_character(src) ~= char_id or State.get_char_id(src) ~= char_id then return end
        _loading[src] = nil
        if not st then
            _seen[src] = nil
            log('error', 'Falha ao carregar estado do personagem.', {
                char_id = char_id,
                error = load_error,
            })
            notify(src, 'error', 'Estado fisiológico indisponível. Tente reconectar.')
            return
        end
        Engine.add(char_id)
        Damage.register(src, char_id)
        Ped.handle_profile_loaded(src, char_id)
        send_snapshot(src, char_id)
    end)
    if not accepted then
        _loading[src] = nil
        _seen[src] = nil
    end
    return accepted
end


-- ============================================================
-- INVENTÁRIO OPCIONAL
-- ============================================================

local function try_register_inventory()
    if GetResourceState('vhub_inventory') ~= 'started' then return false end
    for _, item_id in ipairs(Cfg.INVENTORY_USE) do
        local ok, registered = pcall(function()
            return exports.vhub_inventory:registerItemUse(item_id, 'useInventoryItem')
        end)
        if not ok or registered ~= true then return false end
    end
    return true
end

local function wire_inventory_bounded()
    _inventory_generation = _inventory_generation + 1
    local generation = _inventory_generation
    Citizen.CreateThread(function()
        for _ = 1, 40 do
            if not _running or generation ~= _inventory_generation then return end
            if try_register_inventory() then return end
            Citizen.Wait(500)
        end
        log('warn', 'Inventário indisponível; consumíveis HSS não registrados.')
    end)
end


-- ============================================================
-- BOOT EM DUAS FASES
-- ============================================================

local function complete_state_boot()
    State.init(SQL, Cfg, log)
    Ped.set_state(State)
    Engine.init(State, Cfg, log, Monitor)
    Items.init(State, Cfg)
    Damage.init(State, Cfg)
    Engine.set_damage(Damage)
    HSS_Exports_setup(State, Items, Cfg, resolve_character)
    Customization.init(SQL, State, log)
    _state_ready = true

    local active = GetConvar(Cfg.ACTIVE_CONVAR, '0') == '1'
    GlobalState.vh_hss_active = active
    if active then Engine.start() end

    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        local char_id = src and resolve_character(src)
        if char_id then
            Monitor.add(src, char_id)
            register_session(src, char_id)
        end
    end
    wire_inventory_bounded()
    log('info', 'Persistência/fisiologia HSS inicializada.', { active = active })
end

local function start_ped_domain()
    if _ped_ready then return end
    Buckets.init(Cfg, resolve_character, log)
    Ped.init(nil, Buckets, Cfg, resolve_character, log)
    Monitor.init(Cfg, resolve_character, Ped.observe, log)
    _ped_ready = true

    local handled = {}
    for src, pending in pairs(_pending_first_spawn) do
        _pending_first_spawn[src] = nil
        local char_id = resolve_character(src)
        if char_id and char_id == pending.char_id then
            -- respeita o first_spawn original salvo pelo handler; existing chars também recebem PED_APPLY
            Ped.handle_spawn(pending, pending.first_spawn == true)
            Monitor.add(src, char_id)
            handled[src] = true
        end
    end
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        local char_id = src and resolve_character(src)
        if char_id and not handled[src] then
            Monitor.add(src, char_id)
            local spawns = read_spawn_counter(src, char_id)
            -- tanto entry_bucket (999) quanto mundo (bucket 1) precisam de handle_spawn
            -- para que PED_APPLY seja enviado e o client execute DoScreenFadeIn
            if spawns ~= nil then
                Ped.handle_spawn({ source = src, char_id = char_id, spawns = spawns }, false)
            end
        end
    end

    SQL.apply_schema(function(ok, result)
        if not _running then return end
        if not ok then
            GlobalState.vh_hss_active = false
            for _, sid in ipairs(GetPlayers()) do
                local src = tonumber(sid)
                local char_id = src and resolve_character(src)
                if char_id then Ped.handle_profile_loaded(src, char_id) end
            end
            log('error', 'SQL indisponível; ped HSS segue em modo volátil.', { error = tostring(result) })
            return
        end
        complete_state_boot()
    end)
end

AddEventHandler('onResourceStart', function(resource)
    if resource == 'vhub_inventory' and _state_ready then
        SetTimeout(500, wire_inventory_bounded)
        return
    end
    if resource ~= GetCurrentResourceName() then return end

    GlobalState.vh_hss_active = false
    Citizen.CreateThread(function()
        for _ = 1, 50 do
            if not _running then return end
            local ok = pcall(function() return exports.vhub:getCharacterId(0) end)
            if ok then
                start_ped_domain()
                return
            end
            Citizen.Wait(200)
        end
        log('error', 'CORE indisponível; domínio de ped HSS não iniciado.')
    end)
end)

AddEventHandler('vhub_inventory:server:ready', function()
    if _state_ready then SetTimeout(100, wire_inventory_bounded) end
end)


-- ============================================================
-- EVENTOS INSTITUCIONAIS
-- ============================================================

AddEventHandler(VHubHSS.E.CHARACTER_LOAD, function(user)
    if not _ped_ready or type(user) ~= 'table' then return end
    local src = tonumber(user.source)
    local char_id = src and resolve_character(src)
    if not char_id or tonumber(user.char_id) ~= char_id then return end
    HSS_Exports_clear_handcuff(src)
    TriggerClientEvent(VHubHSS.E.STATE_HIDE, src)
    Monitor.remove(src)
    Ped.handle_character_load(user)
    Monitor.add(src, char_id)
    if _state_ready then
        register_session(src, char_id)
    else
        -- Diagnóstico: characterLoad chegou ANTES do boot de estado do HSS concluir. O estado
        -- físico NÃO é registrado agora → State.is_loaded(char_id) fica false → getCustomization
        -- devolve 'not_ready' e o criador do SIMS não abre. Se isto aparecer no fluxo de criação,
        -- é a raiz do "Preparando seu piloto…". complete_state_boot() faz um rescan, mas o
        -- register tardio depende do rescan alcançar este src.
        log('error', 'characterLoad com _state_ready=false — estado físico NÃO registrado agora.', {
            src = src, char_id = char_id,
        })
    end
end)

AddEventHandler(VHubHSS.E.PLAYER_SPAWN, function(user, first_spawn)
    if type(user) ~= 'table' then return end
    if not _ped_ready then
        local src = tonumber(user.source)
        local char_id = tonumber(user.char_id)
        -- salva tanto first_spawn quanto existing chars; ambos precisam de PED_APPLY
        if src and char_id then
            _pending_first_spawn[src] = {
                source = src,
                char_id = char_id,
                spawns = tonumber(user.spawns) or 0,
                first_spawn = first_spawn == true,
            }
        end
        return
    end
    local src = tonumber(user.source)
    local char_id = src and resolve_character(src)
    if not char_id or tonumber(user.char_id) ~= char_id then return end
    Ped.handle_spawn(user, first_spawn)
    Monitor.add(src, char_id)
    if _state_ready then
        register_session(src, char_id)
        if State.is_loaded(char_id) then
            Damage.register(src, char_id)
            Engine.clear_bags(char_id)
            send_snapshot(src, char_id)
        end
    end
end)

AddEventHandler(VHubHSS.E.PLAYER_DEATH, function(user)
    if not _ped_ready or type(user) ~= 'table' then return end
    local src = tonumber(user.source)
    local char_id = src and resolve_character(src)
    if char_id then
        HSS_Exports_clear_handcuff(src)
        TriggerClientEvent(VHubHSS.E.STATE_HIDE, src)
        Ped.handle_death(src, char_id)
        Monitor.add(src, char_id)
    end
    if _state_ready and char_id and State.get_char_id(src) == char_id then
        Damage.unregister(src)
        State.reset_after_death(char_id)
        TriggerClientEvent(VHubHSS.E.PED_GIVE_WEAPONS, src, {}, true)
    end
end)

RegisterNetEvent(VHubHSS.E.REQUEST_INIT, function()
    local src = source
    if not _state_ready or not GetPlayerName(src) then return end
    local now = GetGameTimer()
    if _init_rate[src] and now - _init_rate[src] < 5000 then return end
    _init_rate[src] = now
    local char_id = resolve_character(src)
    if not char_id then return end
    if Ped.is_suspended(src) then return end
    Monitor.add(src, char_id)
    if State.is_loaded(char_id) then send_snapshot(src, char_id) else register_session(src, char_id) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local char_id = _state_ready and State.get_char_id(src) or nil
    Monitor.remove(src)
    Ped.drop(src, char_id)
    if _state_ready then remove_session(src) end
    _init_rate[src] = nil
    _pending_first_spawn[src] = nil
    HSS_Exports_clear_rate(src)
    HSS_Exports_clear_handcuff(src)
end)


-- ============================================================
-- AUTOSAVE / SHUTDOWN
-- ============================================================

Citizen.CreateThread(function()
    local interval = math.max(5000, tonumber(Cfg.SAVE_INTERVAL_MS) or 30000)
    while _running do
        Citizen.Wait(interval)
        if _state_ready then State.flush_all() end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    _running = false
    _inventory_generation = _inventory_generation + 1
    if _ped_ready then
        Ped.shutdown()
        Monitor.stop()
    end
    if _state_ready then
        Engine.stop()
        if Cfg.FLUSH_ON_STOP then State.shutdown() end
    end
    GlobalState.vh_hss_active = false
end)


-- ============================================================
-- COMANDOS DE CONSOLE
-- ============================================================

RegisterCommand('hss_activate', function(src)
    if src ~= 0 or not _state_ready then return end
    for _, sid in ipairs(GetPlayers()) do
        local player_src = tonumber(sid)
        local char_id = player_src and State.get_char_id(player_src)
        if char_id then Damage.register(player_src, char_id) end
    end
    GlobalState.vh_hss_active = true
    Engine.start()
end, true)

RegisterCommand('hss_deactivate', function(src)
    if src ~= 0 or not _state_ready then return end
    Engine.stop()
    for _, sid in ipairs(GetPlayers()) do Damage.unregister(tonumber(sid)) end
    GlobalState.vh_hss_active = false
end, true)

-- Executa round-trip persistente somente pelo runner em ambiente de teste.
exports('runPersistenceTest', function(src)
    if GetInvokingResource() ~= 'vhub_testrunner'
        or not _state_ready
        or GetConvar('vhub_test_mode', '0') ~= '1'
        or _test_running then
        return nil
    end
    _test_sequence = _test_sequence + 1
    local token = tostring(_test_sequence)
    _test_running = true
    Citizen.CreateThread(function()
        local ok, result = pcall(State.run_persistence_test, src)
        _test_results[token] = { done = true, result = ok and result == true }
        _test_running = false
        SetTimeout(90000, function() _test_results[token] = nil end)
    end)
    return token
end)

-- Consulta e consome resultado assíncrono do teste persistente.
exports('getPersistenceTest', function(token)
    if GetInvokingResource() ~= 'vhub_testrunner' then return nil end
    token = type(token) == 'string' and token or nil
    local result = token and _test_results[token] or nil
    if result then _test_results[token] = nil end
    return result
end)
