---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_wow'
author      'vHub Mirage'
version     '2.0.0'
description 'Motor de audio/video (player YouTube nocookie + busca InnerTube/APIv3 + surface DVD no carro).'

dependencies {
  'vhub',
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
}

server_scripts {
  'server/providers/youtube_innertube.lua',  -- busca primaria (sem chave)
  'server/providers/youtube_apiv3.lua',      -- busca fallback (convar wow_youtube_key)
  'server/music_search.lua',                 -- registry+failover+cache+radio (antes dos exports)
  'server/exports.lua',
}

client_scripts {
  'client/settings.lua',
  'client/engine.lua',
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/audio.js',
  'html/runtime.js',
  'html/native.js',
  'html/settings.js',
  'html/style.css',
  'assets/logo.png',
}
