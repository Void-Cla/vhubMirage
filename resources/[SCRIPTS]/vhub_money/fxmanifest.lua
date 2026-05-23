---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_money'
author      'vHub Mirage'
version     '2.0.0'
description 'Fleeca Camell — carteira, banco, ATMs, transferencias P2P e auditoria.'

dependencies {
  'oxmysql',
  'vhub',
}

shared_scripts {
  'shared/config.lua',
  'shared/helpers.lua',
}

server_scripts {
  'server/sql.lua',
  'server/core.lua',
  'server/transfer.lua',
  'server/atm.lua',
  'server/exports.lua',
  'server/init.lua',
}

client_scripts {
  'client/init.lua',
  'client/zones.lua',
  'client/nui.lua',
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
