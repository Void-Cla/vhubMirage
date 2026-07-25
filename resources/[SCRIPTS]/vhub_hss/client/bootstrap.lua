-- client/bootstrap.lua — cache efêmero e delta NUI do HSS
-- Budgets: HUD/efeitos 2 Hz; self-heal máximo 0,125 Hz.

local _state = {}
local _ready = false
local _running = true
local _nui_previous = {}
local _runtime_generation = 0
local _handcuffed_local = false
local _control_locked = false
local start_runtime = nil
-- Efeitos visuais de mort/dano só ativam APÓS o ped sair do hold (PED_RELEASE).
-- Sem este gate, STATE_INIT com blood=0 (char novo) dispara DeathFailOut antes do
-- mundo aparecer, resultando em tela preta permanente.
local _effects_active = false

local SERVER_FIELDS = {
    'food', 'water', 'energy', 'blood', 'bleeding', 'pain',
    'trauma', 'body_temp', 'stress', 'consciousness', 'adrenaline',
}


-- ============================================================
-- SNAPSHOT / SELF-HEAL
-- ============================================================

RegisterNetEvent(VHubHSS.E.STATE_INIT, function(snapshot)
    if type(snapshot) ~= 'table' then return end
    for key, value in pairs(snapshot) do _state[key] = value end
    local start = not _ready
    _ready = true

    SendNUIMessage({ type = 'hss:update', data = snapshot })
    for _, field in ipairs(SERVER_FIELDS) do _nui_previous[field] = snapshot[field] end
    if start and start_runtime then start_runtime() end
end)

-- Libera efeitos visuais (morte/dano) apenas após o ped sair do hold.
AddEventHandler(VHubHSS.E.SPAWNED, function()
    _effects_active = true
end)

RegisterNetEvent(VHubHSS.E.STATE_HIDE, function()
    _ready = false
    _effects_active = false
    _runtime_generation = _runtime_generation + 1
    _handcuffed_local = false
    _control_locked = false
    SendNUIMessage({ type = 'hss:hide' })
    if VHubHSS_ClearEffects then VHubHSS_ClearEffects() end
end)

Citizen.CreateThread(function()
    Citizen.Wait(3000)
    while _running and not _ready do
        TriggerServerEvent(VHubHSS.E.REQUEST_INIT)
        Citizen.Wait(8000)
    end
end)


-- ============================================================
-- CONTROLES BLOQUEADOS — algema e inconsciência
-- ============================================================

-- combate + ação bloqueados ao estar algemado
local LOCK_COMBAT = {
    21, 22, 24, 25, 44, 45, 46, 47, 51,
    68, 69, 70, 71, 72, 75, 91, 92, 99,
    140, 141, 142, 143,
}
-- movimento bloqueado adicionalmente ao estar inconsciente
local LOCK_MOVE = { 30, 31 }

local function activate_locker()
    Citizen.CreateThread(function()
        while _control_locked and _running do
            for _, c in ipairs(LOCK_COMBAT) do DisableControlAction(0, c, true) end
            if _state.consciousness == 'unconscious' then
                for _, c in ipairs(LOCK_MOVE) do DisableControlAction(0, c, true) end
            end
            Citizen.Wait(0)
        end
    end)
end

local function sync_control_lock()
    local should = _handcuffed_local or (_state.consciousness == 'unconscious')
    if should and not _control_locked then
        _control_locked = true
        activate_locker()
    elseif not should then
        _control_locked = false
    end
end

RegisterNetEvent(VHubHSS.E.HANDCUFF_SET, function(active)
    _handcuffed_local = active == true
    sync_control_lock()
end)


-- ============================================================
-- DELTA NUI — 2 Hz
-- ============================================================

local function add_delta(delta, field, value, epsilon)
    if value == nil then return false end
    local previous = _nui_previous[field]
    if type(value) == 'number' and type(previous) == 'number' and epsilon then
        if math.abs(value - previous) <= epsilon then return false end
    elseif value == previous then
        return false
    end
    delta[field] = value
    _nui_previous[field] = value
    return true
end

start_runtime = function()
    _runtime_generation = _runtime_generation + 1
    local generation = _runtime_generation
    local player_id = PlayerId()

    Citizen.CreateThread(function()
        local tick = 0
        while _running and _ready and generation == _runtime_generation do
            Citizen.Wait(500)
            if not _running or not _ready or generation ~= _runtime_generation then return end
            tick = tick + 1

            local player_state = Player(player_id).state
            local ped = PlayerPedId()
            if not ped or ped == 0 or not DoesEntityExist(ped) then goto continue end
            local delta = {}
            local dirty = false

            for _, field in ipairs(SERVER_FIELDS) do
                local value = player_state['hss_' .. field]
                if value == nil then value = _state[field] end
                if value ~= nil then _state[field] = value end
                if field ~= 'energy' and add_delta(delta, field, value, 0.005) then dirty = true end
            end

            local max_health = GetEntityMaxHealth(ped)
            local health = GetEntityHealth(ped)
            local health_pct = max_health > 100
                and math.max(0.0, math.min(1.0, (health - 100) / (max_health - 100)))
                or math.max(0.0, math.min(1.0, health / math.max(max_health, 1)))
            if add_delta(delta, 'health', health_pct, 0.01) then dirty = true end

            local armour = math.max(0.0, math.min(1.0, GetPedArmour(ped) / 100.0))
            if add_delta(delta, 'armour', armour, 0.01) then dirty = true end

            local stamina = math.max(0.0, math.min(1.0,
                GetPlayerSprintStaminaRemaining(player_id) / 100.0))
            local effective_energy = math.min(tonumber(_state.energy) or 1.0, stamina)
            if add_delta(delta, 'effective_energy', effective_energy, 0.01) then dirty = true end

            local underwater = IsPedSwimmingUnderWater(ped)
            local oxygen = underwater
                and math.max(0.0, math.min(1.0, GetPlayerUnderwaterTimeRemaining(player_id) / 10.0))
                or 1.0
            if add_delta(delta, 'oxygen', oxygen, 0.01) then dirty = true end
            if add_delta(delta, 'oxygen_visible', underwater, nil) then dirty = true end

            if NetworkIsPlayerTalking(player_id) then
                PlayFacialAnim(ped, 'mic_chatter', 'mp_facial')
            end
            if tick % 8 == 0 then RestorePlayerStamina(player_id, 0.0099) end
            sync_control_lock()
            if _effects_active and VHubHSS_UpdateEffects then VHubHSS_UpdateEffects(_state) end
            if dirty then SendNUIMessage({ type = 'hss:update', data = delta }) end
            ::continue::
        end
    end)
end

if _ready then start_runtime() end


-- ============================================================
-- API LOCAL / CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    _running = false
    _ready = false
    _runtime_generation = _runtime_generation + 1
    _control_locked = false
    _handcuffed_local = false
    SendNUIMessage({ type = 'hss:hide' })
end)
