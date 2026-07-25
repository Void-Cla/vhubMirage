-- server/engine.lua — scheduler fisiológico server-authoritative do HSS

VHubHSS_Engine = {}
local Engine = VHubHSS_Engine

local State = nil
local Cfg = nil
local Damage = nil
local Monitor = nil
local Logger = nil

local _slots = {}
local _tick_at = {}
local _previous_bags = {}
local _running = false
local _run_generation = 0
local _last_error_at = 0


-- ============================================================
-- HELPERS
-- ============================================================

local function clamp(value, min_value, max_value)
    return math.max(min_value, math.min(max_value, value))
end

local function apply_activity(st, dt, sample)
    if not sample then return end
    local speed = sample.speed or 0.0
    local activity = Cfg.ACTIVITY
    if sample.in_vehicle then
        st.energy = clamp(st.energy + activity.vehicle_regen * dt, 0.0, 1.0)
    elseif speed >= activity.sprint_speed then
        st.energy = clamp(st.energy - activity.sprint_energy * dt, 0.0, 1.0)
        st.food = clamp(st.food - activity.sprint_food * dt, 0.0, 1.0)
        st.water = clamp(st.water - activity.sprint_water * dt, 0.0, 1.0)
    elseif speed >= activity.run_speed then
        st.energy = clamp(st.energy - activity.run_energy * dt, 0.0, 1.0)
    elseif speed <= activity.idle_speed
        and st.food > activity.regen_min_food
        and st.water > activity.regen_min_water then
        st.energy = clamp(st.energy + activity.idle_regen * dt, 0.0, 1.0)
    end
end

local function tick_one(char_id)
    local st = State.get(char_id)
    if not st then return end
    local sample = Monitor and Monitor.get(char_id) or nil

    local now = GetGameTimer()
    local previous_at = _tick_at[char_id] or (now - 1000)
    _tick_at[char_id] = now
    local dt = clamp((now - previous_at) / 1000.0, 0.25, 3.0)
    local drain = Cfg.DRAIN

    local food_mult, water_mult, energy_mult = 1.0, 1.0, 1.0
    local adr_meta = Cfg.ADRENALINE_META
    if st.adrenaline >= adr_meta.threshold then
        food_mult = adr_meta.food_mult
        water_mult = adr_meta.water_mult
        energy_mult = adr_meta.energy_mult
    end

    st.food = clamp(st.food - drain.food * food_mult * dt, 0.0, 1.0)
    st.water = clamp(st.water - drain.water * water_mult * dt, 0.0, 1.0)
    st.energy = clamp(
        st.energy - drain.energy * (1.0 + st.stress * 2.0) * energy_mult * dt,
        0.0,
        1.0
    )

    apply_activity(st, dt, sample)

    st.adrenaline = clamp(st.adrenaline * (Cfg.ADRENALINE_DECAY ^ dt), 0.0, 1.0)
    st.stress = clamp(st.stress * (Cfg.STRESS_DECAY ^ dt), 0.0, 1.0)

    local blood_drain = drain.blood_per_bleed[st.bleeding] or 0.0
    if blood_drain > 0.0 then
        st.blood = clamp(st.blood - blood_drain * dt, 0.0, 1.0)
    elseif st.blood < 1.0 then
        st.blood = clamp(st.blood + Cfg.BLOOD_REGEN * dt, 0.0, 1.0)
    end

    if st.body_temp ~= 37.0 then
        local diff = 37.0 - st.body_temp
        local step = Cfg.TEMP_RESTORE_RATE * dt
        st.body_temp = math.abs(diff) <= step and 37.0
            or st.body_temp + (diff > 0 and step or -step)
    end

    st.pain = clamp(st.pain - Cfg.PAIN_RECOVERY * dt, 0.0, 1.0)
    local trauma = tonumber(st.injuries.trauma) or 0.0
    if trauma > 0.0 then
        st.injuries.trauma = clamp(trauma - Cfg.TRAUMA_RECOVERY * dt, 0.0, 1.0)
    end

    if st.blood <= 0.10 and st.consciousness == 'awake' then
        st.consciousness = 'unconscious'
        TriggerEvent(VHubHSS.E.CRITICAL, char_id, 'blood_critical')
    elseif st.blood > 0.15 and st.consciousness == 'unconscious' then
        st.consciousness = 'awake'
    end

    State.touch(char_id)
    if Damage and sample then Damage.observe(State.get_src(char_id), char_id, sample.health) end
end

local function sync_bags(char_id)
    local st = State.get(char_id)
    local src = State.get_src(char_id)
    if not st or not src then return end

    local previous = _previous_bags[char_id]
    if not previous then
        previous = {}
        _previous_bags[char_id] = previous
    end

    local player_state = Player(src).state
    local threshold = Cfg.BAG_THRESHOLD

    local function publish(key, value, min_delta)
        local old = previous[key]
        if old ~= nil then
            if min_delta and type(value) == 'number' and math.abs(old - value) < min_delta then return end
            if not min_delta and old == value then return end
        end
        player_state:set('hss_' .. key, value, true)
        previous[key] = value
    end

    publish('food', st.food, threshold.food)
    publish('water', st.water, threshold.water)
    publish('energy', st.energy, threshold.energy)
    publish('adrenaline', st.adrenaline, threshold.adrenaline)
    publish('stress', st.stress, threshold.stress)
    publish('blood', st.blood, threshold.blood)
    publish('bleeding', st.bleeding, threshold.bleeding)
    publish('pain', st.pain, threshold.pain)
    publish('trauma', tonumber(st.injuries.trauma) or 0.0, threshold.trauma)
    publish('body_temp', st.body_temp, threshold.body_temp)
    publish('consciousness', st.consciousness, nil)
end


-- ============================================================
-- API
-- ============================================================

-- Injeta estado e configuração.
function Engine.init(state_module, cfg, logger, monitor)
    State = state_module
    Cfg = cfg
    Logger = logger
    Monitor = monitor
end

-- Injeta observador autoritativo de dano.
function Engine.set_damage(damage_module)
    Damage = damage_module
end

-- Registra personagem idempotentemente no scheduler.
function Engine.add(char_id)
    for _, current in ipairs(_slots) do
        if current == char_id then return end
    end
    _slots[#_slots + 1] = char_id
end

-- Remove personagem e seus caches efêmeros.
function Engine.remove(char_id)
    _tick_at[char_id] = nil
    _previous_bags[char_id] = nil
    for index, current in ipairs(_slots) do
        if current == char_id then
            table.remove(_slots, index)
            return
        end
    end
end

-- Inicia scheduler em lotes de 16 com custo O(1) por jogador/segundo.
function Engine.start()
    if _running then return end
    _running = true
    _run_generation = _run_generation + 1
    local generation = _run_generation

    Citizen.CreateThread(function()
        while _running and generation == _run_generation do
            if #_slots == 0 then
                Citizen.Wait(1000)
            else
                local cycle_at = GetGameTimer()
                local batch = {}
                for index, char_id in ipairs(_slots) do batch[index] = char_id end
                for index, char_id in ipairs(batch) do
                    if char_id and State.is_loaded(char_id) then
                        local ok, err = pcall(tick_one, char_id)
                        if ok then ok, err = pcall(sync_bags, char_id) end
                        local now = GetGameTimer()
                        if not ok and Logger and (now - _last_error_at) >= 5000 then
                            _last_error_at = now
                            Logger('error', 'Falha isolada no tick fisiológico.', {
                                char_id = char_id,
                                error = tostring(err),
                            })
                        end
                    end
                    if index % 16 == 0 then Citizen.Wait(0) end
                end
                Citizen.Wait(math.max(1, 1000 - (GetGameTimer() - cycle_at)))
            end
        end
    end)
end

-- Encerra o scheduler sem deixar loop órfão.
function Engine.stop()
    _running = false
    _run_generation = _run_generation + 1
end

-- Força publicação no próximo slot do personagem.
function Engine.clear_bags(char_id)
    _previous_bags[char_id] = nil
end
