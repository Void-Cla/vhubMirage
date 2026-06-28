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
  -- MOD SPLIT (cosmético × performance) — aplicado server-side
  -- bennys: rejeita indices PERFORMANCE; oficina: aceita APENAS PERFORMANCE
  -- ============================================================

  performance_mods = { [11]=true, [12]=true, [13]=true, [15]=true, [16]=true, [18]=true },

  -- índices cosméticos permitidos no bennys (complemento dos performance + toggles visuais)
  -- 0=spoiler 1=bumper_f 2=bumper_r 3=skirt 4=exhaust 5=rollcage 6=grille 7=hood
  -- 8=fender_l 9=fender_r 10=roof 20=smoke 22=xenon 23=wheels_r 24=wheels_b 25..49=visual
  cosmetic_mods = {
    [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,
    [8]=true,[9]=true,[10]=true,[20]=true,[22]=true,[23]=true,[24]=true,
    [25]=true,[26]=true,[27]=true,[28]=true,[29]=true,[30]=true,[31]=true,
    [32]=true,[33]=true,[34]=true,[35]=true,[36]=true,[37]=true,[38]=true,
    [39]=true,[40]=true,[41]=true,[42]=true,[43]=true,[44]=true,[45]=true,
    [46]=true,[47]=true,[48]=true,[49]=true,
  },


  -- ============================================================
  -- RATE LIMITING (max disparos por janela em ms)
  -- ============================================================

  rates = {
    bennys_apply  = { max = 5,  window = 30000 },   -- 5 aplicações/30s
    mec_repair    = { max = 3,  window = 60000 },   -- 3 reparos/60s
    mec_tow       = { max = 2,  window = 120000 },  -- 2 reboques/120s
    oficina_tune  = { max = 5,  window = 60000 },   -- 5 tunings/60s
  },


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
  },


  -- ============================================================
  -- CAP DE STAGE POR CLASSE GTA (sem carskill F2)
  -- Enquanto vhub_p1skill não existir, usa este cap conservador.
  -- Mapeado pela classe nativa (GetVehicleClass): 0=compacto..7=SUV..8=coupe..
  -- 9=muscle..10=sport classic..11=sport..12=super
  -- ============================================================

  stage_cap_by_class = {
    [0]  = 1,   -- compacto
    [1]  = 1,   -- sedan
    [2]  = 1,   -- SUV
    [3]  = 2,   -- coupe
    [4]  = 2,   -- muscle
    [5]  = 1,   -- esporte clássico
    [6]  = 2,   -- esporte
    [7]  = 3,   -- super
    [8]  = 1,   -- motocicleta
    [9]  = 1,   -- off-road
    [10] = 1,   -- utilitário
    [11] = 0,   -- van (sem tuning)
    [12] = 0,   -- bicicleta
    [13] = 0,   -- barco
    [14] = 0,   -- helicóptero
    [15] = 0,   -- avião
    [16] = 2,   -- serviço
    [17] = 0,   -- emergência
    [18] = 0,   -- militar
    [19] = 1,   -- comercial
    [20] = 0,   -- trem
  },

  -- fallback quando a classe não está no mapa
  stage_cap_default = 1,


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
