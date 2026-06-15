---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_spawselector'
author      'vHub Mirage'
version     '2.0.0'
description 'Provedor de coordenada de spawn do vhub_player_state (UI pura — nunca toca o ped)'

dependencies {
  'vhub',
  'vhub_groups',
  'vhub_player_state'
}

shared_scripts {
  'shared/config.lua'
}

server_scripts {
  'server/init.lua'
}

client_scripts {
  'client/main.lua'
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/css/style.css',
  'ui/js/script.js',
  'ui/images/lspd.png',
  'ui/images/mechanic.png',
  'ui/images/Motel.png',
  'ui/images/parking.png',
  'ui/images/pattern.png',
  'ui/images/sandy.png'
}
