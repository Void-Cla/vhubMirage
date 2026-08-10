fx_version 'cerulean'
game 'gta5'

name        'vhub_animacao'
description 'Motor de emotes/animações + sentar em props — integrado com vhub_hss'
version     '1.1.0'
author      'vHub Mirage'

dependency 'vhub_hss'
dependency 'vhub_target'

-- ============================================================
-- SHARED
-- ============================================================

shared_scripts {
    'shared/events.lua',
    'shared/config.lua',
    'shared/props.lua',
    'shared/sit_config.lua',
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
    'client/sit.lua',
}
