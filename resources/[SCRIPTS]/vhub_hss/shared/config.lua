-- shared/config.lua — contratos estáticos do vHub Human State System

VHubHSS = VHubHSS or {}

VHubHSS.Cfg = {
    ACTIVE_CONVAR = 'vh_hss_active',
    SAVE_INTERVAL_MS = 30000,
    FLUSH_ON_STOP = true,

    PED = {
        spawn = vec4(-538.70, -214.91, 37.65, 0.0),
        customization_stage = vec4(402.60, -997.20, -98.30, 180.0),
        default_model = 'mp_m_freemode_01',
        default_health = 200,
        default_armour = 0,
        selector_enabled = true,
        selector_mode = 'session',
        selector_timeout_ms = 300000,
        entry_bucket = 999,
        world_bucket = 1,
        activity_bucket_first = 1000,
        activity_bucket_last = 65535,
        monitor_hz = 1,
        max_foot_speed = 18.0,
        max_vehicle_speed = 180.0,
        max_vertical_speed = 90.0,
        position_slack = 20.0,
        teleport_tolerance = 35.0,
        mutation_ledger_ms = 5000,
        allowed_models = {
            mp_m_freemode_01 = true,
            mp_f_freemode_01 = true,
        },
    },

    PED_TRUSTED = {
        ['vhub_admin'] = true,
        ['vhub_coinshop'] = true,
        ['vhub_groups'] = true,
        ['vhub_spawselector'] = true,
        ['vhub_login'] = true,
    },

    ACTIVITY_TRUSTED = {
        ['vhub_coinshop'] = true,
    },

    CUSTOMIZATION_TRUSTED = {
        ['vhub_sims'] = true,
    },

    DRAIN = {
        food = 0.001,    -- teste: ~16 min p/ zerar (produção: 0.00007)
        water = 0.0015,  -- teste: ~11 min p/ zerar (produção: 0.00011)
        energy = 0.00002,
        blood_per_bleed = {
            [0] = 0.0,
            [1] = 0.0008,
            [2] = 0.0025,
            [3] = 0.006,
            [4] = 0.014,
        },
    },

    BLOOD_REGEN = 0.0009,
    PAIN_RECOVERY = 0.00012,
    TRAUMA_RECOVERY = 0.00035,
    TEMP_RESTORE_RATE = 0.005,
    ADRENALINE_DECAY = 0.982,
    STRESS_DECAY = 0.9997,

    ADRENALINE_META = {
        threshold = 0.55,
        water_mult = 1.6,
        food_mult = 1.2,
        energy_mult = 1.5,
    },

    ACTIVITY = {
        sprint_speed = 5.5,
        run_speed = 2.5,
        idle_speed = 0.7,
        sprint_energy = 0.012,
        run_energy = 0.003,
        idle_regen = 0.015,
        vehicle_regen = 0.006,
        sprint_food = 0.00009,
        sprint_water = 0.00018,
        regen_min_food = 0.15,
        regen_min_water = 0.15,
    },

    DAMAGE = {
        max_health_delta = 100,
        pain_per_health = 0.008,
        stress_per_health = 0.005,
        adrenaline_per_health = 0.010,
        trauma_per_health = 0.009,
        bleed_level_1 = 20,
        bleed_level_2 = 50,
    },

    BAG_THRESHOLD = {
        food = 0.005,
        water = 0.005,
        energy = 0.005,
        adrenaline = 0.02,
        stress = 0.002,
        blood = 0.01,
        bleeding = 1,
        pain = 0.03,
        trauma = 0.03,
        body_temp = 0.1,
    },

    LIMITS = {
        food = { min = 0.0, max = 1.0 },
        water = { min = 0.0, max = 1.0 },
        energy = { min = 0.0, max = 1.0 },
        stress = { min = 0.0, max = 1.0 },
        adrenaline = { min = 0.0, max = 1.0 },
        blood = { min = 0.0, max = 1.0 },
        bleeding = { min = 0, max = 4 },
        pain = { min = 0.0, max = 1.0 },
        trauma = { min = 0.0, max = 1.0 },
        body_temp = { min = 34.0, max = 43.0 },
    },

    ITEMS = {
        bandage = { effect = 'bleeding', delta = -1, animation = 'medical' },
        tourniquet = { effect = 'bleeding', delta = -3, animation = 'medical' },
        splint = { effect = 'trauma', delta = -0.45, animation = 'medical' },
        saline = { effect = 'blood', delta = 0.10, animation = 'medical' },
        blood_bag = { effect = 'blood', delta = 0.35, animation = 'medical' },
        morphine = { effect = 'pain', delta = -0.60, animation = 'medical' },
        epinephrine = { effect = 'adrenaline', delta = 0.40, animation = 'medical' },
        surgery_kit = {
            effect = 'multi',
            multi = { bleeding = -4, pain = -0.8, blood = 0.2, trauma = -0.8 },
            animation = 'medical',
        },
        energy_drink = {
            effect = 'multi',
            multi = { energy = 0.25, adrenaline = 0.10 },
            animation = 'drink',
        },
        coffee = {
            effect = 'multi',
            multi = { energy = 0.15, stress = -0.05 },
            animation = 'drink',
        },
        meal = {
            effect = 'multi',
            multi = { food = 0.40, energy = 0.10 },
            animation = 'food',
        },
        water_bottle = { effect = 'water', delta = 0.40, animation = 'drink' },
        blanket = { effect = 'body_temp', delta = 1.5, animation = 'medical' },
        thermic_jacket = { effect = 'body_temp', delta = 2.0, animation = 'medical' },

        agua = { effect = 'water', delta = 0.35, animation = 'drink' },
        sandwich = {
            effect = 'multi',
            multi = { food = 0.40, energy = 0.10 },
            animation = 'food',
        },
        medkit = {
            effect = 'multi',
            multi = { blood = 0.35, bleeding = -2, pain = -0.50, trauma = -0.35 },
            animation = 'medical',
        },
    },

    INVENTORY_USE = { 'agua', 'sandwich', 'bandage', 'medkit' },

    ITEM_ANIMATIONS = {
        drink = { dict = 'mp_player_intdrink', name = 'loop_bottle', duration_ms = 2200 },
        food = { dict = 'mp_player_inteat@burger', name = 'mp_player_int_eat_burger', duration_ms = 2600 },
        medical = {
            dict = 'amb@medic@standing@tendtodead@idle_a',
            name = 'idle_a',
            duration_ms = 2800,
        },
    },

    ITEM_LABELS = {
        agua = 'Água consumida.',
        sandwich = 'Alimento consumido.',
        bandage = 'Bandagem aplicada.',
        medkit = 'Tratamento aplicado.',
    },

    FX = {
        shake_adr_threshold = 0.35,
        blur_pain_threshold = 0.70,
        blood_fx_threshold = 0.12,
        limp_trauma_threshold = 0.15,
        sweat_stress_threshold = 0.60,
    },

    TRUSTED = {
        ['vhub_racha'] = true,
        ['vhub_nitro'] = true,
        ['vhub_vrcs'] = true,
        ['vhub_custom'] = true,
        ['vhub_coinshop'] = true,
        ['vhub_admin'] = true,
        ['vhub_animacao'] = true,
    },

    RATE_LIMIT_MS = {
        addAdrenaline = 100,
        addStress = 500,
        addPain = 300,
        addBleeding = 1000,
        applyItem = 1500,
        fullHeal = 2000,
        registerItem = 1000,
        pedMutation = 100,
        teleport = 250,
    },
}
