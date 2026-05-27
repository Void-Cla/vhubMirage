fx_version 'adamant'
game 'gta5'

author 'Void-Hub'
description 'Inventario unificado com mochila, baus, marketplace e lojas (void_mochila_prime)'
version '1.0.0-prime'

ui_page 'nui/index.html'

client_scripts {
    '@vrp/lib/utils.lua',
    'client/main.lua',
    'client/nui.lua',
    'client/threads.lua',
    'client/events.lua',
    'client/identidade.lua',
    'client/mochila_compat.lua',
    'client/player/helpers.lua',
    'client/player/core.lua',
    'client/player/events.lua',
    'client/player/vehicle.lua',
    'client/player/commands.lua'
}


server_scripts {
    '@vrp/lib/utils.lua',
    'database/queries.lua',
    'server/main.lua',
    'server/transacoes.lua',
    'server/compat.lua',
    'server/validacao.lua',
    'server/auditoria.lua',
    'server/callbacks.lua',
    'server/events.lua',
    'server/chest_compat.lua',
    'server/trunkchest_compat.lua',
    'server/marketvoid_compat.lua',
    'server/mochila_compat.lua',
    'server/identidade_compat.lua',
    'server/player/core.lua',
    'server/player/events.lua',
    'server/player/items.lua',
    'server/player/commands.lua',
    'server/player/anti_cheat.lua'
}


files {
    'config.lua',
    'shared/constants.lua',
    'shared/utils.lua',
    'shared/items.lua',
    'nui/index.html',
    'nui/css/styles.css',
    'nui/js/app.js',
    'nui/images/*',
    'nui/fonts/*'
}



