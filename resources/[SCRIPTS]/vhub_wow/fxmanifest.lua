---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_wow'
author      'vHub Mirage'
version     '1.0.0'
description 'Motor de audio standalone (porta minima do xsound). Sem NLP, sem gateway multi-API, sem adapters de framework.'

dependencies {
  'vhub',
}

shared_scripts {
  'shared/config.lua',
}

server_scripts {
  'server/music.lua',     -- provider Jamendo (busca/radio) + cache — antes dos exports
  'server/exports.lua',
}

client_scripts {
  'client/engine.lua',
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/audio.js',
}
