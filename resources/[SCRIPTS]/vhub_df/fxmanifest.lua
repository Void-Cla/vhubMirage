-- fxmanifest.lua — manifesto do vhub_df (gateway de pagamento Pix · MercadoPago)

---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_df'
author      'vHub Mirage'
version     '1.0.0'
description 'Gateway de pagamento Pix (MercadoPago): QR + copia-e-cola, polling + webhook, entrega via handlers registrados por exports gated.'

-- Dependências (exports.vhub:* são a única fronteira com o core)
dependencies {
    'vhub',       -- kernel autoritativo (getUser → char_id)
    'oxmysql',    -- SQL próprio (vhub_df_*)
}

shared_scripts {
    'shared/config.lua',
    'shared/events.lua',
    'shared/utils.lua',
}

server_scripts {
    'server/sql.lua',
    'server/core.lua',
    'server/mercadopago.lua',
    'server/payments.lua',
    'server/queue.lua',
    'server/webhook.lua',
    'server/exports.lua',
    'server/init.lua',
}

client_scripts {
    'client/init.lua',
}

ui_page 'nui/index.html'

files {
    -- NUI (A-10: todo asset carregado declarado; zero CDN)
    'nui/index.html',
    'nui/css/style.css',
    'nui/js/app.js',

    -- schema lido no boot via LoadResourceFile
    'sql/schema.sql',
}
