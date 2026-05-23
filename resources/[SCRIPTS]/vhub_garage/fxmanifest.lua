---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_garage'
author      'vHub Mirage'
version     '2.0.0'
description 'Garagem centralizada: garage + concession ria + leil o + p tio + aluguel + IPVA + chave. Fonte de verdade dos ve culos.'

dependencies {
  'vhub',
  'vhub_inventory',
  'vhub_money',
  'vhub_identity',
  'vhub_groups',
  'oxmysql',
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/types.lua',
  'shared/utils.lua',
}

server_scripts {
  'server/sql.lua',
  'server/core.lua',
  'server/init.lua',
  'server/garage.lua',
  'server/dealership.lua',
  'server/auction.lua',
  'server/rental.lua',
  'server/impound.lua',
  'server/ipva.lua',
  'server/maintenance.lua',
  'server/admin.lua',
  'server/exports.lua',
}

client_scripts {
  'client/init.lua',
  'client/vehicles.lua',
  'client/zones.lua',
}

ui_page 'nui/index.html'

files {
  'nui/index.html',
  'nui/css/style.css',
  'nui/js/app.js',
  'nui/js/sand.js',
  'nui/js/garage.js',
  'nui/js/dealership.js',
  'nui/js/auction.js',
  'nui/js/impound.js',
  'nui/assets/bg.png',
  'nui/assets/logo.png',
}
