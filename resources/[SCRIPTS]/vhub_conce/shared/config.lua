-- shared/config.lua — namespace + configuração estática do vhub_conce
---@diagnostic disable: undefined-global, lowercase-global

-- Namespace único do resource (lido por todos os módulos server/shared).
-- Config nasce junto com o consumidor de cada fase (cron na FASE 3).
VHubConce     = VHubConce or {}
VHubConce.cfg = {

  -- Vocabulário de tipos de chave (espelha o ENUM de vhub_vehicle_keys.kind).
  -- 'owner' = chave-mãe imutável do dono; clone/shared/rental = posse temporária.
  key_kinds = { owner = true, clone = true, shared = true, rental = true },

  -- ============================================================
  -- CONCESSIONÁRIA (transação — FASE 2). Zona/local pertence ao conce (decisão #25).
  -- ============================================================
  max_veiculos_player = 25,      -- defesa contra alocador maligno
  ipva_dias           = 7,      -- a cada 15 dias o IPVA vence
  taxa_placa_custom   = 10000,    -- ao comprar com placa personalizada
  fator_revenda_loja  = 0.60,    -- valor de venda de volta à loja
  fator_test_drive    = 0.00,    -- custo do test drive = 0% do preço
  test_drive_segundos = 9999,     -- duração do test drive
  test_drive_raio     = 900.0,   -- raio máximo do test drive (m)

  -- ============================================================
  -- CRON 24h — devolução de posse temporária (FASE 3)
  -- ============================================================
  cron_interval_ms = 3600 * 1000,   -- varredura horária
  temp_hold_ttl_s  = 24 * 3600,     -- chave sem 'expires' explícito devolve em 24h

  -- ============================================================
  -- ZONAS DA CONCESSIONÁRIA (decisão #25 — dono da config de localização)
  -- L-19: `coord` = vec3 (blip/zona); `test_spawn` = vec4 (x,y,z,w=heading).
  -- O garage faz PULL no boot (exports.vhub_conce:getZones) e renderiza a engine
  -- de presença única; vec NÃO cruza fronteira → getZones devolve flat {x,y,z[,h]}.
  -- ============================================================
  concessionarias = {
    {
      id    = 'pdm',
      label = 'Premium Deluxe Motorsport',
      coord = vec3(-56.84, -1097.41, 26.42), raio = 10.0,
      tipos = { 'car', 'bike' },
      blip  = { sprite = 326, color = 3, scale = 0.85 },
      test_spawn = vec4(-23.0, -1100.0, 26.42, 70.0),
    },
    {
      id    = 'sandy_dealer',
      label = 'Auto Sandy',
      coord = vec3(1226.92, 2729.18, 38.00), raio = 10.0,
      tipos = { 'car', 'bike', 'truck' },
      blip  = { sprite = 326, color = 3, scale = 0.85 },
      test_spawn = vec4(1240.0, 2730.0, 38.00, 0.0),
    },
    {
      id    = 'paleto_dealer',
      label = 'Paleto Auto',
      coord = vec3(119.50, 6620.96, 31.78), raio = 10.0,
      tipos = { 'car', 'bike' },
      blip  = { sprite = 326, color = 3, scale = 0.85 },
      test_spawn = vec4(110.0, 6622.0, 31.78, 270.0),
    },
    {
      id    = 'aero_dealer',
      label = 'Aero Vendas',
      coord = vec3(-944.45, -2974.05, 13.95), raio = 10.0,
      tipos = { 'plane', 'heli' },
      blip  = { sprite = 90, color = 3, scale = 0.85 },
      test_spawn = vec4(-990.0, -2980.0, 13.95, 240.0),
    },
    {
      id    = 'marina_dealer',
      label = 'Marina Vendas',
      coord = vec3(-802.24, -1496.79, 1.60), raio = 10.0,
      tipos = { 'boat' },
      blip  = { sprite = 410, color = 3, scale = 0.85 },
      test_spawn = vec4(-799.0, -1518.0, 0.00, 110.0),
    },
  },
}
