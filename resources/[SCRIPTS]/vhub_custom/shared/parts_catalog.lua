-- shared/parts_catalog.lua — CATÁLOGO DECLARATIVO de peças de engenharia (ADR #82 FASE 1)
--
-- SÓ DADOS. Zero SQL, zero evento, zero native, zero lógica de player/entidade. É a fonte única
-- do que EXISTE como peça; a LÓGICA (instalar/validar/cobrar/persistir/aplicar física) mora nos
-- sistemas (server/oficina.lua, vhub_vehcontrol). Compartilhado server+client p/ o preview da NUI.
--
-- MODELO DA PEÇA (ADR #82): peça = VETOR DE DELTAS com TRADE-OFFS, nunca "stage escalar maior vence".
-- Cada peça declara ganhos E penalidades nos 5 eixos canônicos do engine de skill (decisão #27):
--     potencia · grip · frenagem · aero · suspensao   (mesma ordem de vhub_vehcontrol/tier_rules)
--
-- ⚠️ OS DELTAS SÃO DESIGN, NÃO VERDADE FÍSICA (prompt §27). Na FASE 1 NENHUM delta é aplicado ao
--    veículo — a física é da Camada A (per-entidade, FASE 2) e Camada B (model-wide, ADR #83). Aqui
--    os deltas só descrevem a INTENÇÃO da peça e alimentam o preview/UX. Antes de virar física real:
--    pesquisa → benchmark → teste in-game → ADR.
--
-- DOMÍNIOS ORTOGONAIS (ADR #82 L-04): `parts` (engenharia) ≠ `mods` GTA (visual). Uma peça PODE
--    referenciar um `gta_mod` (índice/stage GTA) que o instalador aplica em `customization.mods`
--    na MESMA transação — o mod aparece no carro; o delta descreve o efeito. Um escritor (vhub_custom).
--
-- CAMPOS DA PEÇA:
--   id            string única (chave em customization.parts — SEMPRE string, nunca numérica)
--   family        agrupador na NUI (engine/turbo/brakes/transmission/suspension/handbrake)
--   name/desc     rótulo PT-BR e descrição curta
--   deltas        { eixo = número } — ganho(+)/penalidade(−) por eixo. Ausente = 0.
--   mass          (opcional) delta de PESO em kg (+ pesa / − alivia). ADR #85 F2.5-B: alimenta
--                 sheet.mass = base_mass + Σ mass (derivado, efêmero). Física de massa GATED (ADR #83).
--   price         custo em R$ (autoritativo server-side; a NUI só exibe)
--   item          (opcional) item_id do inventário consumido no install (1x). Ausente = peça sem
--                 gate de inventário (ex.: "voltar ao original" — só reverte, não consome nada).
--   gta_mod       (opcional) { index=<slot GTA>, stage=<0..3> } aplicado em customization.mods
--   capabilities  (opcional) tags que a peça HABILITA (ex.: 'drift') — derivadas, nunca 2ª verdade
--   requires      (opcional) ids exigidos instalados antes desta peça   ] GATE de compatibilidade,
--   conflicts     (opcional) ids que, instalados, impedem esta peça     ] ATIVO na ADR #85 F2.5-A
--   replaces      (opcional) ids que esta peça substitui (mesmo slot)   ] via Core.resolvePartStatus
--
-- ADR #85 F2.5-A: requires/conflicts/replaces são o gate REAL de instalação (compatibilidade).
-- `class_min` foi DESCARTADO de propósito: compatibilidade não é piso de classe — o DNA/classe
-- (class_budget/stageCap) virou só HINT não-bloqueante (nunca barra a instalação). Física fina
-- permanece GATED na Camada B (ADR #83); `mass` (kg) por peça entra na F2.5-B.
---@diagnostic disable: undefined-global, lowercase-global

VHubCustom = VHubCustom or {}


-- ============================================================
-- EIXOS (espelho de vhub_vehcontrol/tier_rules.TR.AXES — ordem canônica)
-- ============================================================

local AXES = { 'potencia', 'grip', 'frenagem', 'aero', 'suspensao' }


-- ============================================================
-- FAMÍLIAS (metadados de agrupamento p/ a NUI — rótulo + ordem)
-- ============================================================

local FAMILIES = {
  { id = 'engine',       label = 'Motor',          order = 1 },
  { id = 'turbo',        label = 'Indução',        order = 2 },
  { id = 'ecu',          label = 'ECU / Mapa',     order = 3 },
  { id = 'transmission', label = 'Transmissão',    order = 4 },
  { id = 'brakes',       label = 'Freios',         order = 5 },
  { id = 'suspension',   label = 'Suspensão',      order = 6 },
  { id = 'aero',         label = 'Aerodinâmica',   order = 7 },
  { id = 'weight',       label = 'Peso / Chassi',  order = 8 },
  { id = 'handbrake',    label = 'Freio de Mão',   order = 9 },
}


-- ============================================================
-- PEÇAS (vetor de deltas — trade-offs reais, sem "melhor peça"; ADR #85 F2.5)
-- ============================================================
-- Convenção de sinais: (+) melhora o eixo, (−) piora. NENHUMA peça é só ganho.
-- Eixos: potencia (potência/torque/aceleração) · grip (aderência/tração) · frenagem ·
--        aero (teto de velocidade; asa/downforce custa aero=arrasto) · suspensao (estabilidade).
-- mass  = delta de PESO em kg (+ pesa/− alivia) — ADR #85 F2.5-B (derivado; física gated ADR #83).
-- Uma peça por FAMÍLIA (slot único): cada peça `replaces` as irmãs. As "Originais" têm
-- gta_mod stage=0 → o install reseta o mod GTA ao stock (revert limpo). Famílias sem slot GTA
-- (ecu/aero/weight/handbrake) não têm gta_mod — instalam por lógica pura (deltas/mass/capability).

local PARTS = {

  -- ============================================================
  -- MOTOR (bloco — original / aspirado / turbinado)   [GTA idx 11]
  -- ============================================================
  {
    id = 'engine_original', family = 'engine',
    name = 'Motor Original', desc = 'Bloco de fábrica. Base equilibrada, sem trade-offs.',
    deltas = {}, mass = 0, price = 0,
    gta_mod = { index = 11, stage = 0 },
    replaces = { 'engine_aspirado', 'engine_turbo' },
  },
  {
    id = 'engine_aspirado', family = 'engine',
    name = 'Motor Aspirado 4-Cil (alta rotação)',
    desc = 'Resposta linear e previsível, leve. Sem pico de torque em baixa.',
    deltas = { potencia = 16, grip = 6, aero = -2 }, mass = -12, price = 22000,
    item = 'part_engine_aspirado',
    gta_mod = { index = 11, stage = 2 },
    replaces = { 'engine_original', 'engine_turbo' },
  },
  {
    id = 'engine_turbo', family = 'engine',
    name = 'Motor V6 Biturbo (bloco fechado)',
    desc = 'Torque brutal em cima. Perde tração na largada, esquenta e pesa mais.',
    deltas = { potencia = 30, grip = -8, frenagem = -3 }, mass = 24, price = 34000,
    item = 'part_engine_turbo',
    gta_mod = { index = 11, stage = 3 },
    replaces = { 'engine_original', 'engine_aspirado' },
    conflicts = { 'turbo_none' },   -- bloco biturbo exige indução forçada
  },

  -- ============================================================
  -- INDUÇÃO (marcas de turbina — potência × lag)      [GTA idx 18]
  -- ============================================================
  {
    id = 'turbo_none', family = 'turbo',
    name = 'Aspiração Natural', desc = 'Sem compressor. Resposta imediata, teto de potência menor.',
    deltas = {}, mass = 0, price = 0,
    gta_mod = { index = 18, stage = 0 },
    replaces = { 'turbo_kit', 'turbo_big' },
  },
  {
    id = 'turbo_kit', family = 'turbo',
    name = 'Turbo Garrett Single', desc = 'Sopro único equilibrado. Ganho firme de potência com lag leve.',
    deltas = { potencia = 15, grip = -5 }, mass = 10, price = 18000,
    item = 'part_turbo_kit',
    gta_mod = { index = 18, stage = 1 },
    replaces = { 'turbo_none', 'turbo_big' },
  },
  {
    id = 'turbo_big', family = 'turbo',
    name = 'Big Single Precision', desc = 'Monstro de topo. Potência enorme, lag pesado e teto de velocidade menor.',
    deltas = { potencia = 28, grip = -12, aero = -2 }, mass = 12, price = 30000,
    item = 'part_turbo_big',
    gta_mod = { index = 18, stage = 1 },
    replaces = { 'turbo_none', 'turbo_kit' },
  },

  -- ============================================================
  -- ECU / MAPA (tune eletrônico — sem slot GTA)
  -- ============================================================
  {
    id = 'ecu_stock', family = 'ecu',
    name = 'ECU de Fábrica', desc = 'Mapa original conservador. Sem ganho, sem risco.',
    deltas = {}, mass = 0, price = 0,
    replaces = { 'ecu_street', 'ecu_race', 'ecu_launch' },
  },
  {
    id = 'ecu_street', family = 'ecu',
    name = 'Remap Stage 1 (rua)', desc = 'Ganho seguro de potência, ajuda até a frenagem-motor.',
    deltas = { potencia = 6, frenagem = 1 }, mass = 0, price = 8000,
    item = 'part_ecu_street',
    replaces = { 'ecu_stock', 'ecu_race', 'ecu_launch' },
  },
  {
    id = 'ecu_race', family = 'ecu',
    name = 'Mapa de Pista (agressivo)', desc = 'Muita potência; difícil de colocar no chão (perde tração).',
    deltas = { potencia = 12, grip = -3 }, mass = 0, price = 16000,
    item = 'part_ecu_race',
    replaces = { 'ecu_stock', 'ecu_street', 'ecu_launch' },
  },
  {
    id = 'ecu_launch', family = 'ecu',
    name = 'Mapa Arrancada / Torque', desc = 'Torque em baixa para largada; encurta o fôlego de topo.',
    deltas = { potencia = 8, aero = -3 }, mass = 0, price = 12000,
    item = 'part_ecu_launch',
    replaces = { 'ecu_stock', 'ecu_street', 'ecu_race' },
  },

  -- ============================================================
  -- TRANSMISSÃO (aceleração × topo)                   [GTA idx 13]
  -- ============================================================
  {
    id = 'transmission_original', family = 'transmission',
    name = 'Câmbio Original', desc = 'Relação de fábrica. Equilíbrio neutro.',
    deltas = {}, mass = 0, price = 0,
    gta_mod = { index = 13, stage = 0 },
    replaces = { 'transmission_sport', 'transmission_race', 'transmission_long' },
  },
  {
    id = 'transmission_sport', family = 'transmission',
    name = 'Câmbio Esportivo (relação curta)', desc = 'Acelera mais rápido; perde um pouco de topo.',
    deltas = { potencia = 8, aero = -4 }, mass = 3, price = 14000,
    item = 'part_trans_sport',
    gta_mod = { index = 13, stage = 2 },
    replaces = { 'transmission_original', 'transmission_race', 'transmission_long' },
  },
  {
    id = 'transmission_race', family = 'transmission',
    name = 'Sequencial de Corrida', desc = 'Trocas instantâneas e leves. Rígido e punitivo em piso ruim.',
    deltas = { potencia = 12, suspensao = -3 }, mass = -5, price = 26000,
    item = 'part_trans_race',
    gta_mod = { index = 13, stage = 3 },
    replaces = { 'transmission_original', 'transmission_sport', 'transmission_long' },
  },
  {
    id = 'transmission_long', family = 'transmission',
    name = 'Relação Longa (topo de pista)', desc = 'Estica cada marcha p/ velocidade final; larga mais devagar.',
    deltas = { aero = 9, potencia = -3 }, mass = 2, price = 15000,
    item = 'part_trans_long',
    gta_mod = { index = 13, stage = 1 },
    replaces = { 'transmission_original', 'transmission_sport', 'transmission_race' },
  },

  -- ============================================================
  -- FREIOS (frenagem × peso)                          [GTA idx 12]
  -- ============================================================
  {
    id = 'brakes_original', family = 'brakes',
    name = 'Freios Originais', desc = 'Discos de série. Base neutra.',
    deltas = {}, mass = 0, price = 0,
    gta_mod = { index = 12, stage = 0 },
    replaces = { 'brakes_sport', 'brakes_race', 'brakes_drift' },
  },
  {
    id = 'brakes_sport', family = 'brakes',
    name = 'Freios Esportivos (disco ventilado)', desc = 'Frenagem firme e constante. Ganho de peso modesto.',
    deltas = { frenagem = 10, potencia = -1 }, mass = 5, price = 9000,
    item = 'part_brakes_sport',
    gta_mod = { index = 12, stage = 2 },
    replaces = { 'brakes_original', 'brakes_race', 'brakes_drift' },
  },
  {
    id = 'brakes_race', family = 'brakes',
    name = 'Freios de Competição (cerâmica)', desc = 'Frenagem máxima; caro em peso não-suspenso e rigidez.',
    deltas = { frenagem = 18, potencia = -3, suspensao = -2 }, mass = 10, price = 20000,
    item = 'part_brakes_race',
    gta_mod = { index = 12, stage = 3 },
    replaces = { 'brakes_original', 'brakes_sport', 'brakes_drift' },
  },
  {
    id = 'brakes_drift', family = 'brakes',
    name = 'Kit Freio Traseiro (drift)', desc = 'Viés traseiro para iniciar deslizes; abre mão de aderência.',
    deltas = { frenagem = 6, grip = -4 }, mass = 2, price = 11000,
    item = 'part_brakes_drift',
    gta_mod = { index = 12, stage = 1 },
    replaces = { 'brakes_original', 'brakes_sport', 'brakes_race' },
  },

  -- ============================================================
  -- SUSPENSÃO (estabilidade × curva × ângulo)         [GTA idx 15]
  -- ============================================================
  {
    id = 'suspension_original', family = 'suspension',
    name = 'Suspensão Original', desc = 'Geometria de série. Base neutra.',
    deltas = {}, mass = 0, price = 0,
    gta_mod = { index = 15, stage = 0 },
    replaces = { 'suspension_coilover', 'suspension_race', 'suspension_drift' },
  },
  {
    id = 'suspension_coilover', family = 'suspension',
    name = 'Coilover Regulável (rua)', desc = 'Ajustável: melhora curva e estabilidade, endurece a pilotagem.',
    deltas = { suspensao = 10, grip = 6, frenagem = -2 }, mass = 2, price = 12000,
    item = 'part_susp_street',
    gta_mod = { index = 15, stage = 2 },
    replaces = { 'suspension_original', 'suspension_race', 'suspension_drift' },
  },
  {
    id = 'suspension_race', family = 'suspension',
    name = 'Suspensão de Pista', desc = 'Cola em pista lisa; leve. Sofre em piso irregular e cria arrasto.',
    deltas = { suspensao = 16, grip = 10, aero = -4 }, mass = -3, price = 24000,
    item = 'part_susp_race',
    gta_mod = { index = 15, stage = 3 },
    replaces = { 'suspension_original', 'suspension_coilover', 'suspension_drift' },
  },
  {
    id = 'suspension_drift', family = 'suspension',
    name = 'Suspensão de Drift (ângulo alto)', desc = 'Muito esterço e controle de traseira; abre mão de aderência.',
    deltas = { suspensao = 8, grip = -6, frenagem = 2 }, mass = 0, price = 13000,
    item = 'part_susp_drift',
    gta_mod = { index = 15, stage = 1 },
    replaces = { 'suspension_original', 'suspension_coilover', 'suspension_race' },
  },

  -- ============================================================
  -- AERODINÂMICA (downforce × arrasto — sem slot GTA)
  -- ============================================================
  {
    id = 'aero_none', family = 'aero',
    name = 'Sem Aerodinâmica', desc = 'Lataria limpa. Menor arrasto, menor downforce.',
    deltas = {}, mass = 0, price = 0,
    replaces = { 'aero_lip', 'aero_wing', 'aero_active' },
  },
  {
    id = 'aero_lip', family = 'aero',
    name = 'Lip Frontal + Difusor', desc = 'Downforce sutil e equilibrado; leve custo de potência.',
    deltas = { aero = 4, grip = 4, potencia = -1 }, mass = 4, price = 7000,
    item = 'part_aero_lip',
    replaces = { 'aero_none', 'aero_wing', 'aero_active' },
  },
  {
    id = 'aero_wing', family = 'aero',
    name = 'Asa GT (downforce)', desc = 'Cola em alta velocidade; o arrasto derruba o topo de velocidade.',
    deltas = { grip = 10, aero = -6, suspensao = 2 }, mass = 8, price = 16000,
    item = 'part_aero_wing',
    replaces = { 'aero_none', 'aero_lip', 'aero_active' },
  },
  {
    id = 'aero_active', family = 'aero',
    name = 'Aerofólio Ativo (DRS)', desc = 'Fecha nas retas, abre nas curvas. Caro, mas sem grande penalidade.',
    deltas = { aero = 8, grip = 5 }, mass = 6, price = 28000,
    item = 'part_aero_active',
    replaces = { 'aero_none', 'aero_lip', 'aero_wing' },
  },

  -- ============================================================
  -- PESO / CHASSI (aligeirar × estabilizar — sem slot GTA)
  -- ============================================================
  {
    id = 'weight_stock', family = 'weight',
    name = 'Chassi de Série', desc = 'Peso de fábrica. Base neutra.',
    deltas = {}, mass = 0, price = 0,
    replaces = { 'weight_carbon', 'weight_ballast' },
  },
  {
    id = 'weight_carbon', family = 'weight',
    name = 'Kit Fibra de Carbono', desc = 'Alivia muito peso: ganha agilidade e frenagem; fica mais nervoso no topo.',
    deltas = { potencia = 2, grip = 4, frenagem = 2, aero = -2 }, mass = -60, price = 40000,
    item = 'part_carbon_kit',
    replaces = { 'weight_stock', 'weight_ballast' },
  },
  {
    id = 'weight_ballast', family = 'weight',
    name = 'Lastro de Estabilidade', desc = 'Adiciona peso baixo: plantado e estável, porém lento e preguiçoso.',
    deltas = { grip = 5, suspensao = 4, potencia = -3, aero = -2 }, mass = 80, price = 6000,
    item = 'part_ballast',
    replaces = { 'weight_stock', 'weight_carbon' },
  },

  -- ============================================================
  -- FREIO DE MÃO (original / profissional / hidráulico-drift — sem slot GTA)
  -- ============================================================
  -- Persiste via drift_capable (CUST_KEYS). O EFEITO físico do handbrake é da Camada B (ADR #83):
  -- até lá o hidráulico instala e HABILITA a capability 'drift', sem física fina — honesto.
  {
    id = 'handbrake_original', family = 'handbrake',
    name = 'Freio de Mão Original', desc = 'Alavanca de série. Sem capacidade de drift dedicada.',
    deltas = {}, mass = 0, price = 0,
    replaces = { 'handbrake_pro', 'handbrake_hydraulic' },
  },
  {
    id = 'handbrake_pro', family = 'handbrake',
    name = 'Freio de Mão Profissional', desc = 'Curso e trava melhores para manobra e baliza. Ganho discreto.',
    deltas = { frenagem = 3, suspensao = 2 }, mass = 1, price = 4000,
    item = 'part_handbrake_pro',
    replaces = { 'handbrake_original', 'handbrake_hydraulic' },
  },
  {
    id = 'handbrake_hydraulic', family = 'handbrake',
    name = 'Freio de Mão Hidráulico (Drift)', desc = 'Trava o eixo traseiro sob demanda. Habilita drift controlado.',
    deltas = { grip = -6, suspensao = 4 }, mass = 3, price = 4500,
    item = 'hydraulic_handbrake',
    capabilities = { 'drift' },
    replaces = { 'handbrake_original', 'handbrake_pro' },
  },
}


-- ============================================================
-- ÍNDICES DERIVADOS (montados 1x no load — leitura O(1) sem varrer a lista)
-- ============================================================

local BY_ID     = {}   -- [id] = peça
local BY_FAMILY = {}   -- [family] = { peça, ... } (ordem de declaração)

for _, p in ipairs(PARTS) do
  BY_ID[p.id] = p
  BY_FAMILY[p.family] = BY_FAMILY[p.family] or {}
  BY_FAMILY[p.family][#BY_FAMILY[p.family] + 1] = p
end


-- ============================================================
-- API DE LEITURA (pura — sem mutação; consumida por oficina.lua e pela NUI)
-- ============================================================

VHubCustom.PartsCatalog = {
  AXES     = AXES,
  FAMILIES = FAMILIES,
  PARTS    = PARTS,

  -- retorna a peça pelo id (ou nil) — a lógica de instalar valida contra isto (whitelist fechada)
  get = function(id)
    return type(id) == 'string' and BY_ID[id] or nil
  end,

  -- retorna a lista de peças de uma família (ou tabela vazia)
  byFamily = function(family)
    return BY_FAMILY[family] or {}
  end,

  -- payload FLAT (primitivos, L-19) p/ a NUI desenhar as famílias/peças sem conhecer a estrutura
  -- interna. Só dados de exibição — preço/deltas/gta_mod. NUNCA é autoridade (server revalida tudo).
  forNUI = function()
    local out = { families = {}, parts = {} }
    for _, f in ipairs(FAMILIES) do
      out.families[#out.families + 1] = { id = f.id, label = f.label, order = f.order }
    end
    for _, p in ipairs(PARTS) do
      out.parts[#out.parts + 1] = {
        id = p.id, family = p.family, name = p.name, desc = p.desc,
        deltas = p.deltas or {}, mass = p.mass or 0, price = p.price or 0,
        capabilities = p.capabilities or nil,
      }
    end
    return out
  end,
}

return VHubCustom.PartsCatalog
