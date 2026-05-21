fx_version 'cerulean'
game      'gta5'
lua54     'yes'

name        'vhub_admin'
author      'vHub Mirage'
version     '1.1.0'
description 'Ferramentas de administração: painel NUI, teleporte, kick, ban, dinheiro, itens, noclip.'

ui_page 'html/index.html'

dependency 'vhub'
dependency 'vhub_player_state'
dependency 'vhub_inventory'
dependency 'vhub_money'
dependency 'vhub_groups'

server_scripts { 'server.lua' }
client_scripts { 'client.lua' }

files {
  'html/index.html',
}
