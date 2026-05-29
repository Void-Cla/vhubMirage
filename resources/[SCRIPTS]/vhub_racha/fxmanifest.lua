---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_racha'
author      'vHub Mirage'
version     '3.1.0'
description 'Liga clandestina premium — 7 modos, ready-zone, totem cinematografico, editor visual, ranking persistido.'

dependencies {
  'oxmysql',
  'vhub',
  'vhub_money',
  'vhub_identity',
  'vhub_groups',
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',        -- registro unico de nomes de eventos (VHubRachaE)
  'shared/enums.lua',         -- enums de estado (InstState, Mode, Kind, EditorPhase, VClass)
  'shared/lang/pt_br.lua',
  'shared/math.lua',
  'shared/vehicle.lua',
  'shared/checkpoints.lua',
  'shared/utils.lua',
}

server_scripts {
  'server/bootstrap.lua',     -- PRIMEIRO: fila on_ready (handshake vhub core)
  'server/sessions.lua',      -- cache de usuarios via vHub:characterLoad (publico)
  'server/sql.lua',
  'server/state.lua',
  'server/grid.lua',          -- geometria de largada (ready-zone + slots) — antes do lobby
  'server/anti_cheat.lua',
  'server/history.lua',
  'server/ranking.lua',
  'server/rewards.lua',       -- interface com vhub_money (charge/refund/pay)
  'server/lobby.lua',         -- maquina de estados (depende de sessions + grid + rewards)
  'server/runtime.lua',       -- corrida ativa (racing → finished)
  'server/editor.lua',
  'server/exports.lua',
  'server/init.lua',          -- ULTIMO: wire de net events
}

client_scripts {
  'client/bootstrap.lua',
  'client/state.lua',
  'client/nui.lua',
  'client/lobby.lua',
  'client/race.lua',
  'client/nui_bridge.lua',
  'client/totem.lua',
  'client/countdown.lua',
  'client/sync.lua',
  'client/editor.lua',
  'client/modes/base.lua',
  'client/modes/sprint.lua',
  'client/modes/circuit.lua',
  'client/modes/drag.lua',
  'client/modes/drift.lua',
  'client/modes/speedtrap.lua',
  'client/modes/timeattack.lua',
  'client/modes/freerun.lua',
}

-- NUI componentizada (web/). Modulos: hud, panel, race. O totem 3D e nativo
-- (client/totem.lua), nao NUI. Legado nui/ removido — sem duplicacao.
ui_page 'web/index.html'

files {
  'sql/schema.sql',

  -- ============================================================
  -- NUI — engine + shared + modulos (web/)
  -- ============================================================

  -- Entry
  'web/index.html',

  -- Runtime (L3 — engine)
  'web/runtime/bus.js',
  'web/runtime/store.js',
  'web/runtime/bridge.js',
  'web/runtime/sand.js',
  'web/runtime/core.js',

  -- Shared (tokens + reset + components + utils)
  'web/shared/tokens.css',
  'web/shared/reset.css',
  'web/shared/components.css',
  'web/shared/utils.js',

  -- Modulo: HUD (L4 — overlay in-race)
  'web/modules/hud/hud.html',
  'web/modules/hud/hud.css',
  'web/modules/hud/hud.js',

  -- Modulo: PANEL (L4 — menu /racha: shell + 5 views + modal)
  'web/modules/panel/panel.html',
  'web/modules/panel/panel.css',
  'web/modules/panel/panel.js',

  -- Modulo: RACE (L4 — overlay da ready-zone; totem e 100% nativo em totem.lua)
  'web/modules/race/race.html',
  'web/modules/race/race.css',
  'web/modules/race/race.js',

  -- Assets locais (cópia — sem ownership cruzado com vhub_garage)
  'web/assets/bg.png',
  'web/assets/logo.png',
}
