---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_groups'
author      'vHub Mirage'
version     '2.0.0'
description 'Sistema de grupos, niveis hierarquicos e permissoes por personagem. VRAM-first com painel NUI.'

dependencies {
  'oxmysql',
  'vhub',
}

shared_scripts {
  'shared/config.lua',
  'shared/definitions.lua',
  'shared/permissions.lua',
}

server_scripts {
  'server/sql.lua',
  'server/cache.lua',
  'server/core.lua',
  'server/admin.lua',
  'server/exports.lua',
  'server/init.lua',
}

client_scripts {
  'client/init.lua',
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
