fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vhub_legacyfuel'
description 'Legacy fuel adapted to vHub (server now uses vHub APIs)'

shared_script 'config.lua'

server_script 'server.lua'
client_script 'client.lua'

dependencies {
	'vhub',
	'vhub_money'
}