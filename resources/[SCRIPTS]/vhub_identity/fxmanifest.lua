fx_version 'cerulean'
game      'gta5'
lua54     'yes'

name        'vhub_identity'
author      'vHub Mirage'
version     '1.1.1'
description 'Identidade do personagem — nome, sobrenome, idade, registro, telefone.'

dependency  'oxmysql'
dependency  'vhub'
dependency  'vhub_money'

server_scripts { '@oxmysql/lib/MySQL.lua', 'server.lua' }
client_scripts { 'client.lua' }
files { 'sql/schema.sql' }
