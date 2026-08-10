fx_version 'cerulean'
game 'gta5'

author 'vHub Mirage'
description 'Outdoors administrativos com imagem ou video remoto'
version '3.1.0'

lua54 'yes'

dependencies {
  'oxmysql',
  'vhub',
  'vhub_groups',
  'vhub_notify',
  'vhub_wow',
  'vhub_inventory',
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/media.lua',
}

client_scripts {
  'client/props.lua',
  'client/remote.lua',
  'client/placement.lua',
  'client/renderer.lua',
}

server_scripts {
  'server/media.lua',
  'server/sql.lua',
  'server/core.lua',
  'server/remote.lua',
  'server/audio.lua',
  'server/init.lua',
  'server/exports.lua',
}

ui_page 'web/admin.html'

files {
  'web/admin.html',
  'web/admin.css',
  'web/admin.js',
  'web/remote.css',
  'web/remote.js',
  'web/display.html',
  'web/display.css',
  'web/display.js',
}
