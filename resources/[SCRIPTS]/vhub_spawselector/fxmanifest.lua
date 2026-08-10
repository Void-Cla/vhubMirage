---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_spawselector'
author      'vHub Mirage'
version     '2.3.1'
description 'Provedor de coordenada de spawn do vhub_hss (UI pura — nunca toca o ped)'

dependencies {
  'vhub',
  'vhub_groups',
  'vhub_hss'
}

shared_scripts {
  '@vhub_hss/shared/events.lua',
  'shared/events.lua',
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
