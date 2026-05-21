fx_version 'cerulean'
game      'gta5'
lua54     'yes'

name        'vhub_dealership'
author      'vHub Mirage'
version     '1.0.0'
description 'Concessionária: compra e venda de veículos. Gera chave e entrega ao inventário.'

dependency 'vhub'
dependency 'vhub_inventory'
dependency 'vhub_money'

server_scripts { 'server.lua' }
client_scripts { 'client.lua' }
