---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_nitro'
author      'vHub Mirage Adaptation'
version     '2.0.0'
description 'Nitro server-authoritative — estado na PLACA via conce (customization.nitro). Ativa no Shift Direito. Reescrito de vRP p/ vHub (decisao #29).'

-- SOFT-deps (via export com pcall): vhub_conce (prontuario/placa), vhub_custom (oficina instala o kit).
dependencies {
  'vhub',
  'vhub_inventory',
}

shared_scripts {
  'cfg/config.lua',
}

server_scripts {
  'server.lua',
}

client_scripts {
  'client.lua',
}
