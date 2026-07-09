-- fxmanifest.lua — manifesto do recurso vhub_coinshop (Loja de Moedas vHub Mirage)

---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_coinshop'
author      'vHub Mirage'
version     '2.0.0'
description 'Loja de moedas, itens, veículos e ofertas — server-authoritative, integrada ao core vHub.'

-- Dependências do core vHub Mirage (exports.vhub:* são a única fronteira)
dependencies {
    'vhub',              -- SEMPRE: kernel autoritativo (getUser, getCData, notify, etc.)
    'oxmysql',           -- SQL próprio (vhub_coinshop_*)
    'vhub_groups',       -- checagem de permissão (coinshop.admin)
    'vhub_inventory',    -- dar itens/armas ao comprar
    'vhub_player_state', -- teleport do test-drive (owner único do ped)
    'vhub_conce',        -- registrar veículo comprado (contrato de commit)
}

shared_scripts {
    'shared/config.lua',
    'shared/events.lua',
    'shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sql.lua',
    'server/core.lua',
    'server/init.lua',
    'server/coins.lua',
    'server/items.lua',
    'server/purchases.lua',
    'server/discord.lua',
    'server/webhooks.lua',
    'server/testdrive.lua',
    'server/commands.lua',
    'server/exports.lua',
}

client_scripts {
    'client/init.lua',
    'client/nui.lua',
    'client/testdrive.lua',
    'client/vehicle_spawn.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/css/style.css',
    'nui/js/app.js',
}
