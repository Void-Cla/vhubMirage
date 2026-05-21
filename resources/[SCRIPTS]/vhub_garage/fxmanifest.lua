fx_version 'cerulean'
game      'gta5'
lua54     'yes'

name        'vhub_garage'
author      'vHub Mirage'
version     '1.0.0'
description 'Garagem: spawna/guarda veículos lendo chave do inventário. Estado salvo na chave.'

dependency 'vhub'
dependency 'vhub_money'
dependency 'vhub_inventory'

server_scripts { 'server.lua' }
client_scripts { 'client.lua' }
