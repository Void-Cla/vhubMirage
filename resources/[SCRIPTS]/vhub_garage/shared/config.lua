-- shared/config.lua  configura  o centralizada do vhub_garage
-- L da por server e client. Apenas dados; nada de l gica.

VHubGarage = VHubGarage or {}

VHubGarage.cfg = {
  -- ---------- Taxas e custos -----------------------------------------------
  taxa_force_out      = 50,      -- recolocar ve culo que est  "out" (perdeu, esqueceu)
  taxa_placa_custom   = 200,     -- ao comprar com placa personalizada
  fator_revenda_loja  = 0.60,    -- venda concession ria
  fator_test_drive    = 0.01,    -- 1% do pre o
  test_drive_segundos = 180,     -- 3 minutos
  test_drive_raio     = 300.0,   -- m
  fator_aluguel       = 0.10,    -- 10% do pre o por per odo
  aluguel_periodo_h   = 24,      -- dura  o padr o do aluguel em horas
  taxa_leilao         = 100,     -- fee de listagem (n o-reembols vel)
  leilao_duracao_min  = 60,      -- min utos padr o
  leilao_incremento   = 0.05,    -- min imo 5% acima do lance atual
  ipva_dias           = 15,      -- a cada 15 dias o IPVA vence
  ipva_porcentagem    = 0.01,    -- 1% do pre o do ve culo
  patio_taxa          = 500,     -- taxa base de libera  o
  patio_taxa_porcent  = 0.05,    -- + 5% do pre o do ve culo
  reparo_taxa_engine  = 0.0015,  -- 0,15% do pre o por ponto de dano (motor)
  reparo_taxa_body    = 0.0008,  -- 0,08% do pre o por ponto de dano (carro aria)
  clone_chave_taxa    = 800,     -- clonar chave (item extra no invent rio)
  emprestar_dias      = 7,       -- empr stimo expira em 7 dias por padr o
  max_veiculos_player = 25,      -- defesa contra alocador maligno

  -- ---------- Spawn / sa da -------------------------------------------------
  spawn_offset_carro = { x = 0.0, y = 5.0,  z = 0.5 },
  spawn_offset_moto  = { x = 0.0, y = 3.0,  z = 0.5 },
  spawn_offset_boat  = { x = 0.0, y = 8.0,  z = 0.0 },
  spawn_offset_plane = { x = 0.0, y = 25.0, z = 0.0 },
  spawn_offset_heli  = { x = 0.0, y = 0.0,  z = 0.0 },

  raio_guardar       = 18.0,     -- raio para guardar ve culo na garagem
  report_intervalo_s = 30,       -- cliente reporta posi  o/customiza  o a cada 30s

  -- ---------- Garagens (multi-tipo) ----------------------------------------
  -- Cada garagem suporta uma OU mais classes de ve culo: car / bike / boat / plane / heli / truck
  garagens = {
    {
      id      = 'ls_centro',
      label   = 'Garagem Los Santos',
      x = -341.99, y = -167.42, z = 38.73, h = 118.0, raio = 8.0,
      tipos   = { 'car', 'bike' },
      blip    = { sprite = 357, color = 5, scale = 0.75 },
    },
    {
      id      = 'sandy',
      label   = 'Garagem Sandy Shores',
      x = 1869.34, y = 3691.84, z = 33.58, h = 210.0, raio = 8.0,
      tipos   = { 'car', 'bike', 'truck' },
      blip    = { sprite = 357, color = 5, scale = 0.75 },
    },
    {
      id      = 'paleto',
      label   = 'Garagem Paleto Bay',
      x = -237.25, y = 6328.11, z = 32.64, h = 46.0, raio = 8.0,
      tipos   = { 'car', 'bike' },
      blip    = { sprite = 357, color = 5, scale = 0.75 },
    },
    {
      id      = 'aero_ls',
      label   = 'Hangar LS',
      x = -1102.95, y = -2895.49, z = 13.95, h = 240.0, raio = 12.0,
      tipos   = { 'plane', 'heli' },
      blip    = { sprite = 307, color = 3, scale = 0.85 },
    },
    {
      id      = 'sandy_aero',
      label   = 'Hangar Sandy',
      x = 1726.78, y = 3303.92, z = 41.22, h = 105.0, raio = 12.0,
      tipos   = { 'plane', 'heli' },
      blip    = { sprite = 307, color = 3, scale = 0.85 },
    },
    {
      id      = 'marina_ls',
      label   = 'Marina LS',
      x = -793.42, y = -1496.06, z = 1.60, h = 110.0, raio = 12.0,
      tipos   = { 'boat' },
      blip    = { sprite = 410, color = 3, scale = 0.85 },
    },
  },

  -- ---------- Concession rias ----------------------------------------------
  concessionarias = {
    {
      id      = 'pdm',
      label   = 'Premium Deluxe Motorsport',
      x = -56.84, y = -1097.41, z = 26.42, raio = 10.0,
      tipos   = { 'car', 'bike' },
      blip    = { sprite = 326, color = 3, scale = 0.85 },
      test_spawn = { x = -23.0, y = -1100.0, z = 26.42, h = 70.0 },
    },
    {
      id      = 'sandy_dealer',
      label   = 'Auto Sandy',
      x = 1226.92, y = 2729.18, z = 38.00, raio = 10.0,
      tipos   = { 'car', 'bike', 'truck' },
      blip    = { sprite = 326, color = 3, scale = 0.85 },
      test_spawn = { x = 1240.0, y = 2730.0, z = 38.00, h = 0.0 },
    },
    {
      id      = 'paleto_dealer',
      label   = 'Paleto Auto',
      x = 119.50, y = 6620.96, z = 31.78, raio = 10.0,
      tipos   = { 'car', 'bike' },
      blip    = { sprite = 326, color = 3, scale = 0.85 },
      test_spawn = { x = 110.0, y = 6622.0, z = 31.78, h = 270.0 },
    },
    {
      id      = 'aero_dealer',
      label   = 'Aero Vendas',
      x = -944.45, y = -2974.05, z = 13.95, raio = 10.0,
      tipos   = { 'plane', 'heli' },
      blip    = { sprite = 90, color = 3, scale = 0.85 },
      test_spawn = { x = -990.0, y = -2980.0, z = 13.95, h = 240.0 },
    },
    {
      id      = 'marina_dealer',
      label   = 'Marina Vendas',
      x = -802.24, y = -1496.79, z = 1.60, raio = 10.0,
      tipos   = { 'boat' },
      blip    = { sprite = 410, color = 3, scale = 0.85 },
      test_spawn = { x = -799.0, y = -1518.0, z = 0.00, h = 110.0 },
    },
  },

  -- ---------- Casa de leil es ---------------------------------------------
  leilao_local = {
    id    = 'auction_house',
    label = 'Casa de Leil es',
    x = -45.61, y = -1693.55, z = 29.62, raio = 6.0,
    blip = { sprite = 431, color = 46, scale = 0.85 },
  },

  -- ---------- P tio --------------------------------------------------------
  patio_local = {
    id    = 'patio_dpdp',
    label = 'P tio Municipal',
    x = 405.40, y = -1623.41, z = 29.29, raio = 8.0,
    blip = { sprite = 67, color = 1, scale = 0.85 },
  },

  -- ---------- Permiss es / grupos -----------------------------------------
  perms = {
    impound_admin = 'police.patio',   -- pode apreender ve culo
    auction_admin = 'admin.garage',   -- pode cancelar leil es
    stock_admin   = 'admin.garage',   -- pode mexer no estoque da concession ria
  },
}

-- helper exposto a outros m dulos: retorna config completa (read-only por conven  o)
function VHubGarage.getCfg() return VHubGarage.cfg end
