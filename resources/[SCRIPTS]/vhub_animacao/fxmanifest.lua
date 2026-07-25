fx_version 'cerulean'
game 'gta5'

name        'vhub_animacao'
description 'Motor de emotes/animações — integrado com vhub_hss'
version     '1.0.0'
author      'vHub Mirage'

dependency 'vhub_hss'

-- ============================================================
-- SHARED
-- ============================================================

shared_scripts {
    'shared/events.lua',
    'shared/config.lua',
}

-- ============================================================
-- SERVER
-- ============================================================

server_scripts {
    'server/init.lua',
}

-- ============================================================
-- CLIENT
-- ============================================================

client_scripts {
    'client/init.lua',
}
