---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_racha'
author      'vHub Mirage'
version     '1.0.0'
description 'Corridas ilegais server-authoritative com lobby, ranking, historico e premios auditaveis.'

dependencies {
  'vhub',
  'oxmysql',
  'vhub_money',
  'vhub_identity',
  'vhub_groups',
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/utils.lua',
}

server_scripts {
  'server/sql.lua',
  'server/core.lua',
  'server/init.lua',
  'server/exports.lua',
}

client_scripts {
  'client/init.lua',
  'client/zones.lua',
  'client/race.lua',
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
