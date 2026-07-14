-- shared/config.lua — configuração pública e sem segredos do vhub_admin

VHubAdmin = VHubAdmin or {}

VHubAdmin.cfg = {
  hotkey_open = 'F6',

  -- Chaves verificadas por uid=1, ACE `vhub.<chave>` e vhub_groups.
  perms = {
    panel       = 'vhub.admin.panel',
    kick        = 'player.kick',
    ban         = 'player.ban',
    unban       = 'player.unban',
    warn        = 'player.warn',
    jail        = 'admin.jail',
    mute        = 'admin.mute',
    tp          = 'player.tpto',
    bring       = 'player.tptome',
    tpgo        = 'player.tpcoords',
    tpcds       = 'player.tpcoords',
    tpall       = 'admin.tpall',
    heal        = 'player.heal',
    god         = 'admin.weapon.god',
    freeze      = 'player.freeze',
    revive      = 'player.revive',
    invisible   = 'admin.invisible',
    noclip      = 'player.noclip',
    spec        = 'admin.spectate',
    skin        = 'admin.skin',
    buff        = 'admin.buff',
    vehicle_spawn = 'admin.car.give',
    vehicle_delete = 'admin.car.dv',
    vehicle_fix = 'admin.car.fix',
    vehicle_boost = 'admin.car.fix',
    vehicle_view = 'admin.vehicle.view',
    vehicle_manage = 'admin.vehicle.manage',
    weather     = 'admin.world.weather',
    time        = 'admin.world.time',
    blackout    = 'admin.blackout',
    clearzone   = 'admin.clearzone',
    wipe        = 'admin.wipe',
    announce    = 'admin.announce',
    staffchat   = 'admin.staffchat',
    givemoney   = 'admin.money.give',
    setmoney    = 'admin.money.set',
    giveitem    = 'admin.item.give',
    addgroup    = 'admin.group.add',
    delgroup    = 'admin.group.remove',
    rg          = 'player.rg',
    reports     = 'admin.report.view',
    logs        = 'admin.logs',
  },

  -- Intervalos mínimos por origem, em milissegundos. Todo evento cliente usa um.
  rates = {
    default       = 500,
    panel         = 750,
    dashboard     = 1000,
    players       = 750,
    profile       = 1000,
    wall_toggle   = 750,
    wall_snapshot = 2000,
    reports       = 750,
    logs          = 1000,
    fleet          = 1000,
    fleet_detail   = 1000,
    report         = 60000,
    teleport       = 500,
    waypoint       = 1000,
    tpall          = 10000,
    world          = 1000,
    wipe           = 15000,
    moderation     = 750,
    economy        = 1000,
    vehicle        = 1000,
  },

  limits = {
    jail_min       = 5,
    jail_max       = 4320,
    mute_min       = 5,
    mute_max       = 1440,
    money_max      = 100000000,
    item_max       = 9999,
    announce_chars = 220,
    report_chars   = 500,
    report_cd_secs = 60,
    tp_history     = 20,
    fleet_page     = 100,
    fleet_max      = 500,
    players        = 256,
    logs           = 200,
    reports        = 200,
    wipe_cap       = 1000,
  },

  wall = {
    draw_distance   = 20.0,
    server_distance = 25.0,
    update_ms       = 100,  -- orcamento ativo: 10 Hz de SendNUIMessage.
    refresh_ms      = 2000, -- snapshot autoritativo: 0,5 Hz.
    max_players     = 64,
  },

  jail = {
    pos      = { x = 1681.05, y = 2516.59, z = 45.56, h = 270.0 },
    radius   = 30.0,
    check_ms = 2000, -- orçamento: O(jogadores presos), não O(players).
  },

  -- Coordenadas atravessam fronteiras como primitivos (L-19).
  teleport_zones = {
    hospital  = { label = 'Hospital Central', x = 308.19, y = -595.35, z = 43.29, h = 70.0 },
    garagem   = { label = 'Garagem Central', x = 215.12, y = -805.85, z = 30.81, h = 340.0 },
    aeroporto = { label = 'Aeroporto', x = -1037.74, y = -2737.77, z = 20.17, h = 330.0 },
    base      = { label = 'Base Administrativa', x = -75.23, y = -818.58, z = 326.18, h = 250.0 },
  },

  world = {
    weathers = {
      EXTRASUNNY = 'Ensolarado intenso', CLEAR = 'Limpo', CLOUDS = 'Nublado',
      OVERCAST = 'Encoberto', RAIN = 'Chuva', CLEARING = 'Abrindo',
      THUNDER = 'Tempestade', SMOG = 'Poluição', FOGGY = 'Neblina',
      XMAS = 'Natal', SNOWLIGHT = 'Neve leve', BLIZZARD = 'Nevasca',
    },
  },

  selectors = {
    money_routes = {
      { value = 'bank', label = 'Banco' },
      { value = 'wallet', label = 'Carteira' },
    },
    discipline_minutes = { 5, 10, 15, 30, 60, 120, 240, 480, 1440, 4320 },
    vehicle_statuses = {
      { value = 'garage', label = 'Garagem' },
      { value = 'out', label = 'Em uso' },
      { value = 'impound', label = 'Pátio' },
      { value = 'auction', label = 'Leilão' },
      { value = 'rental', label = 'Alugado' },
      { value = 'sold', label = 'Vendido' },
    },
  },
}

-- Retorna a configuração compartilhada e não sensível do resource.
function VHubAdmin.getCfg()
  return VHubAdmin.cfg
end
