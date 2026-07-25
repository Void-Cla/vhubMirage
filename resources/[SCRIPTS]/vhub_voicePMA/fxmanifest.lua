fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vhub_voicePMA'
author 'vHub Mirage'
version '1.0.0'
description 'Voz Mumble nativa: proximidade, radio, ligacao e ducking do WOW.'

dependencies {
  'vhub',
  'vhub_hss',
  'vhub_inventory',
  'vhub_groups',
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
}

server_scripts {
  'server/channels.lua',
  'server/init.lua',
  'server/exports.lua',
}

client_scripts {
  'client/transport.lua',
  'client/channels.lua',
  'client/ducking.lua',
}
