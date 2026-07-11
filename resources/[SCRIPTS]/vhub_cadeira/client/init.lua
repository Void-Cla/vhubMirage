-- client/init.lua — sentar em props via vhub_target (client-only, sem servidor)
---@diagnostic disable: undefined-global

local isSitting  = false
local seatProp   = 0

-- controla o watch-thread para não criar múltiplos
local _watchActive = false

-- registro de quais props estão ocupadas: [entHandle] = true
-- client-local — cada jogador vê só o próprio estado; não evita colisão entre jogadores
-- (colisão entre jogadores exigiria state bag server-side — escopo futuro)
local _occupied = {}


-- ============================================================
-- SCENARIO POR MODELO
-- ============================================================

local SCENARIO_BY_MODEL = {
    [joaat('prop_armchair_01')]              = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('apa_mp_h_stn_sofa3seat_01')]     = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('apa_mp_h_stn_sofa3seat_02')]     = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('apa_mp_h_stn_sofa2seat_02')]     = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('apa_mp_h_stn_sofa_daybed_01')]   = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('apa_mp_h_stn_sofa_daybed_02')]   = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('p_armchair_01_s')]               = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('v_res_fh_easychair')]            = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('v_ilev_p_easychair')]            = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('xm_lab_easychair_01')]           = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('p_ilev_p_easychair_s')]          = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('v_res_m_l_chair1')]              = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('prop_old_deck_chair')]           = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('prop_old_deck_chair_02')]        = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('prop_chateau_chair_01')]         = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('prop_sol_chair')]                = 'WORLD_HUMAN_SEAT_ARMCHAIR',
    [joaat('prop_cs_office_chair')]          = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('v_corp_offchair')]               = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('v_club_officechair')]            = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('v_corp_bk_chair3')]              = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_01')]             = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_03')]             = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_04')]             = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_04b')]            = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_05')]             = 'WORLD_HUMAN_SEAT_CHAIR',
}

local function getScenario(prop)
    return SCENARIO_BY_MODEL[GetEntityModel(prop)] or 'WORLD_HUMAN_SEAT_LEDGE'
end


-- ============================================================
-- POSIÇÃO DE ASSENTO
-- ============================================================

-- offset Z do assento acima da origem do prop (empírico por categoria)
-- bancos têm seat mais baixo (~0.25m); sofás/poltronas ~0.40m; cadeiras de mesa ~0.35m
local ZOFFSET_BY_MODEL = {
    -- sofás / poltronas — mais altos
    [joaat('prop_armchair_01')]           = 0.40,
    [joaat('apa_mp_h_stn_sofa3seat_01')]  = 0.40,
    [joaat('apa_mp_h_stn_sofa3seat_02')]  = 0.40,
    [joaat('apa_mp_h_stn_sofa2seat_02')]  = 0.40,
    [joaat('apa_mp_h_stn_sofa_daybed_01')]= 0.38,
    [joaat('apa_mp_h_stn_sofa_daybed_02')]= 0.38,
    -- bancos externos — mais baixos
    [joaat('prop_bench_01a')]             = 0.25,
    [joaat('prop_bench_01b')]             = 0.25,
    [joaat('prop_bench_01c')]             = 0.25,
    [joaat('prop_bench_02')]              = 0.25,
    [joaat('prop_bench_03')]              = 0.25,
    [joaat('prop_bench_04')]              = 0.25,
    [joaat('prop_bench_05')]              = 0.25,
    [joaat('prop_bench_06')]              = 0.25,
    [joaat('prop_bench_07')]              = 0.25,
    [joaat('prop_bench_08')]              = 0.25,
    [joaat('prop_bench_09')]              = 0.25,
    [joaat('prop_bench_10')]              = 0.25,
    [joaat('prop_bench_11')]              = 0.25,
    [joaat('prop_air_bench_01')]          = 0.28,
    [joaat('prop_air_bench_02')]          = 0.28,
    [joaat('prop_fib_3b_bench')]          = 0.28,
}

local function getSeatZOffset(prop)
    return ZOFFSET_BY_MODEL[GetEntityModel(prop)] or 0.35
end

-- retorna posição world + heading para sentar na cadeira
local function getSeatPoint(prop)
    local zOff   = getSeatZOffset(prop)
    local world  = GetOffsetFromEntityInWorldCoords(prop, 0.0, 0.0, zOff)
    -- ped de costas para frente do prop (olha na mesma direção que a cadeira "aponta")
    local heading = GetEntityHeading(prop) + 180.0
    return world.x, world.y, world.z, heading
end


-- ============================================================
-- AÇÕES
-- ============================================================

-- forward-declaration: sit() referencia standUp() via upvalue
local standUp

local function sit(prop)
    if isSitting then return end
    if _occupied[prop] then return end  -- cadeira já ocupada por este client

    local ped = PlayerPedId()
    local x, y, z, h = getSeatPoint(prop)

    ClearPedTasks(ped)
    Wait(50)

    SetEntityCoords(ped, x, y, z, false, false, false, false)
    SetEntityHeading(ped, h)
    Wait(100)

    TaskStartScenarioInPlace(ped, getScenario(prop), 0, true)

    isSitting       = true
    seatProp        = prop
    _occupied[prop] = true

    -- watch: qualquer movimento horizontal cancela a animação (andar, correr)
    if not _watchActive then
        _watchActive = true
        CreateThread(function()
            while isSitting do
                Wait(300)
                local vel   = GetEntityVelocity(PlayerPedId())
                local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
                if speed > 0.5 then standUp() end
            end
            _watchActive = false
        end)
    end
end

standUp = function()
    if not isSitting then return end

    ClearPedTasksImmediately(PlayerPedId())
    _occupied[seatProp] = nil
    isSitting           = false
    seatProp            = 0
end

local function toggle(prop)
    if isSitting and seatProp == prop then
        standUp()
    else
        if isSitting then standUp(); Wait(150) end
        sit(prop)
    end
end


-- ============================================================
-- REGISTRO NO vhub_target
-- ============================================================

CreateThread(function()
    while not exports['vhub_target'] do
        Wait(500)
    end

    exports['vhub_target']:addModel(SeatableProps, {
        -- opção "Sentar" — aparece quando NÃO está sentado nessa cadeira
        {
            name     = 'cadeira:sentar',
            label    = 'Sentar',
            icon     = 'fa-solid fa-chair',
            distance = 2.0,
            canInteract = function(entity)
                return not (isSitting and seatProp == entity)
            end,
            onSelect = function(data)
                toggle(data.entity)
            end,
        },
        -- opção "Levantar" — aparece somente quando está sentado NESSA cadeira
        {
            name     = 'cadeira:levantar',
            label    = 'Levantar',
            icon     = 'fa-solid fa-person-walking',
            distance = 3.0,  -- alcance maior: ped está sentado, olho sobe ~0.8m
            canInteract = function(entity)
                return isSitting and seatProp == entity
            end,
            onSelect = function(_)
                standUp()
            end,
        },
    })
end)


-- ============================================================
-- LIMPEZA
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isSitting then standUp() end
end)
