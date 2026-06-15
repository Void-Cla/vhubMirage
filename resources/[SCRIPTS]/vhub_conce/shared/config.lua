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
  -- CONCESSIONÁRIA (transação — FASE 2). Zonas/locais ficam no garage.
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
}
