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
  'shared/events.lua',      -- nomes de eventos do engine de skill (anti-fantasma)
  'shared/tier_rules.lua',  -- regras PURAS de tier/score/alloc/afinidade (server + client)
}

server_scripts {
  'server/main.lua',
  'server/item_handlers.lua',    -- integracao com vhub_inventory (veh_key + caixadeferramentas)
  'server/exports.lua',          -- API read-only: getVehicleTier/Score/Affinity/Sheet (decisão #27)
  'server/skill.lua',            -- handler único RECALIBRATE: toolbox + oficina (decisão #27)
  'server/nitro_bridge.lua',     -- ficha → vhub_nitro: liga/nível/abastece (delega, decisão #30)
}

client_scripts {
  'client/main.lua',
  'client/handling.lua',         -- F5: aplica fisica derivada (sheet.hnd) no carro dirigido (decisao #28)
}

-- Velocímetro REMOVIDO (VELO-3 2026-06): agora é o resource `vhub_velo` (1 velocímetro só).
-- vehcontrol mantém painel de controle + cinto (vhub_seatbelt) + telemetria do PRONTUÁRIO
-- (stateSync/requestState → vhub_conce; cadeia vEnter/vLeave do CORE removida na decisão #24).

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/core.js',           -- nucleo: showPanel/hidePanel + dispatch das mensagens do Lua
  'html/controls.js',
  'html/ficha.js',
  'html/sound.js',
  'html/style-core.css',
  'html/style-controls.css',
  'html/style-ficha.css',
  'html/style-sound.css',
}
