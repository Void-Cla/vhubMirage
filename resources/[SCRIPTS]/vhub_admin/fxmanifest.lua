---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_admin'
author      'vHub Mirage'
version     '2.0.0'
description 'Painel admin completo: modera  o, teleporte, p layer ops, ve culos, mundo, spec, reports, jail/mute persistentes.'

dependencies {
  'vhub',
  'vhub_inventory',
  'vhub_money',
  'vhub_identity',
  'vhub_groups',
  'vhub_garage',
  'oxmysql',
}

shared_scripts {
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
}

ui_page 'nui/index.html'

files {
  'nui/index.html',
  'nui/css/style.css',
  'nui/js/app.js',
  'nui/js/players.js',
  'nui/js/actions.js',
  'nui/js/reports.js',
  'nui/js/logs.js',
  'nui/assets/bg.png',
}
