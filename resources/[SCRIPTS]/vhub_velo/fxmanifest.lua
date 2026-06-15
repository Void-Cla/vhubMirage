fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'vhub_velo'
author      'vHub Mirage'
description 'vhub_velo — Sistema de Velocímetro Modular (HUD de display do veículo, consumidor puro)'
version     '2.2.0'

-- Sem server_scripts: a preferência de HUD é KVP client-side (dado de UI, não-crítico).
-- vhub_velo é PURO CONSUMIDOR: lê bags vh_fuel/vh_odo/vhub_seatbelt + natives; nunca escreve verdade.

ui_page 'nui/index.html'

shared_script 'shared/config.lua'

client_scripts {
    'client/main.lua',
}

files {
    'nui/index.html',
    'nui/velo-controller.js',
    'nui/velo-core.js',
    -- HUDs (cada um isolado por iframe). Cobre html/css/js/svg. Se seu HUD usar imagem LOCAL
    -- (.png/.jpg), adicione o glob correspondente; fundos por LINK externo não precisam.
    'nui/huds/**/*.html',
    'nui/huds/**/*.css',
    'nui/huds/**/*.js',
    'nui/huds/**/*.svg',
}
