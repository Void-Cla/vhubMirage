-- shared/config.lua — vhub_racha v3 (Liga clandestina premium)
-- Brand, regras globais e catalogo de pistas pre-definidas.

VHubRachaCfg = {
  -- ── Brand ───────────────────────────────────────────────────────────────
  BRAND_NAME = 'Mirage Racha',
  BRAND_TAG  = 'Liga clandestina',

  -- ── Owner / permissoes ──────────────────────────────────────────────────
  OWNER_CHAR_ID    = 1,
  ADMIN_ACE        = 'vhub.racha.admin',
  ADMIN_PERMISSION = 'vhub.racha.admin',
  EDITOR_PERMISSION = 'vhub.racha.editor',
  TRUSTED_RESOURCES = { ['vhub'] = true, ['vhub_admin'] = true },

  -- ── Comandos / atalho ──────────────────────────────────────────────────
  CMD_OPEN          = 'racha',          -- /racha → abre painel principal
  KEY_OPEN          = 'F7',
  CMD_TRAINING      = 'racha_treino',   -- /racha_treino <track_id> → solo sem premio
  -- Editor (sempre via NUI; comandos sao backup p/ debug)
  CMD_EDITOR_DEBUG  = 'racha_editor',
  CMD_EDITOR_PT     = 'racha_editor_pos',

  -- ── Lobby ──────────────────────────────────────────────────────────────
  LOBBY_TTL_MS        = 300000,   -- 5 min: lobby sem confirmar = cancela
  PENDING_TTL_MS      = 300000,   -- 5 min: tempo para confirmar presenca apos entrar
  COUNTDOWN_MS        = 7000,
  FINISH_GRACE_MS     = 60000,
  MIN_CHECKPOINT_MS   = 400,
  TICK_INTERVAL_MS    = 1000,

  -- ── Ready Zone (confirmacao de presenca na largada) ────────────────────
  -- Visual: gas/fumaca de areia dourada bem fraco no chao — so para o piloto
  -- identificar que esta no lugar certo. NADA de cilindro opaco gritante.
  READY_ZONE = {
    RADIUS_M        = 18.0,        -- raio do circulo de confirmacao
    Z_TOLERANCE     = 5.0,         -- diferenca de altura aceita
    REQUIRE_VEHICLE = false,       -- pode confirmar a pe ou em qualquer veiculo?
    GAS_COLOR       = { r = 232, g = 198, b = 130 },  -- areia dourada
    GAS_ALPHA       = 32,          -- gas quase invisivel no chao
    GAS_WISPS       = 14,          -- numero de baforadas de fumaca
    -- compat legado
    GLOW_COLOR      = { r = 232, g = 198, b = 130, a = 32 },
    GLOW_HEIGHT     = 2.5,
  },

  -- ── Editor ─────────────────────────────────────────────────────────────
  EDITOR_MAX_CPS      = 80,
  EDITOR_MAX_GRID     = 12,
  EDITOR_DRAFT_TTL_MS = 1800000,

  -- ── Anti-cheat ─────────────────────────────────────────────────────────
  CP_MAX_TELEPORT_DIST = 300.0,
  MAX_SPEED_KMH        = 400,

  -- ── Premio / payout ────────────────────────────────────────────────────
  MAX_ENTRY_FEE        = 100000,
  DEFAULT_ENTRY_FEE    = 1000,
  PAYOUT_3P            = { 0.70, 0.20, 0.10 },
  PAYOUT_2P            = { 0.80, 0.20 },
  PAYOUT_SOLO          = { 1.00 },
  TIMEATTACK_BONUS_PCT = 50,

  -- ── Drift scoring ───────────────────────────────────────────────────────
  -- A FABRICACAO da pontuacao bruta (angulo x velocidade x combo) vive no
  -- resource "Drift" (exports.Drift:getTelemetry). Aqui ficam:
  --   • BANK_MS                → regra de BANCO do modo (client/modes/drift.lua)
  --   • CAP_PER_SEC, COMBO_MULT → cap server-side (runtime.lua / anti_cheat.lua)
  -- Mantenha CAP_PER_SEC / COMBO_MULT alinhados com os do resource "Drift".
  DRIFT = {
    BANK_MS          = 5000,   -- ms de drift sem bater p/ o lote virar valido
    CAP_PER_SEC      = 100,    -- teto server-side (alinhado com SCORE_CAP_PER_SEC do Drift)
    COMBO_MULT       = { 1.5, 2.0, 3.0 },
  },

  -- ── Drag (1/4 mile) ────────────────────────────────────────────────────
  DRAG = {
    SEMAFORO_GREEN_MS = 3000,
    FALSE_START_MS    = 500,
    LANE_SEPARATION   = 4.5,
  },

  -- ── Speed trap ─────────────────────────────────────────────────────────
  SPEEDTRAP = {
    RADIUS_M    = 6.0,
    COMBO_BONUS = 1.05,
  },

  -- ── Polícia / Heat ─────────────────────────────────────────────────────
  POLICE = {
    PERMISSION  = 'policia.radio',
    BLIP_TTL_MS = 90000,
    HEAT_PER_MIN = 1,
  },

  -- ── HUD ─────────────────────────────────────────────────────────────────
  -- Todo o HUD de corrida e renderizado pela NUI (web/modules/hud). O HUD Lua
  -- DrawText legado foi removido. USE_NUI deve permanecer true — e a flag que
  -- libera o envio de telemetria/statebag para a NUI em client/nui_bridge.lua.
  HUD = {
    USE_NUI = true,
  },

  -- ── Totem de checkpoint (estilo Forza — nativo, totem unico) ────────────
  -- UMA unica linha fina e longa, cor de areia de ouro neon, que nasce NO CHAO
  -- (sem flutuar) e sobe. Mais ALTA a 999m, encolhe ate sumir no 0m. Na base,
  -- uma nuvem de areia quase transparente (sombra suave). Contador (%m) no topo.
  -- Renderizado SEMPRE nativo (DrawMarker/DrawText) — um totem, sem duplicacao.
  TOTEM = {
    -- Alcance maximo de render (m)
    RENDER_RANGE     = 999.0,
    -- Altura: mais alta a 999m (= SCALE_DIST), encolhe linear ate MIN no 0m.
    SCALE_DIST       = 999.0,
    MIN_HEIGHT       = 5.0,
    MAX_HEIGHT       = 150.0,
    -- Espessura da linha (FINA — uma unica camada solida)
    COLUMN_W         = 0.55,
    -- Offset do chao: desce a base do CP ate o solo (ajuste se afundar/flutuar)
    GROUND_OFFSET    = 0.5,
    -- Raio da nuvem de areia na base (sombra suave, nao o diametro do CP)
    BASE_RADIUS      = 5.0,
    -- Cores (RGB)
    COLOR_DEFAULT    = { r = 248, g = 200, b = 105 },  -- AREIA DE OURO NEON (padrao)
    COLOR_FINISH     = { r = 120, g = 230, b = 140 },  -- verde no CP final
    COLOR_SPEEDTRAP  = { r = 38,  g = 220, b = 80  },  -- speedtrap = radar verde
    COLOR_DRIFT_ZONE = { r = 190, g = 120, b = 255 },  -- drift zone roxo
  },

  -- ── Estilo geral (mantido para compat) ─────────────────────────────────
  COLOR = { r = 243, g = 181, b = 58 },
  -- Blips desligados por padrao: o totem ja marca o ponto de partida.
  -- O painel /racha mostra a lista visual.
  BLIP = { show = false, sprite = 38, color = 5, scale = 0.75 },
}

-- ─── Catalogo de pistas pre-definidas ────────────────────────────────────────
--
-- Coords aceitam 5 formatos (normalizado em shared/checkpoints.lua):
--
--   1. { x = X, y = Y, z = Z [, h = H] }              ← canonico
--   2. vec3(X, Y, Z)                                   ← FiveM nativo
--   3. { X, Y, Z [, H] }                               ← array curto
--   4. "x = N, y = N, z = N"                           ← string do comando /cds
--   5. { cds = vec3(X, Y, Z), h = H }                  ← PREFERIDO p/ grid (estilo nation_race)
--
-- Exemplo recomendado para tracks novas (sintaxe humana, separa coord+heading):
--
--   start = vec3(2658.68, 1693.25, 24.49),  -- heading 0 implicito
--   grid  = {
--     { cds = vec3(2662.46, 1645.46, 23.87), h = 268.71 },
--     { cds = vec3(2662.19, 1638.51, 23.87), h = 270.82 },
--   },
--   checkpoints = {
--     vec3(2821.18, 1650.77, 23.94),
--     vec3(2813.19, 1701.23, 23.97),
--     vec3(2689.22, 1623.83, 23.84),
--   },
--
-- Campos opcionais por track: ready_zone = { x, y, z, radius } (override do start)
-- As 8 pistas atuais (vrp_1..vrp_8) usam o formato 1 — funcionam sem migracao.

-- Imported tracks converted from exemplos/.../vrp_races (vrp_races client-side)
-- IDs: vrp_1 .. vrp_8
VHubRachaTracks = {
  {
    id = 'corrida_atk', label = 'atk 1', district = 'atk',
    kind = 'sprint', illegal = true, alerts_police = false,
    laps = 1, min_players = 1, max_players = 2, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 900,
    color = { r = 243, g = 181, b = 58 },
    start = vec3(2658.68,1693.25,24.49),
    grid = {
      { cds = vec3(2662.46,1645.46,23.87), h = 268.71 },
      { cds = vec3(2662.19,1638.51,23.87), h = 270.82 },
    },
    checkpoints = {
      vec3(2821.18,1650.77,23.94),
      vec3(2813.19,1701.23,23.97),
      vec3(2689.22,1623.83,23.84),
      vec3(2697.15,1404.43,23.82),
      vec3(2762.31,1408.47,23.79),
      vec3(2793.46,1477.66,23.83),
      vec3(2866.73,1538.0,23.85),
      vec3(2813.99,1590.36,23.82),
      vec3(2811.48,1639.52,23.86),
      vec3(2690.64,1634.67,23.84),
      vec3(2689.01,1428.43,23.85),
    },
  },
  {
    id = 'banham_blitz', label = 'Banham Blitz', district = 'Great Ocean',
    kind = 'sprint', illegal = true, alerts_police = false,
    laps = 1, min_players = 1, max_players = 4, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 150,
    color = { r = 38, g = 248, b = 255 },
    start = vec3(-2298.28, 378.65, 174.47),
    grid = {
      { cds = vec3(-2307.71, 457.17, 173.8), h = 354.08 },
      { cds = vec3(-2302.16, 453.45, 173.8), h = 352.78 },
      { cds = vec3(-2308.31, 451.21, 173.8), h = 353.54 },
      { cds = vec3(-2303.08, 447.53, 173.8), h = 353.50 },
    },
    checkpoints = {
      vec3(-1727.0, 91.72, 65.86),
      vec3(-1377.11, 374.27, 63.65),
      vec3(-815.86, 440.66, 88.8),
      vec3(-553.78, 522.46, 106.42),
      vec3(-492.91, 566.07, 119.48),
      vec3(-332.35, 486.51, 112.15),
      vec3(-125.53, 528.42, 142.92),
      vec3(290.41, 768.15, 183.99),
      vec3(299.57, 841.45, 192.12),
      vec3(466.85, 892.61, 197.44),
      vec3(481.5, 1308.91, 278.97),
      vec3(810.19, 1275.74, 359.84),
    },
  },
  {
    id = 'vinewood_descent', label = 'Vinewood Descent', district = 'Vinewood',
    kind = 'sprint', illegal = true, alerts_police = false,
    laps = 1, min_players = 1, max_players = 4, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 300,
    color = { r = 38, g = 248, b = 255 },
    start = vec3(647.39, 643.86, 128.3),
    grid = {
      { cds = vec3(729.21, 630.86, 128.25), h = 251.88 },
      { cds = vec3(728.09, 627.25, 128.25), h = 250.68 },
      { cds = vec3(725.16, 619.97, 128.25), h = 249.77 },
      { cds = vec3(723.72, 616.2, 128.25), h = 247.32 },
    },
    checkpoints = {
      vec3(911.84, 514.06, 120.21),
      vec3(561.19, 227.4, 102.25),
      vec3(202.51, -831.25, 30.2),
      vec3(406.98, -829.44, 28.67),
      vec3(392.96, -677.53, 28.65),
      vec3(-50.86, -528.43, 39.72),
      vec3(91.64, -179.04, 54.28),
      vec3(216.66, -245.59, 53.01),
      vec3(168.26, -325.24, 43.46),
      vec3(-137.46, -292.58, 39.75),
      vec3(-623.44, -349.55, 34.1),
      vec3(-784.91, -120.13, 37.13),
      vec3(-1006.65, -200.53, 37.16),
      vec3(-1411.91, -59.47, 52.26),
      vec3(-1521.02, -218.13, 52.06),
      vec3(-941.6, -850.95, 14.92),
      vec3(-791.48, -1121.17, 10.03),
      vec3(-1166.17, -1296.35, 4.55),
      vec3(-1451.76, -771.25, 22.85),
      vec3(-1769.71, -1152.83, 12.42),
    },
  },
}
