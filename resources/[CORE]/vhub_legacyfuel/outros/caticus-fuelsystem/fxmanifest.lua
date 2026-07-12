fx_version 'cerulean'
game 'gta5'

author 'caticus'
description 'A multi-framework fuel system with realistic hoses - Supports ESX, QBCore, and QBox'
website 'www.5Mservers.com'

version '1.0.0'

shared_scripts {
    'shared/locale.lua',
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

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/script.js',
    'html/**/*.*',
    'data/handling.meta',
    'data/vehicles.meta',
    'data/carvariations.meta',
    'stream/*.yft',
    'stream/*.ytd'
}

data_file 'HANDLING_FILE' 'data/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'

dependencies {
    'oxmysql'
}

lua54 'yes'
