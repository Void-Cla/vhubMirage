fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'vhub_rp'
description 'Comandos RP sociais/informativos: /me, /status'
version     '1.0.0'
author      'vHub Mirage'

dependency 'vhub'
dependency 'vhub_identity'


-- ============================================================
-- SHARED
-- ============================================================

shared_scripts {
    'shared/config.lua',
    'shared/events.lua',
}


-- ============================================================
-- SERVER
-- ============================================================

server_scripts {
    'server/broadcast.lua',
    'server/status.lua',
}


-- ============================================================
-- CLIENT
-- ============================================================

client_scripts {
    'client/broadcast.lua',
}
