fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'vhub_hss'
description 'Sistema autoritativo de estado humano, ped, spawn e fisiologia por char_id'
version     '2.3.0'
author      'vHub Mirage'

dependency 'vhub'
dependency 'oxmysql'

-- ============================================================
-- SHARED
-- ============================================================

shared_scripts {
    'shared/config.lua',
    'shared/events.lua',
    'shared/appearance.lua',
}

-- ============================================================
-- SERVER
-- ============================================================

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sql.lua',
    'server/state.lua',
    'server/buckets.lua',
    'server/ped.lua',
    'server/customization.lua',
    'server/monitor.lua',
    'server/engine.lua',
    'server/items.lua',
    'server/damage.lua',
    'server/exports.lua',
    'server/movement.lua',
    'server/afk.lua',
    'server/init.lua',
}

-- ============================================================
-- CLIENT
-- ============================================================

client_scripts {
    'client/bootstrap.lua',
    'client/hud_native.lua',
    'client/damage.lua',
    'client/native_bridge.lua',
    'client/customization.lua',
    'client/effects.lua',
    'client/movement.lua',
    'client/afk.lua',
}

-- ============================================================
-- NUI
-- ============================================================

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/runtime.js',
    'web/hud.js',
}
