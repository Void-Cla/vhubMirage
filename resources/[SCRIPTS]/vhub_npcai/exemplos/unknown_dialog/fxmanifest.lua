fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author "err_unknown"
description 'Dialog script'
version '1.0.2'

dependencies {
    'ox_lib',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/locales.lua',
    'shared/functions.lua',
    'shared/inventory.lua',
    'shared/target.lua',
    'shared/framework.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

escrow_ignore {
    'shared/target.lua',
    'shared/inventory.lua',
    'locales/locales.lua',
    'shared/framework.lua',
    'config.lua',
}
dependency '/assetpacks'