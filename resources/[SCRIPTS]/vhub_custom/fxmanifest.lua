---@diagnostic disable: undefined-global
fx_version 'cerulean'
game 'gta5'

name        'vhub_custom'
description 'Oficina vHub — Bennys (estética), Mec (reparo/reboque), Oficina (tuning)'
version     '1.0.0'
author      'vHub Mirage'

ui_page 'web/index.html'

files {
  'web/index.html',
  'web/style.css',
  'web/bennys.css',
  'web/mec.css',
  'web/oficina.js',
  'web/bennys.js',
  'web/mec.js',
}

-- ordem: shared → server → client
shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/utils.lua',
  'shared/logger.lua',
}

server_scripts {
  'server/core.lua',
  'server/init.lua',
  'server/bennys.lua',
  'server/mec.lua',
  'server/oficina.lua',
}

client_scripts {
  'client/init.lua',
  'client/camera.lua',   -- L2 HAL: câmera orbital livre (dependência de bennys/oficina)
  'client/zones.lua',
  'client/bennys.lua',
  'client/mec.lua',
  'client/oficina.lua',
}

dependency 'vhub_conce'
dependency 'vhub_money'
