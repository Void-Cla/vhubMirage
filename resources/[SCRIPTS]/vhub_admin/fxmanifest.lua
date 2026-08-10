---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_admin'
author      'vHub Mirage'
version     '3.1.0'
description 'Painel admin completo: moderação, teleporte, player ops, veículos, mundo, economia, spec, reports, jail/mute persistentes.'

dependencies {
  'vhub',
  'vhub_hss',
  'vhub_inventory',
  'vhub_money',
  'vhub_identity',
  'vhub_groups',
  'vhub_garage',
  'oxmysql',
}

shared_scripts {
  '@vhub_hss/shared/events.lua',
  'shared/config.lua',
  'shared/events.lua',
  'shared/utils.lua',
  'shared/actions.lua',
}

server_scripts {
  'server/sql.lua',
  'server/core.lua',
  'server/init.lua',
  'server/moderation.lua',
  'server/teleport.lua',
  'server/player.lua',
  'server/vehicle.lua',
  'server/world.lua',
  'server/spectator.lua',
  'server/reports.lua',
  'server/info.lua',
  'server/exports.lua',
}

client_scripts {
  'client/init.lua',
  'client/noclip.lua',
  'client/teleport.lua',
  'client/player.lua',
  'client/vehicle.lua',
  'client/world.lua',
  'client/spectator.lua',
  'client/jail.lua',
  'client/commands.lua',
  'client/ui.lua',
  'client/overlay.lua',
}

ui_page 'nui/index.html'

files {
  'nui/index.html',
  'nui/css/style.css',
  'nui/js/app.js',
  'nui/js/dashboard.js',
  'nui/js/players.js',
  'nui/js/actions.js',
  'nui/js/reports.js',
  'nui/js/logs.js',
  'nui/js/fleet.js',
  'nui/js/overlay.js',
  'nui/assets/logo.png',
}
