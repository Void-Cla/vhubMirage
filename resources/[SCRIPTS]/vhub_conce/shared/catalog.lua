-- shared/catalog.lua — catálogo canônico de veículos (identidade + preço base)
-- vhub_conce é dono da identidade/preço do veículo (plano §1.2). O garage faz
-- cache read-only deste catálogo no boot (VHubGarage.catalog) só para exibição.
--   nome: rótulo PT-BR | preco: base concessionária | tipo: car/bike/...
--   categoria: subcategoria visual | stats: {vel,acel,freio,dir} 0-100 | tags: opcionais
--   p1: bloco do ENGINE DE SKILL (decisão #27) — identidade física do .meta selado.
--       Gerado por tools/handling-balancer (out/catalog-patch.json), mesclado À MÃO aqui.
--       Campos: tier_base/tier_max (obrigatórios p/ habilitar skill), base_alloc (distribuição
--       natural do tier; soma == BUDGET[tier_base]), archetype/grip_modifier/drive_bias/
--       susp_raise/mass/inertia_z/low_speed_loss (opcionais — afinidade; default seguro se ausentes),
--       seal (hash do .meta p/ auditoria). Carro SEM p1 = sem tier/skill (fail-closed, UI degrada).
--       BUDGET por tier: D=500 C=600 B=700 A=800 S=900 S+=1000.
---@diagnostic disable: undefined-global, lowercase-global

VHubConce         = VHubConce or {}
VHubConce.catalog = {
  -- ---------- CARROS ----------
  sultan    = { nome='Sultan',       preco=18000,   tipo='car',  categoria='sedan',     stats={vel=70,acel=72,freio=66,dir=74} },
  kuruma    = { nome='Kuruma',       preco=35000,   tipo='car',  categoria='sedan',     stats={vel=68,acel=70,freio=72,dir=70} },
  schafter2 = { nome='Schafter V12', preco=42000,   tipo='car',  categoria='sedan',     stats={vel=78,acel=74,freio=72,dir=78} },
  tailgater = { nome='Tailgater',    preco=28000,   tipo='car',  categoria='sedan',     stats={vel=72,acel=72,freio=68,dir=72} },
  oracle2   = { nome='Oracle XS',    preco=32000,   tipo='car',  categoria='sedan',     stats={vel=70,acel=68,freio=68,dir=72} },
  baller    = { nome='Baller',       preco=90000,   tipo='car',  categoria='suv',       stats={vel=72,acel=68,freio=64,dir=70} },
  cavalcade = { nome='Cavalcade',    preco=65000,   tipo='car',  categoria='suv',       stats={vel=70,acel=64,freio=64,dir=68} },
  granger   = { nome='Granger',      preco=35000,   tipo='car',  categoria='suv',       stats={vel=64,acel=62,freio=58,dir=66} },
  xls       = { nome='XLS',          preco=120000,  tipo='car',  categoria='suv',       stats={vel=76,acel=74,freio=70,dir=78} },
  adder     = { nome='Adder',        preco=1000000, tipo='car',  categoria='super',     stats={vel=98,acel=92,freio=88,dir=84}, tags={'premium'} },
  zentorno  = { nome='Zentorno',     preco=725000,  tipo='car',  categoria='super',     stats={vel=96,acel=90,freio=88,dir=90}, tags={'premium'} },
  t20       = { nome='Pegassi T20',  preco=2200000, tipo='car',  categoria='super',     stats={vel=99,acel=96,freio=90,dir=92}, tags={'premium','exclusivo'} },
  turismor  = { nome='Turismo R',    preco=500000,  tipo='car',  categoria='super',     stats={vel=92,acel=88,freio=86,dir=88} },
  entityxf  = { nome='Entity XF',    preco=795000,  tipo='car',  categoria='super',     stats={vel=94,acel=90,freio=86,dir=92} },
  TOYOTASUPRA = { nome='Toyota Supra A80', preco=420000, tipo='car', categoria='sport', stats={vel=90,acel=88,freio=78,dir=86}, tags={'mod'},
    p1 = { handling_name='toyotasupra', tier_base='S', tier_max='S+', base_alloc={potencia=180,grip=180,frenagem=180,aero=180,suspensao=180} } },
  SKYLINER34 = { nome='Nissan Skyline R34', preco=380000, tipo='car', categoria='sport', stats={vel=88,acel=86,freio=76,dir=84}, tags={'mod'},
    p1 = { handling_name='skyliner34', tier_base='S', tier_max='S+', base_alloc={potencia=180,grip=180,frenagem=180,aero=180,suspensao=180} } },
  NISSAN370Z = { nome='Nissan 370z', preco=380000, tipo='car', categoria='sport', stats={vel=88,acel=86,freio=76,dir=84}, tags={'mod'},
    p1 = { handling_name='nissan370z', tier_base='A', tier_max='S', base_alloc={potencia=160,grip=160,frenagem=160,aero=160,suspensao=160} } },
  f8t = { nome='Ferrari F8', preco=380000, tipo='car', categoria='sport', stats={vel=88,acel=86,freio=76,dir=84}, tags={'mod'},
    p1 = { handling_name='f8t', tier_base='S', tier_max='S+', archetype='rwd_heavy', grip_modifier=0.92,
           base_alloc={potencia=180,grip=180,frenagem=180,aero=180,suspensao=180},
           drive_bias=0.0, susp_raise=-0.015, mass=1600, inertia_z=1.6, low_speed_loss=1.0,
           seal='sha256:c65806cc6e8a382bd931fa29274e3265b0b078c02eb20c3594c4f53524fb30fa' } },
  FUSCA68 = { nome='Volkswagen Fusca 68', preco=380000, tipo='car', categoria='sport', stats={vel=88,acel=86,freio=76,dir=84}, tags={'mod'},
    p1 = { handling_name='fusca68', tier_base='C', tier_max='B', base_alloc={potencia=120,grip=120,frenagem=120,aero=120,suspensao=120} } },
  m3e46 = { nome='BMW M3 E46', preco=380000, tipo='car', categoria='sport', stats={vel=88,acel=86,freio=76,dir=84}, tags={'mod'},
    p1 = { handling_name='m3e46', tier_base='A', tier_max='S', base_alloc={potencia=160,grip=160,frenagem=160,aero=160,suspensao=160} } },

  -- ---------- MOTOS ----------
  bati801   = { nome='Bati 801',     preco=15000,  tipo='bike', categoria='esportiva',  stats={vel=84,acel=88,freio=64,dir=82} },
  akuma     = { nome='Akuma',        preco=9000,   tipo='bike', categoria='esportiva',  stats={vel=82,acel=86,freio=66,dir=80} },
  daemon    = { nome='Daemon',       preco=11000,  tipo='bike', categoria='chopper',    stats={vel=72,acel=70,freio=58,dir=70} },
  faggio2   = { nome='Faggio Sport', preco=4500,   tipo='bike', categoria='scooter',    stats={vel=44,acel=52,freio=58,dir=64} },
  double    = { nome='Double T',     preco=18000,  tipo='bike', categoria='esportiva',  stats={vel=88,acel=90,freio=66,dir=84} },
  hakuchou  = { nome='Hakuchou',     preco=22000,  tipo='bike', categoria='esportiva',  stats={vel=92,acel=92,freio=68,dir=86} },

  -- ---------- VANS / TRUCKS ----------
  burrito   = { nome='Burrito',      preco=22000,  tipo='truck', categoria='van',       stats={vel=58,acel=56,freio=58,dir=62} },
  speedo    = { nome='Speedo',       preco=18000,  tipo='truck', categoria='van',       stats={vel=56,acel=54,freio=58,dir=60} },
  youga     = { nome='Youga',        preco=16000,  tipo='truck', categoria='van',       stats={vel=54,acel=52,freio=58,dir=60} },
  pounder   = { nome='Pounder',      preco=90000,  tipo='truck', categoria='caminhao',  stats={vel=52,acel=48,freio=52,dir=58} },

  -- ---------- BARCOS ----------
  dinghy    = { nome='Dinghy',       preco=25000,  tipo='boat', categoria='lancha',     stats={vel=68,acel=66,freio=60,dir=72} },
  jetmax    = { nome='Jetmax',       preco=275000, tipo='boat', categoria='iate',       stats={vel=86,acel=78,freio=64,dir=82} },
  marquis   = { nome='Marquis',      preco=130000, tipo='boat', categoria='veleiro',    stats={vel=58,acel=56,freio=58,dir=66} },
  seashark  = { nome='Seashark',     preco=18000,  tipo='boat', categoria='jet',        stats={vel=78,acel=82,freio=70,dir=78} },

  -- ---------- AERONAVES ----------
  cuban800  = { nome='Cuban 800',    preco=180000,  tipo='plane', categoria='leve',     stats={vel=68,acel=64,freio=60,dir=70} },
  duster    = { nome='Duster',       preco=120000,  tipo='plane', categoria='leve',     stats={vel=62,acel=60,freio=60,dir=64} },
  vestra    = { nome='Vestra',       preco=950000,  tipo='plane', categoria='executiva',stats={vel=82,acel=80,freio=68,dir=80} },
  luxor     = { nome='Luxor',        preco=1625000, tipo='plane', categoria='jato',     stats={vel=90,acel=86,freio=72,dir=84}, tags={'premium'} },

  -- ---------- HELICOPTEROS ----------
  buzzard2  = { nome='Buzzard',      preco=900000,  tipo='heli', categoria='civil',     stats={vel=78,acel=76,freio=68,dir=80} },
  frogger   = { nome='Frogger',      preco=600000,  tipo='heli', categoria='civil',     stats={vel=72,acel=70,freio=66,dir=78} },
  swift     = { nome='Swift Deluxe', preco=1300000, tipo='heli', categoria='executivo', stats={vel=82,acel=80,freio=70,dir=82}, tags={'premium'} },
}
