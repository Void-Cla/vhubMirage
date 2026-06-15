---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_vehcontrol'
author      'vHub Mirage Adaptation'
version     '1.1.0'
description 'Controle de veiculo (portas, motor, trava, luzes, banco, camera). Adaptado p/ vHub. Integracao: veh_key.'

-- SOFT-deps (via export com pcall, NAO em dependencies p/ nao travar o boot):
--   xsound       -> radio (sem ele, o resto funciona)
--   vhub_garage  -> caminho "dono do veiculo" da trava/motor (sem ele, vale so a chave fisica)
dependencies {
  'vhub',
  'vhub_inventory',
}

shared_scripts {
  'shared/config.lua',
}

server_scripts {
  'server/main.lua',
  'server/item_handlers.lua',    -- integracao com vhub_inventory (veh_key use)
}

client_scripts {
  'client/main.lua',
}

-- Velocímetro REMOVIDO (VELO-3 2026-06): agora é o resource `vhub_velo` (1 velocímetro só).
-- vehcontrol mantém painel de controle + cinto (vhub_seatbelt) + telemetria do PRONTUÁRIO
-- (stateSync/requestState → vhub_conce; cadeia vEnter/vLeave do CORE removida na decisão #24).

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/app.js',
  'html/style-core.css',
  'html/style-dashboard.css',
  'html/style-buttons.css',
}
