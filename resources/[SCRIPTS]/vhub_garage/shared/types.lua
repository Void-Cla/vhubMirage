-- shared/types.lua  metadados de TIPO de veiculo (spawn surface, markers, lista)
-- O CATALOGO (nome/preco/stats) migrou para vhub_conce na FASE 2. O garage faz
-- cache read-only dele em VHubGarage.catalog no boot (server/init.lua), entao
-- todos os read-sites de VHubGarage.catalog seguem funcionando sem mudanca.
-- Tipos: 'car', 'bike', 'plane', 'heli', 'boat', 'truck', 'trailer'

VHubGarage          = VHubGarage or {}
VHubGarage.types    = VHubGarage.types or {}
VHubGarage.catalog  = VHubGarage.catalog or {}   -- cache: preenchido no boot via vhub_conce

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
