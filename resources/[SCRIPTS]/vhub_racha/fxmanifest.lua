---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_racha'
author      'vHub Mirage'
version     '3.0.0'
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
  'shared/enums.lua',
  'shared/lang/pt_br.lua',
  'shared/math.lua',
  'shared/vehicle.lua',
  'shared/checkpoints.lua',
  'shared/utils.lua',
}

server_scripts {
  'server/bootstrap.lua',
  'server/sql.lua',
  'server/state.lua',
  'server/anti_cheat.lua',
  'server/history.lua',
  'server/ranking.lua',
  'server/rewards.lua',
  'server/lobby.lua',
  'server/runtime.lua',
  'server/editor.lua',
  'server/exports.lua',
  'server/init.lua',
}

client_scripts {
  'client/bootstrap.lua',
  'client/state.lua',
  'client/nui.lua',
  'client/lobby.lua',
  'client/race.lua',
  'client/nui_bridge.lua',
  'client/totem.lua',
  'client/hud.lua',
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

ui_page 'nui/index.html'

files {
  'sql/schema.sql',
  'nui/index.html',
  'nui/css/style.css',
  'nui/js/app.js',
  'nui/js/sand.js',
  'nui/assets/bg.png',
  'nui/assets/logo.png',
}
