-- shared/config.lua  configura  o centralizada do vhub_garage
-- L da por server e client. Apenas dados; nada de l gica.
---@diagnostic disable: undefined-global, lowercase-global

VHubGarage = VHubGarage or {}

VHubGarage.cfg = {
  -- ---------- Taxas e custos -----------------------------------------------
  taxa_force_out      = 50,      -- recolocar ve culo que est  "out" (perdeu, esqueceu)
  taxa_placa_custom   = 2000,     -- ao comprar com placa personalizada
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
  patio_boot_scan     = true,      -- recolhe veiculos "out" orfaos no boot real (IT.3)
  patio_boot_destino  = 'impound', -- 'impound' (cobra taxa) | 'garage' (devolve gratis)
  reparo_taxa_engine  = 0.0015,  -- 0,15% do pre o por ponto de dano (motor)
  reparo_taxa_body    = 0.0008,  -- 0,08% do pre o por ponto de dano (carro aria)
  clone_chave_taxa    = 800,     -- clonar chave (item extra no invent rio)
  emprestar_dias      = 7,       -- empr stimo expira em 7 dias por padr o
  max_veiculos_player = 25,      -- defesa contra alocador maligno

  -- ---------- Spawn / sa da -------------------------------------------------
  -- L-19: offset relativo = vec3 (sem heading). Usado server-side (mesma context),
  -- nao cruza fronteira; somado a garagem.coord no spawn.
  spawn_offset_carro = vec3(0.0, 5.0,  0.5),
  spawn_offset_moto  = vec3(0.0, 3.0,  0.5),
  spawn_offset_boat  = vec3(0.0, 8.0,  0.0),
  spawn_offset_plane = vec3(0.0, 25.0, 0.0),
  spawn_offset_heli  = vec3(0.0, 0.0,  0.0),

  raio_guardar       = 5.0,     -- raio para guardar ve culo na garagem
  report_intervalo_s = 30,       -- cliente reporta posi  o/customiza  o a cada 30s

  -- ---------- Garagens (multi-tipo) ----------------------------------------
  -- Cada garagem suporta uma OU mais classes de ve culo: car / bike / boat / plane / heli / truck
  -- L-19: `coord` = vec3 (blip/zona/proximidade); `h` = heading de saida do veiculo
  -- (spawn = coord + spawn_offset, virado para `h`). Coord ACHATADA no SETUP.
  garagens = {
    {
      id      = 'ls_centro',
      label   = 'Garagem Los Santos',
      coord   = vec3(222.5119, -801.9008, 30.6713), h = 118.0, raio = 8.0,
      tipos   = { 'car', 'bike' },
      blip    = { sprite = 357, color = 5, scale = 0.75 },
    },
    {
      id      = 'sandy',
      label   = 'Garagem Sandy Shores',
      coord   = vec3(1869.34, 3691.84, 33.58), h = 210.0, raio = 8.0,
      tipos   = { 'car', 'bike', 'truck' },
      blip    = { sprite = 357, color = 5, scale = 0.75 },
    },
    {
      id      = 'paleto',
      label   = 'Garagem Paleto Bay',
      coord   = vec3(-237.25, 6328.11, 32.64), h = 46.0, raio = 8.0,
      tipos   = { 'car', 'bike' },
      blip    = { sprite = 357, color = 5, scale = 0.75 },
    },
    {
      id      = 'aero_ls',
      label   = 'Hangar LS',
      coord   = vec3(-1102.95, -2895.49, 13.95), h = 240.0, raio = 12.0,
      tipos   = { 'plane', 'heli' },
      blip    = { sprite = 307, color = 3, scale = 0.85 },
    },
    {
      id      = 'sandy_aero',
      label   = 'Hangar Sandy',
      coord   = vec3(1726.78, 3303.92, 41.22), h = 105.0, raio = 12.0,
      tipos   = { 'plane', 'heli' },
      blip    = { sprite = 307, color = 3, scale = 0.85 },
    },
    {
      id      = 'marina_ls',
      label   = 'Marina LS',
      coord   = vec3(-793.42, -1496.06, 1.60), h = 110.0, raio = 12.0,
      tipos   = { 'boat' },
      blip    = { sprite = 410, color = 3, scale = 0.85 },
    },
  },

  -- ---------- Concession rias / Casa de leil es (MOVIDAS) -----------------
  -- decisao #25: a config de localizacao da CONCESSIONARIA mudou para vhub_conce
  -- e a do LEILAO para vhub_ferinha (donos de negocio). O garage agrega ambas
  -- via PULL no boot (exports.vhub_conce:getZones / exports.vhub_ferinha:getZones)
  -- e renderiza a engine de presenca unica (client/zones.lua). Nao redeclarar aqui.

  -- ---------- P tio --------------------------------------------------------
  patio_local = {
    id    = 'patio_dpdp',
    label = 'P tio Municipal',
    coord = vec3(405.40, -1623.41, 29.29), raio = 8.0,
    blip  = { sprite = 67, color = 1, scale = 0.85 },
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
