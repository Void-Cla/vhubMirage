fx_version 'cerulean'
game      'gta5'
lua54     'yes'

name        'vhub_login'
author      'vHub Mirage'
version     '0.1.0'
description 'Gate de entrada: login de conta (username/senha) + seleção de personagem. Ponte para o futuro criador. NÃO faz loading nem criação de personagem.'

dependency  'vhub'

shared_script 'config/config.lua'

server_scripts {
  '@oxmysql/lib/MySQL.lua',
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
