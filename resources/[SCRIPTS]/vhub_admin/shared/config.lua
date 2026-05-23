-- shared/config.lua  configura  o do vhub_admin
VHubAdmin = VHubAdmin or {}

VHubAdmin.cfg = {
  -- ---------- Hotkey -------------------------------------------------------
  hotkey_open = 'F6',     -- abre o painel (RegisterKeyMapping)

  -- ---------- Permiss es (chaves usadas no vhub_groups OU ACE vhub.*) -----
  perms = {
    panel       = 'admin.panel',
    -- moderation
    kick        = 'admin.kick',
    ban         = 'admin.ban',
    unban       = 'admin.unban',
    whitelist   = 'admin.whitelist',
    warn        = 'admin.warn',
    jail        = 'admin.jail',
    mute        = 'admin.mute',
    -- teleport
    tp          = 'admin.tp',
    bring       = 'admin.bring',
    tpgo        = 'admin.tpgo',
    tpcds       = 'admin.tpcds',
    tpall       = 'admin.tpall',
    -- player
    heal        = 'admin.heal',
    god         = 'admin.god',
    freeze      = 'admin.freeze',
    revive      = 'admin.revive',
    invisible   = 'admin.invisible',
    skin        = 'admin.skin',
    spec        = 'admin.spec',
    -- vehicle
    spawncar    = 'admin.spawncar',
    delveh      = 'admin.delveh',
    fix         = 'admin.fix',
    tuning      = 'admin.tuning',
    carcolor    = 'admin.carcolor',
    -- world
    weather     = 'admin.weather',
    time        = 'admin.time',
    blackout    = 'admin.blackout',
    clearzone   = 'admin.clearzone',
    announce    = 'admin.announce',
    staffchat   = 'admin.staffchat',
    -- money/inventory (delegam a outros resources)
    givemoney   = 'admin.givemoney',
    setmoney    = 'admin.setmoney',
    giveitem    = 'admin.giveitem',
    clearinv    = 'admin.clearinv',
    -- groups
    addgroup    = 'admin.group.add',
    delgroup    = 'admin.group.remove',
    -- info
    rg          = 'admin.rg',
    coords      = 'admin.coords',
    pon         = 'admin.pon',
    -- reports
    reports     = 'admin.reports',
    -- owner-only
    setvip      = 'owner.setvip',
    rename      = 'owner.rename',
    delchar     = 'owner.delchar',
  },

  -- ---------- Tetos / limites (defesa em profundidade) --------------------
  limits = {
    jail_min       = 5,         -- jail m nimo em minutos
    jail_max       = 4320,      -- m ximo 72 h em minutos
    mute_min       = 5,
    mute_max       = 1440,
    money_max      = 100000000, -- 100 M
    item_max       = 9999,
    spawn_models   = 200,       -- spawncar  s  carros listados como v lidos
    announce_chars = 220,
    report_chars   = 500,
    report_cd_secs = 60,        -- cooldown entre reports do mesmo jogador
    tp_history     = 20,        -- profundidade do hist rico
  },

  -- ---------- Coords do "jail" -------------------------------------------
  jail_pos = { x = 1681.05, y = 2516.59, z = 45.56, h = 270.0 },

  -- ---------- Webhook Discord (opcional) ---------------------------------
  webhook = {
    enabled = false,
    url     = '',
  },

  -- ---------- Pol tica de noclip ----------------------------------------
  noclip = {
    speed_slow = 5.0,
    speed_norm = 18.0,
    speed_fast = 54.0,
  },

  -- ---------- Tetos de listagem (anti-DoS NUI) --------------------------
  list_caps = {
    players  = 256,
    logs     = 200,
    reports  = 200,
  },
}

function VHubAdmin.getCfg() return VHubAdmin.cfg end
