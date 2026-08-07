-- shared/config.lua — configuração estática do vhub_custom (zonas, preços, rates, splits)
---@diagnostic disable: undefined-global, lowercase-global

VHubCustom     = VHubCustom or {}
VHubCustom.cfg = {

  -- ============================================================
  -- DEBUG — notificações de diagnóstico no caminho de tuning/estética
  -- DESLIGAR (false) após validar em jogo. Mostra cada etapa server-side.
  -- ============================================================

  debug = false,


  -- ============================================================
  -- PALETAS DE TINTA (índices GTA 0-222 por tipo de acabamento)
  -- metalico / fosco / cromado / metal — aplicados via campo colours
  -- ============================================================

  paint_palettes = {
    metalico = {
      0,147,1,11,2,3,4,5,6,7,8,9,10,27,28,29,150,30,31,32,33,34,143,35,135,
      137,136,36,38,138,90,88,89,91,49,50,51,52,53,54,92,141,61,62,63,64,65,
      66,67,68,69,73,70,74,96,101,95,94,97,103,104,98,100,102,105,106,71,72,
      142,145,107,111,112,
    },
    fosco  = { 12,13,14,131,83,82,84,149,148,39,40,41,42,55,128,151,155,152,153,154 },
    cromado= { 120 },
    metal  = { 117,118,119,158,159 },
  },


  -- ============================================================
  -- EXTRAS DO MODELO (acessórios do mod/carro — toggle visibilidade)
  -- ============================================================

  extras_max = 14,   -- índices 0..13


  -- ============================================================
  -- BLINDAGEM DE VIDRO (RP — sem uso de mod slot 16/performance)
  -- ============================================================

  glass_armor_tiers = {
    { id=0, label='Nenhuma',          price=0    },
    { id=1, label='Leve',             price=1500 },
    { id=2, label='Forte',            price=4000 },
    { id=3, label='Ultra Resistente', price=8000 },
  },


  -- ============================================================
  -- STANCE (rebaixamento visual REAL, per-entidade — NÃO model-wide)
  -- Aplicado por client/stance.lua via natives per-entidade (SetVehicleSuspensionHeight,
  -- SetVehicleWheelSize/Width, SetVehicleWheelXOffset) e sincronizado a TODOS por State Bag
  -- (server/visual.lua). Persiste na placa em customization.stance = { r, tf, tr, sz, wd }.
  -- Cada eixo é um NOTCH inteiro [min,max]; o delta físico = notch * unit (metros). A base
  -- STOCK vem do MODELO (veículo temporário), não da entidade — evita empilhar deltas.
  -- ARRAY ORDENADO: o servidor itera p/ validar; a NUI renderiza na mesma ordem.
  -- Para inverter a direção da altura, troque o sinal de `unit` do eixo 'r'.
  -- ============================================================

  stance = {
    -- unit em metros por notch. Bounds CONSERVADORES: evitar clip carroceria/chão e roda absurda.
    -- (−) abaixa · (+) levanta. Hard-caps adicionais em client/stance.lua (RIDE_MIN/MAX etc.)
    { key='r',  label='Altura',            min=-6, max=4, unit=0.010 },  -- max lowering ≈6cm
    { key='tf', label='Bitola dianteira',  min=0,  max=8, unit=0.006 },  -- max spread ≈5cm p/ fora
    { key='tr', label='Bitola traseira',   min=0,  max=8, unit=0.006 },  -- max spread ≈5cm p/ fora
    { key='sz', label='Tamanho da roda',   min=0,  max=6, unit=0.022 },  -- exige roda custom; max +13cm
    { key='wd', label='Largura da roda',   min=0,  max=6, unit=0.022 },  -- exige roda custom; max +13cm
  },


  -- ============================================================
  -- KNOBS DE HANDLING LIVRE (oficina) — valor NORMALIZADO 0..1 por knob
  -- As CHAVES abaixo DEVEM espelhar vhub_vehcontrol/shared/config.lua::Config.skillHandlingExt
  -- (menos 'stance', que vem do bennys). A FÍSICA (bandas) mora no motor; aqui só rótulo+chave.
  -- ============================================================

  handling_knobs = {
    { key = 'handbrake',  label = 'Freio de mão',        hint = 'Força do freio de mão (drift)' },
    { key = 'steering',   label = 'Trava de direção',    hint = 'Ângulo máximo de esterço' },
    { key = 'low_speed',  label = 'Tração na largada',   hint = 'Perda de tração em baixa velocidade' },
    { key = 'susp_force', label = 'Rigidez da suspensão', hint = 'Firmeza da suspensão' },
  },


  -- ============================================================
  -- MOD SPLIT (cosmético × performance) — aplicado server-side
  -- bennys: rejeita indices PERFORMANCE; oficina: aceita APENAS PERFORMANCE
  -- ============================================================

  performance_mods = { [11]=true, [12]=true, [13]=true, [15]=true, [16]=true, [18]=true },

  -- índices cosméticos permitidos no bennys (complemento dos performance + toggles visuais)
  -- 0=spoiler 1=bumper_f 2=bumper_r 3=skirt 4=exhaust 5=rollcage 6=grille 7=hood
  -- 8=fender_l 9=fender_r 10=roof 14=horn 20=smoke 22=xenon 23=wheels_r 24=wheels_b
  -- 25..49=visual. 17/18/19/21 ficam fora: nitro/turbo/subwoofer/hidráulica são toggles.
  cosmetic_mods = {
    [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,
    [8]=true,[9]=true,[10]=true,[14]=true,[20]=true,[22]=true,[23]=true,[24]=true,
    [25]=true,[26]=true,[27]=true,[28]=true,[29]=true,[30]=true,[31]=true,
    [32]=true,[33]=true,[34]=true,[35]=true,[36]=true,[37]=true,[38]=true,
    [39]=true,[40]=true,[41]=true,[42]=true,[43]=true,[44]=true,[45]=true,
    [46]=true,[47]=true,[48]=true,[49]=true,
  },


  -- ============================================================
  -- RATE LIMITING (max disparos por janela em ms)
  -- ============================================================

  rates = {
    service_auth    = { max = 8,  window = 10000 },
    request_visual  = { max = 20, window = 10000 },  -- reidratação de bag (entrar/spawn) — anti-amplificação
    bennys_apply    = { max = 5,  window = 30000 },
    mec_repair      = { max = 3,  window = 60000 },
    mec_tow         = { max = 2,  window = 120000 },
    oficina_tune    = { max = 5,  window = 60000 },
    oficina_preview = { max = 30, window = 10000 },
    oficina_recal   = { max = 3,  window = 60000 },
    oficina_nitro   = { max = 2,  window = 60000 },
    drift_install   = { max = 2,  window = 120000 },
    drift_remove    = { max = 2,  window = 120000 },
  },

  service_lease_ms       = 600000,
  max_player_zone_dist   = 5.5,
  max_vehicle_zone_dist  = 10.0,
  max_player_vehicle_dist= 10.0,
  max_service_speed      = 1.5,


  -- ============================================================
  -- PREÇOS SERVIDOR (nunca vêm do cliente)
  -- ============================================================

  prices = {
    -- bennys — por tipo de mod
    cor_primaria   = 500,
    cor_secundaria = 500,
    cor_perolado   = 800,
    cor_roda       = 400,
    cor_custom     = 1500,  -- pintura RGB exata (custom paint) — primária OU secundária
    interior_color = 500,   -- cor do interior (índice GTA)
    dashboard_color= 500,   -- cor do painel (índice GTA)
    neon           = 1200,
    neon_cor       = 600,   -- troca de cor do neon (sem reinstalar o kit)
    fumaca         = 800,
    fumaca_cor     = 500,   -- cor RGB da fumaça de pneu
    xenon          = 1500,
    tint           = 300,
    livery         = 2000,
    plate_index    = 200,
    wheel_type     = 600,
    mod_cosmetic   = 400,   -- mods cosméticos de lataria (spoiler, para-choque, etc.)
    paint_palette  = 600,   -- tinta por índice de paleta (metálico/fosco/cromado/metal)
    pearlescent_idx= 800,   -- cor perolada por índice (0-161)
    wheel_color_idx= 400,   -- cor de aro por índice (0-161)
    extras_toggle  = 300,   -- acessório extra por unidade toggled
    exhaust_fx     = 800,   -- fogo no escapamento (instalar/atualizar kit)
    stance         = 800,   -- rebaixamento visual (altura/bitola/roda) — cobrado ao ajustar
    glass_armor    = { [0]=0, [1]=1500, [2]=4000, [3]=8000 },

    -- mec — reparo parcial por componente
    pneu           = 300,
    motor_parcial  = 800,   -- por 100pts de dano
    lataria_parcial= 500,   -- por 100pts de dano

    -- oficina — por stage e tipo
    engine_stage   = { [1]=3000,  [2]=8000,  [3]=18000 },
    brakes_stage   = { [1]=2000,  [2]=5000,  [3]=12000 },
    transmission_stage = { [1]=2500, [2]=6000, [3]=14000 },
    suspension_stage   = { [1]=1800, [2]=4500, [3]=10000 },
    armor_stage    = { [1]=1500,  [2]=4000,  [3]=9000  },
    turbo          = 12000,
    recalibration  = 2500,
    nitro_kit      = 5000,
    handling_tune  = 3000,   -- ajuste dos knobs de handling livre (freio/direção/largada/rigidez)
    drift_install  = 4500,   -- instalação do Freio de Mão Hidráulico (mão de obra) — item p/ inventário
    drift_remove   = 500,    -- remoção (devolve peça ao inventário)
  },


  -- fallback conservador para categoria terrestre desconhecida
  stage_cap_default = 1,

  -- cap autoritativo: derivado de dados persistidos, nunca da classe enviada pelo cliente
  stage_cap_by_type = { car = 3, bike = 1, truck = 1 },
  stage_cap_by_category = {
    sedan = 1, suv = 1, super = 3, sport = 2,
    esportiva = 1, chopper = 1, scooter = 1,
    van = 0, caminhao = 0,
  },
  stage_cap_by_tier = { ['D']=1, ['C']=1, ['B']=2, ['A']=2, ['S']=3, ['S+']=3 },


  -- ============================================================
  -- ZONAS (coord flat L-19 — vec3 pré-calculado client-side no boot)
  -- raio_check: distância de detecção (thread fria, 1 Hz)
  -- raio_interact: distância de interação (thread quente, marker + [E])
  -- ============================================================

  zones = {
    {
      id     = 'bennys_ls',
      label  = 'Bennys — Los Santos',
      domain = 'bennys',
      x = -211.4, y = -1323.7, z = 30.3,
      raio_check    = 40.0,
      raio_interact = 3.5,
      blip = { sprite = 72, color = 5, label = 'Bennys' },
      
    },
    {
      id     = 'mec_ls',
      label  = 'Mecânica — LS',
      domain = 'mec',
      x = 136.0, y = -1082.0, z = 29.1,
      raio_check    = 40.0,
      raio_interact = 3.5,
      blip = { sprite = 446, color = 2, label = 'Mecânica' },
      tow_drop = { x = 142.0, y = -1081.0, z = 29.2, h = 0.0 },
    },
    {
      id     = 'oficina_ls',
      label  = 'Oficina de Tuning — LS',
      domain = 'oficina',
      x = -360.0, y = -135.0, z = 38.5,
      raio_check    = 40.0,
      raio_interact = 3.5,
      blip = { sprite = 566, color = 46, label = 'Oficina' },
    },
  },

}
