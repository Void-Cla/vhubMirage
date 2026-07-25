fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Gh0st'
description 'Advent Calendar System - ESX/QBCore Compatible'
website 'www.5Mservers.com'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/script.js'
}

