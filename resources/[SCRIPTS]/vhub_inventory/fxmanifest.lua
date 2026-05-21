fx_version 'cerulean'
game      'gta5'
lua54     'yes'

name        'vhub_inventory'
author      'vHub Mirage'
version     '1.0.0'
description 'Inventário do personagem com peso, itens, baús e transferências.'

dependency  'vhub'
dependency  'vhub_player_state'
dependency  'vhub_survival'

server_scripts { 'server.lua' }
client_scripts { 'client.lua' }
