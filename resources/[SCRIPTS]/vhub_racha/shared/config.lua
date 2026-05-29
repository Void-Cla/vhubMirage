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

  -- ── Drift scoring (calculado client-side, validado server-side) ────────
  DRIFT = {
    MIN_ANGLE_DEG    = 15.0,
    MIN_SPEED_KMH    = 30.0,
    POINTS_DIVISOR   = 40,
    CAP_PER_SEC      = 150,
    COMBO_THRESHOLDS = { 5, 12, 25 },
    COMBO_MULT       = { 1.5, 2.0, 3.0 },
    BREAK_ANGLE_DEG  = 8.0,
    BREAK_MS         = 700,
    IMPACT_THRESHOLD = 8.0,
    IMPACT_PENALTY   = 0.5,
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
  -- Coluna FINA e LONGA de areia dourada com nucleo quase branco e glow forte,
  -- mais ALTA a 999m e ENCOLHE ate sumir no 0m. Base com rasteirinha de poeira
  -- marcando o diametro do CP + baforadas subindo. Contador km + label no topo.
  -- Renderizado SEMPRE nativo (DrawMarker/DrawText) — um totem, sem duplicacao.
  TOTEM = {
    -- Alcance maximo de render (m)
    RENDER_RANGE     = 999.0,
    -- Altura: mais alta a 999m (= SCALE_DIST), encolhe linear ate MIN no 0m.
    SCALE_DIST       = 999.0,
    MIN_HEIGHT       = 8.0,
    MAX_HEIGHT       = 150.0,
    -- Espessura da coluna (FINA): nucleo solido + halo de glow
    COLUMN_CORE_W    = 0.45,
    COLUMN_GLOW_W    = 1.3,
    -- Raio do CP (a rasteirinha de poeira marca o diametro = 2x esse valor)
    BASE_RADIUS      = 11.0,
    -- Baforadas de poeira subindo na base
    DUST_COUNT       = 10,
    -- Frequencia do pulso de brilho
    PULSE_FREQ_HZ    = 0.7,
    -- Cores (RGB)
    COLOR_DEFAULT    = { r = 232, g = 198, b = 130 },  -- AREIA DOURADA (corpo)
    COLOR_CORE       = { r = 255, g = 244, b = 210 },  -- nucleo quase branco
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
    id = 'vrp_1', label = 'VRP Race 1', district = 'VRP',
    kind = 'circuit', illegal = true, alerts_police = false,
    laps = 3, min_players = 1, max_players = 8, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 900,
    color = { r = 243, g = 181, b = 58 },
    start = { x = 2679.43, y = 3443.93, z = 55.81, h = 0.0 },
    grid = {
      { x = 2679.43, y = 3443.93, z = 55.81, h = 0.0 },
      { x = 2676.43, y = 3443.93, z = 55.81, h = 0.0 },
      { x = 2682.43, y = 3443.93, z = 55.81, h = 0.0 },
      { x = 2685.43, y = 3443.93, z = 55.81, h = 0.0 },
    },
    checkpoints = {
      { x = 2750.48, y = 3414.08, z = 55.77 },
      { x = 2549.74, y = 3056.91, z = 43.42 },
      { x = 2250.66, y = 3009.13, z = 44.70 },
      { x = 1732.12, y = 3447.20, z = 38.13 },
      { x = 1189.73, y = 3536.38, z = 34.54 },
      { x = 370.91,  y = 3464.73, z = 34.76 },
      { x = 270.57,  y = 2697.06, z = 43.59 },
      { x = 432.97,  y = 2674.04, z = 43.34 },
      { x = 1406.58, y = 2699.75, z = 37.00 },
      { x = 1907.79, y = 2965.44, z = 45.12 },
      { x = 2049.76, y = 3063.96, z = 45.95 },
      { x = 1886.37, y = 3200.55, z = 45.24 },
      { x = 2259.58, y = 3248.10, z = 47.58 },
      { x = 2576.37, y = 3270.15, z = 51.17 },
      { x = 2685.91, y = 3441.63, z = 55.25 },
    },
  },
  {
    id = 'vrp_2', label = 'VRP Race 2', district = 'VRP',
    kind = 'circuit', illegal = true, alerts_police = true,
    laps = 3, min_players = 1, max_players = 8, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 1200,
    color = { r = 38, g = 248, b = 255 },
    start = { x = -566.72, y = -2117.39, z = 5.98, h = 45.0 },
    grid = {
      { x = -566.72, y = -2117.39, z = 5.98, h = 45.0 },
      { x = -570.72, y = -2117.39, z = 5.98, h = 45.0 },
      { x = -562.72, y = -2117.39, z = 5.98, h = 45.0 },
    },
    checkpoints = {
      { x = -566.24, y = -2065.50, z = 6.25 },
      { x = -256.74, y = -2196.93, z = 9.79 },
      { x = -200.51, y = -1881.79, z = 27.31 },
      { x = 16.53,   y = -1694.03, z = 28.76 },
      { x = -171.71, y = -1472.82, z = 31.58 },
      { x = 51.95,   y = -1372.56, z = 28.76 },
      { x = 69.05,   y = -1178.94, z = 28.75 },
      { x = -63.12,  y = -1134.79, z = 25.31 },
      { x = -193.62, y = -1408.00, z = 30.70 },
      { x = -406.04, y = -1791.38, z = 20.98 },
      { x = -152.28, y = -1979.94, z = 22.33 },
      { x = -285.66, y = -2112.61, z = 21.72 },
      { x = -513.33, y = -1916.75, z = 26.94 },
      { x = -724.83, y = -2138.99, z = 12.82 },
      { x = -1035.16,y = -2549.10, z = 13.21 },
      { x = -853.76, y = -2590.61, z = 13.21 },
      { x = -790.83, y = -2322.36, z = 14.20 },
      { x = -768.50, y = -2147.59, z = 8.29 },
      { x = -755.31, y = -2045.03, z = 8.36 },
      { x = -788.29, y = -1980.52, z = 8.49 },
      { x = -635.59, y = -1991.78, z = 5.76 },
    },
  },
  {
    id = 'vrp_3', label = 'VRP Race 3', district = 'VRP',
    kind = 'circuit', illegal = true, alerts_police = false,
    laps = 2, min_players = 1, max_players = 8, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 1200,
    color = { r = 243, g = 181, b = 58 },
    start = { x = 1679.40, y = -1564.53, z = 112.57, h = 0.0 },
    grid = {
      { x = 1679.40, y = -1564.53, z = 112.57, h = 0.0 },
      { x = 1676.40, y = -1564.53, z = 112.57, h = 0.0 },
      { x = 1682.40, y = -1564.53, z = 112.57, h = 0.0 },
    },
    checkpoints = {
      { x = 1628.26, y = -1574.17, z = 102.08 },
      { x = 1533.88, y = -1683.19, z = 83.68 },
      { x = 1482.93, y = -1818.75, z = 70.58 },
      { x = 1407.33, y = -1627.96, z = 58.23 },
      { x = 1279.40, y = -1483.58, z = 37.09 },
      { x = 866.52,  y = -1432.02, z = 28.68 },
      { x = 793.61,  y = -1076.04, z = 27.97 },
      { x = 594.23,  y = -1021.29, z = 36.50 },
      { x = 281.12,  y = -1046.65, z = 28.66 },
      { x = 182.17,  y = -1347.28, z = 28.76 },
      { x = 408.03,  y = -1597.39, z = 28.76 },
      { x = 307.26,  y = -1803.13, z = 27.09 },
      { x = 438.59,  y = -2022.79, z = 22.81 },
      { x = 716.72,  y = -2067.17, z = 28.75 },
      { x = 831.91,  y = -1810.98, z = 28.56 },
      { x = 1100.99, y = -1743.61, z = 35.13 },
      { x = 1222.70, y = -1621.49, z = 49.07 },
      { x = 1362.82, y = -1539.00, z = 54.66 },
      { x = 1526.84, y = -1459.91, z = 72.22 },
      { x = 1705.10, y = -1335.23, z = 85.66 },
      { x = 1787.15, y = -1378.23, z = 104.60 },
      { x = 1692.44, y = -1479.90, z = 112.35 },
    },
  },
  {
    id = 'vrp_4', label = 'VRP Race 4', district = 'VRP',
    kind = 'circuit', illegal = true, alerts_police = false,
    laps = 3, min_players = 1, max_players = 8, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 1200,
    color = { r = 243, g = 181, b = 58 },
    start = { x = -1732.07, y = -727.34, z = 10.40, h = 0.0 },
    grid = {
      { x = -1732.07, y = -727.34, z = 10.40, h = 0.0 },
      { x = -1729.07, y = -727.34, z = 10.40, h = 0.0 },
      { x = -1735.07, y = -727.34, z = 10.40, h = 0.0 },
    },
    checkpoints = {
      { x = -1687.25, y = -725.70, z = 10.13 },
      { x = -1321.66, y = -1063.46, z = 6.55 },
      { x = -1266.54, y = -998.04, z = 9.20 },
      { x = -1091.11, y = -756.76, z = 18.80 },
      { x = -1344.93, y = -431.61, z = 34.26 },
      { x = -1094.49, y = -231.70, z = 37.20 },
      { x = -1269.32, y = -63.08,  z = 44.89 },
      { x = -1614.40, y = -233.92, z = 53.72 },
      { x = -1744.35, y = -511.75, z = 37.96 },
      { x = -1945.50, y = -427.97, z = 18.21 },
      { x = -1888.41, y = -551.31, z = 11.14 },
    },
  },
  {
    id = 'vrp_5', label = 'VRP Race 5', district = 'VRP',
    kind = 'circuit', illegal = true, alerts_police = false,
    laps = 3, min_players = 1, max_players = 8, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 1200,
    color = { r = 243, g = 181, b = 58 },
    start = { x = -1367.59, y = 15.04, z = 53.38, h = 0.0 },
    grid = {
      { x = -1367.59, y = 15.04, z = 53.38, h = 0.0 },
      { x = -1370.59, y = 15.04, z = 53.38, h = 0.0 },
      { x = -1364.59, y = 15.04, z = 53.38, h = 0.0 },
    },
    checkpoints = {
      { x = -1364.17, y = -49.72, z = 51.24 },
      { x = -1435.79, y = -155.72, z = 47.70 },
      { x = -1278.39, y = -398.14, z = 35.38 },
      { x = -959.16,  y = -323.14, z = 37.54 },
      { x = -707.23,  y = -361.29, z = 33.95 },
      { x = -345.00,  y = -199.92, z = 37.47 },
      { x = -177.95,  y = -82.47,  z = 52.17 },
      { x = 19.43,    y = 210.70,  z = 106.59 },
      { x = -68.28,   y = 290.18,  z = 104.94 },
      { x = -187.34,  y = 427.57,  z = 109.83 },
      { x = -403.84,  y = 402.70,  z = 108.28 },
      { x = -531.58,  y = 395.15,  z = 88.31 },
      { x = -709.42,  y = 288.86,  z = 83.54 },
      { x = -856.58,  y = 407.08,  z = 86.74 },
      { x = -1077.65, y = 342.12,  z = 66.66 },
      { x = -907.13,  y = -79.22,  z = 37.37 },
      { x = -1207.93, y = -97.10,  z = 41.11 },
    },
  },
  {
    id = 'vrp_6', label = 'VRP Race 6', district = 'VRP',
    kind = 'sprint', illegal = true, alerts_police = false,
    laps = 1, min_players = 1, max_players = 8, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 900,
    color = { r = 243, g = 181, b = 58 },
    start = { x = 636.43, y = 649.90, z = 128.90, h = 0.0 },
    grid = {
      { x = 636.43, y = 649.90, z = 128.90, h = 0.0 },
      { x = 633.43, y = 649.90, z = 128.90, h = 0.0 },
      { x = 639.43, y = 649.90, z = 128.90, h = 0.0 },
    },
    checkpoints = {
      { x = 977.00,  y = 515.89,  z = 105.31 },
      { x = 736.79,  y = 74.64,   z = 81.42 },
      { x = 1208.18, y = -325.41, z = 68.54 },
      { x = 962.42,  y = -481.13, z = 61.05 },
      { x = 1120.51, y = -758.95, z = 57.22 },
      { x = 1104.80, y = -836.17, z = 51.81 },
      { x = 766.73,  y = -620.24, z = 37.00 },
      { x = 389.20,  y = -472.41, z = 40.91 },
      { x = 187.44,  y = -761.89, z = 32.12 },
      { x = -10.00,  y = -885.34, z = 29.42 },
      { x = -413.70, y = -835.13, z = 30.92 },
      { x = -520.68, y = -918.21, z = 24.42 },
      { x = -591.87, y = -957.69, z = 21.94 },
      { x = -1177.59,y = -1345.46,z = 4.41 },
      { x = -1124.65,y = -1525.95,z = 3.81 },
      { x = -1078.36,y = -1481.84,z = 4.57 },
      { x = -825.81, y = -1156.65,z = 6.79 },
      { x = -699.42, y = -1226.00,z = 10.08 },
      { x = -567.34, y = -1222.98,z = 15.79 },
      { x = -513.52, y = -1298.88,z = 27.13 },
      { x = -340.87, y = -1438.61,z = 29.35 },
      { x = -285.09, y = -1113.67,z = 22.44 },
      { x = -339.25, y = -1089.42,z = 22.44 },
    },
  },
  {
    id = 'vrp_7', label = 'VRP Race 7', district = 'VRP',
    kind = 'sprint', illegal = true, alerts_police = false,
    laps = 1, min_players = 1, max_players = 8, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 900,
    color = { r = 243, g = 181, b = 58 },
    start = { x = 364.86, y = -543.57, z = 28.75, h = 0.0 },
    grid = {
      { x = 364.86, y = -543.57, z = 28.75, h = 0.0 },
      { x = 361.86, y = -543.57, z = 28.75, h = 0.0 },
      { x = 367.86, y = -543.57, z = 28.75, h = 0.0 },
    },
    checkpoints = {
      { x = 533.25, y = -414.31, z = 31.14 },
      { x = 921.26, y = 180.32,  z = 74.76 },
      { x = 966.95, y = 518.44,  z = 108.04 },
      { x = 719.20, y = 339.06,  z = 112.22 },
      { x = 448.88, y = 420.81,  z = 139.67 },
      { x = 303.33, y = 586.04,  z = 153.65 },
      { x = 240.08, y = 475.68,  z = 125.26 },
      { x = 53.07,  y = 310.46,  z = 110.64 },
      { x = 130.74, y = 213.78,  z = 106.63 },
      { x = 94.49,  y = -104.61, z = 58.28 },
      { x = -12.92, y = -127.54, z = 56.19 },
      { x = -169.55,y = -390.98, z = 32.82 },
      { x = -170.70,y = -705.57, z = 33.88 },
      { x = -165.81,y = -825.46, z = 30.51 },
      { x = 157.93, y = -1026.31,z = 28.78 },
      { x = 362.35, y = -669.27, z = 28.73 },
    },
  },
  {
    id = 'vrp_8', label = 'VRP Race 8', district = 'VRP',
    kind = 'circuit', illegal = true, alerts_police = false,
    laps = 3, min_players = 1, max_players = 8, vehicle_class = 'car',
    default_fee = 1000, limit_seconds = 1200,
    color = { r = 243, g = 181, b = 58 },
    start = { x = 247.31, y = -1513.38, z = 29.10, h = 0.0 },
    grid = {
      { x = 247.31, y = -1513.38, z = 29.10, h = 0.0 },
      { x = 244.31, y = -1513.38, z = 29.10, h = 0.0 },
      { x = 250.31, y = -1513.38, z = 29.10, h = 0.0 },
    },
    checkpoints = {
      { x = 204.64, y = -1573.60, z = 28.75 },
      { x = -74.43, y = -1723.62, z = 28.75 },
      { x = 6.18,   y = -1857.65, z = 23.51 },
      { x = 243.72, y = -1710.35, z = 28.54 },
      { x = 420.14, y = -1789.33, z = 28.26 },
      { x = 499.28, y = -1740.73, z = 28.37 },
      { x = 769.56, y = -1746.88, z = 28.96 },
      { x = 820.75, y = -1504.11, z = 27.80 },
      { x = 280.67, y = -1297.54, z = 29.17 },
      { x = 218.93, y = -1105.09, z = 28.75 },
      { x = 165.16, y = -1018.15, z = 28.78 },
      { x = 117.60, y = -1377.83, z = 28.75 },
      { x = 269.36, y = -1481.18, z = 28.75 },
    },
  },
}
