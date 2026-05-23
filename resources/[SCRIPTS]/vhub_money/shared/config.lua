-- shared/config.lua — vhub_money (Fleeca Camell)
-- Brand visual: "Fleeca Camell" no NUI. Persistencia/exports usam 'vhub_money'.

VHubMoneyCfg = {
  -- ─── Brand (so para o NUI) ──────────────────────────────────────────────
  BRAND_NAME   = 'Fleeca Camell',
  BRAND_TAG    = 'Banco Digital',
  BRAND_SLOGAN = 'Seu dinheiro, com a confianca do deserto.',

  -- ─── Saldos iniciais ────────────────────────────────────────────────────
  WALLET_INITIAL = 150,
  BANK_INITIAL   = 1000,

  -- ─── Comportamento ──────────────────────────────────────────────────────
  LOSE_WALLET_ON_DEATH = true,       -- perde dinheiro vivo ao morrer
  WALLET_DROP_KIND     = 'erase',    -- 'erase' (some) ou 'drop' (vira item — futuro)

  -- ─── Owner ──────────────────────────────────────────────────────────────
  -- char_id 1 = dono da cidade: bypass de qualquer limite e taxa.
  OWNER_CHAR_ID = 1,

  -- ─── ATM (caixa eletronico) ─────────────────────────────────────────────
  ATM = {
    INTERACT_RADIUS  = 1.8,           -- distancia para [E] aparecer
    BLIP_SHOW        = false,         -- ATMs em blip poluem o mapa (40+ pontos)
    BLIP_SPRITE      = 277,
    BLIP_COLOR       = 2,
    WITHDRAW_MAX     = 5000,          -- maximo por saque em ATM
    DEPOSIT_MAX      = 50000,         -- maximo por deposito em ATM
    COOLDOWN_SEC     = 30,            -- cooldown entre operacoes no ATM
    ANIM_DICT        = 'amb@prop_human_atm@male@idle_a',
    ANIM_NAME        = 'idle_a',
  },

  -- ─── Banco fisico (agencia) ─────────────────────────────────────────────
  BANK = {
    INTERACT_RADIUS  = 2.2,
    BLIP_SHOW        = true,
    BLIP_SPRITE      = 108,           -- icone de banco oficial GTA
    BLIP_COLOR       = 5,             -- amarelo
    BLIP_SCALE       = 0.85,
    -- Limites do balcao (ilimitado por padrao — agencia completa)
    WITHDRAW_MAX     = 0,             -- 0 = sem limite
    DEPOSIT_MAX      = 0,
    -- Restricao de horario opcional (estilo nav_bancos)
    HOURS_RESTRICT   = false,         -- true = so funciona em hora especifica
    HOURS_OPEN       = 7,
    HOURS_CLOSE      = 18,
  },

  -- ─── Transferencia P2P ──────────────────────────────────────────────────
  TRANSFER = {
    MIN_AMOUNT        = 1,
    MAX_AMOUNT        = 1000000,      -- 1M por op
    FEE_PERCENT       = 0.0,          -- 0 = sem taxa (alterar p/ % do valor)
    FEE_FIXED         = 0,            -- + valor fixo
    REQUIRE_TARGET_ONLINE = false,    -- false = aceita transferir pra offline
    -- Identificadores aceitos: char_id (direto), registration (Pix), phone (celular)
    BY_REGISTRATION   = true,
    BY_PHONE          = true,
  },

  -- ─── Auditoria ──────────────────────────────────────────────────────────
  AUDIT = {
    LIMIT_DEFAULT = 50,
    LIMIT_MAX     = 200,
    -- Loga todas as movimentacoes; false = so transferencias e admin
    LOG_ALL       = true,
  },

  -- ─── Persistencia ───────────────────────────────────────────────────────
  -- Save throttle: nao grava no SQL toda mudanca; agrupa por char a cada N segundos
  SAVE_INTERVAL_MS = 5000,
  -- Save forcado em playerDropped e onResourceStop
  SAVE_ON_DROP     = true,

  -- ─── ACE / permissoes admin ─────────────────────────────────────────────
  ADMIN_ACE        = 'vhub.money.admin',
  ADMIN_PERMISSION = 'vhub.money.admin',
  TRUSTED_RESOURCES = {
    ['vhub']        = true,
    ['vhub_admin']  = true,
    ['vhub_garage'] = true,
    ['vhub_racha']  = true,
  },

  -- ─── Comandos ───────────────────────────────────────────────────────────
  CMD_OPEN_PANEL    = 'banco',       -- /banco — abre Fleeca Camell (em banco/ATM)
  CMD_PAY           = 'pagar',       -- /pagar <id> <valor>
  CMD_GIVE          = 'dar',         -- /dar <id> <valor> — entrega carteira → carteira
  CMD_BALANCE       = 'saldo',       -- /saldo — toast com saldo atual
  KEY_OPEN_BLOCK    = 'F8',          -- nao tem hotkey global (precisa estar no banco/ATM)

  -- ─── HUD ────────────────────────────────────────────────────────────────
  HUD_FORMAT = 'R$ %s',              -- prefixo na formatacao
  HUD_SEPARATOR = '.',               -- separador de milhares
}

-- ─── Bancos fisicos (agencias) ──────────────────────────────────────────────
-- 7 bancos canonicos cruzados de nav_bancos + eag_banco
VHubMoneyBanks = {
  { id = 'fleeca_vespucci',   label = 'Fleeca Vespucci',       x = 149.85,   y = -1040.71, z = 29.37  },
  { id = 'fleeca_downtown',   label = 'Fleeca Downtown',       x = -1212.63, y = -330.80,  z = 37.78  },
  { id = 'fleeca_morningwood',label = 'Fleeca Morningwood',    x = -351.02,  y = -49.97,   z = 49.04  },
  { id = 'pacific_standard',  label = 'Pacific Standard',      x = 314.13,   y = -279.09,  z = 54.17  },
  { id = 'pacific_bluff',     label = 'Banco Pacific Bluff',   x = -2962.56, y = 482.95,   z = 15.70  },
  { id = 'paleto_bay',        label = 'Fleeca Paleto Bay',     x = -111.97,  y = 6469.19,  z = 31.62  },
  { id = 'sandy_shores',      label = 'Fleeca Sandy Shores',   x = 1175.05,  y = 2706.90,  z = 38.09  },
}

-- ─── ATMs (caixas eletronicos espalhados) ────────────────────────────────────
-- Lista cruzada de nav_bancos (90+) e eag_banco (44) — selecionados os mais
-- confiaveis (verificados in-game) e desduplicados (raio 5m).
VHubMoneyATMs = {
  { -31.49,  -1121.44, 26.55 },
  { -1314.76,-835.98,  16.96 },
  { -1315.72,-834.70,  16.96 },
  { 147.57,  -1035.77, 29.34 },
  { 145.96,  -1035.19, 29.34 },
  { 24.45,   -945.97,  29.35 },
  { 5.24,    -919.84,  29.55 },
  { 119.08,  -883.70,  31.12 },
  { 112.60,  -819.41,  31.33 },
  { 114.41,  -776.43,  31.41 },
  { 111.30,  -775.25,  31.43 },
  { 296.46,  -894.22,  29.23 },
  { 295.77,  -896.10,  29.22 },
  { -203.83, -861.38,  30.26 },
  { -301.70, -830.00,  32.41 },
  { -303.28, -829.72,  32.41 },
  { 289.08,  -1256.83, 29.44 },
  { 288.84,  -1282.33, 29.63 },
  { 33.16,   -1348.25, 29.49 },
  { -56.89,  -1752.10, 29.42 },
  { -721.04, -415.52,  34.98 },
  { 89.69,    2.47,    68.30 },
  { 527.35,  -160.72,  57.09 },
  { -846.29, -341.30,  38.68 },
  { -846.83, -340.21,  38.68 },
  { -1205.03,-326.27,  37.84 },
  { -1205.76,-324.80,  37.85 },
  { -1305.40,-706.38,  25.32 },
  { 158.63,   234.22, 106.62 },
  { 1153.77, -326.69,  69.20 },
  { 1167.00, -456.07,  66.79 },
  { 1138.23, -468.91,  66.73 },
  { 238.33,   215.97, 106.28 },
  { 237.90,   216.88, 106.28 },
  { 237.48,   217.78, 106.28 },
  { 237.05,   218.71, 106.28 },
  { 236.61,   219.66, 106.28 },
  { 285.43,   143.39, 104.17 },
  { 356.96,   173.55, 103.06 },
  { 380.75,   323.37, 103.56 },
  { 228.19,   338.37, 105.56 },
  { 1077.70, -776.54,  58.24 },
  { -165.14,  232.74,  94.92 },
  { -3040.78, 593.09,   7.90 },
  { -1827.29, 784.87, 138.30 },
  { 540.32,  2671.14,  42.15 },
  { -2072.36,-317.29,  13.31 },
  { 2683.11, 3286.56,  55.24 },
  { 1171.52, 2702.57,  38.17 },
  { -2956.88, 487.64,  15.46 },
  { -526.60,-1222.90,  18.45 },
  { -717.71, -915.70,  19.21 },
  { 1701.19, 6426.50,  32.76 },
  { -3241.15, 997.61,  12.55 },
  { 174.14,  6637.93,  31.57 },
  { -95.54,  6457.18,  31.46 },
  { 1968.09, 3743.53,  32.34 },
  { 2558.82,  351.01, 108.62 },
  { -386.72, 6046.08,  31.50 },
  { -132.93, 6366.53,  31.47 },
  { -1571.03, -547.37, 34.95 },
  { -712.89, -818.90,  23.72 },
  { -273.06,-2024.50,  30.14 },
  { -821.66,-1081.91,  11.13 },
  { 129.24, -1291.15,  29.26 },
  { -1391.03,-590.32,  30.31 },
  { 1686.84, 4815.79,  42.00 },
  { -258.84, -723.36,  33.47 },
  { 296.17,  -591.52,  43.27 },
  { 419.05,  -986.33,  29.38 },
  { -618.28, -708.93,  30.05 },
  { -614.59, -704.84,  31.23 },
  { -1109.81,-1690.73,  4.38 },
}
