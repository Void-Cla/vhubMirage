fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vhub_legacyfuel'
author 'vHub Mirage'
version '2.1.0'
description 'Abastecimento autoritativo vHub com bomba, carga elétrica, galão e mangueira nativa.'

dependencies {
  'vhub',
  'vhub_conce',
  'vhub_money',
  'vhub_inventory',
  'vhub_target',
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
}

server_script 'server.lua'
client_script 'client.lua'
