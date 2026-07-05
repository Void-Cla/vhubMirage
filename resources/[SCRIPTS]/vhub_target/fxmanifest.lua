---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'
nui_callback_strict_mode 'true'

name        'vhub_target'
author      'vHub Mirage'
version     '1.0.0'
description 'Interação por mira (targeting) — API de exports compatível com ox_target 1.18.x'

dependency 'vhub'

ui_page 'web/index.html'

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
}

client_scripts {
  'client/init.lua',      -- cache leve (ped/veículo) + keybind
  'client/state.lua',     -- estado do targeting (ativo/focus/disabled/locked)
  'client/zones.lua',     -- engine própria de zonas (box/sphere/poly)
  'client/utils.lua',     -- raycast, filtros de grupo/item
  'client/api.lua',       -- exports públicos (superfície ox_target-compatible)
  'client/main.lua',      -- loop de targeting + NUI select
  'client/defaults.lua',  -- opções built-in de portas de veículo
  'client/debug.lua',     -- zonas/opções de teste (gated por cfg.debug)
}

server_scripts {
  'server/main.lua',      -- validação de netid/porta + rate-limit + GC de entidades
}

files {
  'web/index.html',
  'web/style.css',
  'web/js/icons.js',
  'web/js/fetchNui.js',
  'web/js/createOptions.js',
  'web/js/main.js',
}
