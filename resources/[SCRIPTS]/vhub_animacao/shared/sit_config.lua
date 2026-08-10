-- shared/sit_config.lua — configuração de sentar em props (integrado ao vhub_animacao)

VHubAnimacao.Sit = {}


-- ============================================================
-- CENÁRIOS POR MODELO
-- ============================================================

-- Cenários GTA nativos para interação com props específicos.
-- Default = WORLD_HUMAN_SEAT_LEDGE (genérico, funciona em qualquer superfície).
VHubAnimacao.Sit.SCENARIO_BY_MODEL = {
    -- Poltronas / sofás → armchair scenario
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
    -- Cadeiras de escritório → chair scenario
    [joaat('prop_cs_office_chair')]          = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('v_corp_offchair')]               = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('v_club_officechair')]            = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('v_corp_bk_chair3')]              = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_01')]             = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_03')]             = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_04')]             = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_04b')]            = 'WORLD_HUMAN_SEAT_CHAIR',
    [joaat('prop_off_chair_05')]             = 'WORLD_HUMAN_SEAT_CHAIR',
    -- Bancos externos → bench/ledge (seleção aleatória do pool abaixo)
    [joaat('prop_bench_01a')]                = 'BENCH',
    [joaat('prop_bench_01b')]                = 'BENCH',
    [joaat('prop_bench_01c')]                = 'BENCH',
    [joaat('prop_bench_02')]                 = 'BENCH',
    [joaat('prop_bench_03')]                 = 'BENCH',
    [joaat('prop_bench_04')]                 = 'BENCH',
    [joaat('prop_bench_05')]                 = 'BENCH',
    [joaat('prop_bench_06')]                 = 'BENCH',
    [joaat('prop_bench_07')]                 = 'BENCH',
    [joaat('prop_bench_08')]                 = 'BENCH',
    [joaat('prop_bench_09')]                 = 'BENCH',
    [joaat('prop_bench_10')]                 = 'BENCH',
    [joaat('prop_bench_11')]                 = 'BENCH',
    [joaat('prop_air_bench_01')]             = 'BENCH',
    [joaat('prop_air_bench_02')]             = 'BENCH',
    [joaat('prop_fib_3b_bench')]             = 'BENCH',
}

-- Pool de cenários para bancos/ledges — selecionado aleatoriamente para variedade.
VHubAnimacao.Sit.BENCH_SCENARIOS = {
    'WORLD_HUMAN_SEAT_WALL',
    'WORLD_HUMAN_SEAT_LEDGE',
    'PROP_HUMAN_SEAT_BENCH',
    'PROP_HUMAN_SEAT_CHAIR',
    'PROP_HUMAN_SEAT_BUS_STOP_WAIT',
    'PROP_HUMAN_SEAT_ARMCHAIR',
    'PROP_HUMAN_SEAT_STRIP_WATCH',
}


-- ============================================================
-- OFFSET Z POR MODELO
-- ============================================================

-- Offset Z do assento em relação à *origem* do prop (centro geométrico do mesh GTA).
-- Usado SOMENTE como fallback quando o raycast vertical não encontra a superfície.
-- Para bancos externos: origem fica ~0.4m do chão; assento fica ~0.0–0.05m acima da origem.
-- Para poltronas/sofás: origem no centro da peça; assento fica ~0.05–0.10m acima.
VHubAnimacao.Sit.ZOFFSET_BY_MODEL = {
    -- Sofás / poltronas
    [joaat('prop_armchair_01')]            = 0.05,
    [joaat('apa_mp_h_stn_sofa3seat_01')]   = 0.05,
    [joaat('apa_mp_h_stn_sofa3seat_02')]   = 0.05,
    [joaat('apa_mp_h_stn_sofa2seat_02')]   = 0.05,
    [joaat('apa_mp_h_stn_sofa_daybed_01')] = 0.03,
    [joaat('apa_mp_h_stn_sofa_daybed_02')] = 0.03,
    -- Bancos externos (assento ~mesmo nível da origem do prop)
    [joaat('prop_bench_01a')]              = 0.0,
    [joaat('prop_bench_01b')]              = 0.0,
    [joaat('prop_bench_01c')]              = 0.0,
    [joaat('prop_bench_02')]               = 0.0,
    [joaat('prop_bench_03')]               = 0.0,
    [joaat('prop_bench_04')]               = 0.0,
    [joaat('prop_bench_05')]               = 0.0,
    [joaat('prop_bench_06')]               = 0.0,
    [joaat('prop_bench_07')]               = 0.0,
    [joaat('prop_bench_08')]               = 0.0,
    [joaat('prop_bench_09')]               = 0.0,
    [joaat('prop_bench_10')]               = 0.0,
    [joaat('prop_bench_11')]               = 0.0,
    [joaat('prop_air_bench_01')]           = 0.02,
    [joaat('prop_air_bench_02')]           = 0.02,
    [joaat('prop_fib_3b_bench')]           = 0.02,
}

-- Retorna offset Z ou 0.05 m como padrão genérico (fallback; raycast é preferido).
function VHubAnimacao.Sit.getZOffset(prop)
    return VHubAnimacao.Sit.ZOFFSET_BY_MODEL[GetEntityModel(prop)] or 0.05
end

-- Retorna cenário nativo para o prop; 'BENCH' é resolvido para pool aleatório.
function VHubAnimacao.Sit.getScenario(prop)
    local sc = VHubAnimacao.Sit.SCENARIO_BY_MODEL[GetEntityModel(prop)]
    if sc == 'BENCH' then
        return VHubAnimacao.Sit.BENCH_SCENARIOS[math.random(#VHubAnimacao.Sit.BENCH_SCENARIOS)]
    end
    return sc or 'WORLD_HUMAN_SEAT_LEDGE'
end
