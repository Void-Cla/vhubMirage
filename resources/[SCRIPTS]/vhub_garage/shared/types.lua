-- shared/types.lua  cat logo de ve culos + categoriza  o + stats
-- Tipos: 'car', 'bike', 'plane', 'heli', 'boat', 'truck', 'trailer'
-- Cada modelo decide:
--   nome: r tulo PT-BR exibido
--   preco: base (concession ria)
--   tipo: 'car' | 'bike' | ...
--   categoria: subcategoria visual (sedan / esportivo / SUV / ...)
--   stats: { vel, acel, freio, dir } 0-100 (para barras na NUI)
--   tags: { 'novo', 'premium', 'esportivo' } opcionais

VHubGarage          = VHubGarage or {}
VHubGarage.types    = VHubGarage.types or {}
VHubGarage.catalog  = VHubGarage.catalog or {}

VHubGarage.types.list = { 'car', 'bike', 'plane', 'heli', 'boat', 'truck', 'trailer' }

-- markers no NUI por tipo
VHubGarage.types.markers = {
  car     = 36,
  bike    = 37,
  truck   = 39,
  plane   = 33,
  heli    = 34,
  boat    = 35,
  trailer = 39,
}

-- spawn surface por tipo
VHubGarage.types.surface = {
  car     = 'ground',
  bike    = 'ground',
  truck   = 'ground',
  trailer = 'ground',
  plane   = 'runway',
  heli    = 'pad',
  boat    = 'water',
}

-- ------ Cat logo padr o ------------------------------------------------------
VHubGarage.catalog = {
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
  pounder   = { nome='Pounder',      preco=90000,  tipo='truck', categoria='caminh o',  stats={vel=52,acel=48,freio=52,dir=58} },

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

  -- ---------- HELIC PTEROS ----------
  buzzard2  = { nome='Buzzard',      preco=900000,  tipo='heli', categoria='civil',     stats={vel=78,acel=76,freio=68,dir=80} },
  frogger   = { nome='Frogger',      preco=600000,  tipo='heli', categoria='civil',     stats={vel=72,acel=70,freio=66,dir=78} },
  swift     = { nome='Swift Deluxe', preco=1300000, tipo='heli', categoria='executivo', stats={vel=82,acel=80,freio=70,dir=82}, tags={'premium'} },
}

-- ------ helpers --------------------------------------------------------------

-- retorna entrada do cat logo (ou nil)
function VHubGarage.getModel(model)
  return VHubGarage.catalog[model]
end

-- retorna tipo do ve culo (default car)
function VHubGarage.getType(model)
  local e = VHubGarage.catalog[model]
  return e and e.tipo or 'car'
end

-- categorias dispon veis (para filtro NUI)
function VHubGarage.getCategorias(tipo)
  local set, out = {}, {}
  for _, e in pairs(VHubGarage.catalog) do
    if (not tipo) or e.tipo == tipo then
      if not set[e.categoria] then set[e.categoria] = true; out[#out+1] = e.categoria end
    end
  end
  table.sort(out)
  return out
end

-- list completa de modelos por tipo (para filtros)
function VHubGarage.getModelsByType(tipo)
  local out = {}
  for k, e in pairs(VHubGarage.catalog) do
    if e.tipo == tipo then out[#out+1] = k end
  end
  table.sort(out)
  return out
end
