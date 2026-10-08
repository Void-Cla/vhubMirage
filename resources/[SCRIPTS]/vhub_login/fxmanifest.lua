fx_version 'cerulean'
game      'gta5'
lua54     'yes'
node_version '22'

name        'vhub_login'
author      'vHub Mirage'
version     '0.7.1'
description 'Gate de entrada Mirage: conta, seleção e handoff autoritativo ao criador.'

dependencies {
  'oxmysql',
  'vhub_crypto',
  'vhub',
  'vhub_hss',
  'vhub_identity',
  'vhub_sims',
  'vhub_spawselector',
  'depzitamadasptlnd',
}

shared_scripts {
  '@vhub_hss/shared/events.lua',
  '@vhub_sims/core/shared/events.lua',
  '@vhub_spawselector/shared/events.lua',
  'config/config.lua',
  'shared/events.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  '@vhub/shared/sql_script.lua',
  '@vhub_crypto/server/scrypt.js',
  '@vhub_crypto/server/scrypt.lua',
  'server/dominio/contas.lua',
  'server/dominio/fluxo.lua',
  'server/api/exports.lua',
  'server/init.lua',
}

client_scripts {
  'client/main.lua',
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/css/style.css',
  'ui/js/app.js',
}
