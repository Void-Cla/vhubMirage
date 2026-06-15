---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_lspdtool'
author      'vHub Mirage'
version     '2.0.0'
description 'LSPD Tool: radar automatico + leitura de placa (radar/helicam) + BOLO e dispatch nativos vHub'

-- Integração com sd-policeradar / helicam é SOFT (via pcall) — não são dependências.
-- vhub_groups é usado via exports (sempre presente no stack vHub).
dependencies {
    'vhub',
    'oxmysql',
}

shared_scripts {
    'shared/config.lua',
    'shared/logger.lua',
    'shared/events.lua',
}

server_scripts {
    'server/main.lua',
    'server/bolo.lua',
    'server/mdt.lua',
    'server/accounts.lua',   -- login/senha do app LSPD no iPad
    'server/wanted.lua',     -- procurados (pessoas)
    'server/arrest.lua',     -- prisão (detenção) + apreensão de veículo
    'server/ipad.lua',       -- export ipadRelay (app LSPD no iPad; registro = builtin no config do iPad)
}

client_scripts {
    'client/police.lua',
    'client/radar.lua',
    'client/helicam.lua',
    'client/mdt.lua',
    'client/arrest.lua',     -- HAL do estado de detido (algema + controles)
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/core.css',
    'web/app.js',
    'web/modules/radar/radar.css',
    'web/modules/radar/radar.js',
    'web/modules/helicam/helicam.css',
    'web/modules/helicam/helicam.js',
    'web/modules/mdt/mdt.css',
    'web/modules/mdt/mdt.js',

    -- App "Central LSPD" embutido no iPad (carregado via cfx-nui-vhub_lspdtool/…)
    'web/app_ipad/lspd.html',
    'web/app_ipad/lspd.css',
    'web/app_ipad/lspd.js',
}
