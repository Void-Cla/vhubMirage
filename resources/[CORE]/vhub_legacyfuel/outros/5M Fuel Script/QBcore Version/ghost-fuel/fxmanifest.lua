fx_version 'cerulean'
game 'gta5'

author 'Gh0st / Team 5M'
description 'A simple free and open source fuel script that adds realistic hoses for fuel nozzles'
website 'www.5Mservers.com'

version '1.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua',
    'config.lua'
}


server_scripts {
    '@oxmysql/lib/MySQL.lua',
	'server/main.lua'
}

client_scripts {
	'client/main.lua'
}

dependencies {
  'qb-target'
}

lua54 'yes'
