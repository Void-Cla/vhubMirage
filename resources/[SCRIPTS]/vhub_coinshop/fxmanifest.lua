-- fxmanifest.lua — manifesto do recurso vhub_coinshop (Loja de Moedas vHub Mirage)

---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_coinshop'
author      'vHub Mirage'
version     '2.4.0'
description 'Loja de moedas, itens, veículos e ofertas — server-authoritative, integrada ao core vHub.'

-- Dependências do core vHub Mirage (exports.vhub:* são a única fronteira)
dependencies {
    'vhub',           -- SEMPRE: kernel autoritativo (getUser, getCData, notify, etc.)
    'oxmysql',        -- SQL próprio (vhub_coinshop_*)
    'vhub_groups',    -- checagem de permissão (coinshop.admin)
    'vhub_inventory', -- dar itens/armas ao comprar
    'vhub_conce',     -- registrar veículo comprado (contrato de commit)
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
    'server/commands.lua',
    'server/exports.lua',
    'server/pix_mp.lua',       -- integração MercadoPago Pix (provider real; cfg.pix.provider='mercadopago')
    'server/import.lua',       -- importação em massa: inventário + catálogo de veículos → coinshop_items
    'server/ipad_relay.lua',   -- app CoinShop do iPad (broker vhub_ipad; depois de tudo carregado)
}

client_scripts {
    'client/init.lua',
}

-- ui_page removido: admin migrou para o painel do iPad (relay ipad_relay.lua, v2.3.0)

files {
    -- app do iPad (UI REMOTA: servida via cfx-nui-vhub_coinshop ao CEF do tablet — A-10)
    'web/app_ipad/coinshop.html',
    'web/app_ipad/coinshop.css',
    'web/app_ipad/coinshop.js',
}
