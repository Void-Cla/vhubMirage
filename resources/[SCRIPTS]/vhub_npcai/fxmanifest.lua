---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_npcai'
author      'vHub Mirage'
version     '1.0.0'
description 'NPCs conversacionais por voz — STT/intenção/cache/Gemini, server-authoritative'

dependencies {
    'vhub',
    'oxmysql',
    'vhub_hss',
}

shared_scripts {
    'shared/config.lua',
    'shared/events.lua',
    'shared/logger.lua',
    'shared/utils.lua',
}

server_scripts {
    'server/sql.lua',
    'server/core.lua',
    'server/memory.lua',
    'server/relay.lua',
    'server/init.lua',
    'server/exports.lua',
}

client_scripts {
    'client/init.lua',
    'client/world.lua',
    'client/ped_control.lua',
    'client/proximity.lua',
    'client/mic.lua',
    'client/camera.lua',
    'client/playback.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/css/style.css',
    'nui/js/app.js',

    -- murmúrios genéricos (gerados por sidecar/gerar_audio_npcs.py)
    'nui/audio/murmur_generic_1.wav',
    'nui/audio/murmur_generic_2.wav',
    'nui/audio/murmur_generic_3.wav',
    'nui/audio/murmur_generic_4.wav',
    'nui/audio/murmur_generic_5.wav',

    -- thinking frases por NPC (silêncio zero enquanto IA processa)
    'nui/audio/thinking/jorjao/thinking_00.wav',
    'nui/audio/thinking/jorjao/thinking_01.wav',
    'nui/audio/thinking/jorjao/thinking_02.wav',
    'nui/audio/thinking/jorjao/thinking_03.wav',
    'nui/audio/thinking/jorjao/thinking_04.wav',
    'nui/audio/thinking/jorjao/thinking_05.wav',
    'nui/audio/thinking/jorjao/thinking_06.wav',
    'nui/audio/thinking/jorjao/thinking_07.wav',
    'nui/audio/thinking/jorjao/thinking_08.wav',
    'nui/audio/thinking/jorjao/thinking_09.wav',
    'nui/audio/thinking/rebeca/thinking_00.wav',
    'nui/audio/thinking/rebeca/thinking_01.wav',
    'nui/audio/thinking/rebeca/thinking_02.wav',
    'nui/audio/thinking/rebeca/thinking_03.wav',
    'nui/audio/thinking/rebeca/thinking_04.wav',
    'nui/audio/thinking/rebeca/thinking_05.wav',
    'nui/audio/thinking/rebeca/thinking_06.wav',
    'nui/audio/thinking/rebeca/thinking_07.wav',
    'nui/audio/thinking/rebeca/thinking_08.wav',
    'nui/audio/thinking/rebeca/thinking_09.wav',
    'nui/audio/thinking/carvalho/thinking_00.wav',
    'nui/audio/thinking/carvalho/thinking_01.wav',
    'nui/audio/thinking/carvalho/thinking_02.wav',
    'nui/audio/thinking/carvalho/thinking_03.wav',
    'nui/audio/thinking/carvalho/thinking_04.wav',
    'nui/audio/thinking/carvalho/thinking_05.wav',
    'nui/audio/thinking/carvalho/thinking_06.wav',
    'nui/audio/thinking/carvalho/thinking_07.wav',
    'nui/audio/thinking/carvalho/thinking_08.wav',
    'nui/audio/thinking/carvalho/thinking_09.wav',
    'nui/audio/thinking/marcus/thinking_00.wav',
    'nui/audio/thinking/marcus/thinking_01.wav',
    'nui/audio/thinking/marcus/thinking_02.wav',
    'nui/audio/thinking/marcus/thinking_03.wav',

    -- saudações padrão pré-cacheadas por NPC
    'nui/audio/greet/jorjao/greet_default_00.wav',
    'nui/audio/greet/jorjao/greet_default_01.wav',
    'nui/audio/greet/rebeca/greet_default_00.wav',
    'nui/audio/greet/rebeca/greet_default_01.wav',
    'nui/audio/greet/carvalho/greet_default_00.wav',
    'nui/audio/greet/carvalho/greet_default_01.wav',
    'nui/audio/greet/marcus/greet_default_00.wav',
    'nui/audio/greet/marcus/greet_default_01.wav',
}
