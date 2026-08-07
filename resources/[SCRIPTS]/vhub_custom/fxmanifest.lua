---@diagnostic disable: undefined-global
fx_version 'cerulean'
game 'gta5'

name        'vhub_custom'
description 'Oficina vHub — Bennys (estética), Mec (reparo/reboque), Oficina (tuning), Drift (peça)'
version     '2.2.0'
author      'vHub Mirage'

ui_page 'web/index.html'

files {
  'sql/schema.sql',
  'web/index.html',
  'web/style.css',
  'web/bennys.css',
  'web/mec.css',
  'web/runtime.js',
  'web/oficina.js',
  'web/bennys.js',
  'web/mec.js',
}

-- ordem: shared → server → client
shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/utils.lua',
  'shared/logger.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/sql.lua',
  'server/core.lua',
  'server/visual.lua',   -- reidrata State Bags de stance/escapamento/drift a partir da placa
  'server/init.lua',
  'server/bennys.lua',
  'server/mec.lua',
  'server/oficina.lua',
  'server/drift.lua',    -- Freio de Mão Hidráulico (peça instalável — FASE 1 ADR #81)
}

client_scripts {
  'client/init.lua',
  'client/camera.lua',   -- L2 HAL: câmera orbital livre (dependência de bennys/oficina)
  'client/zones.lua',
  'client/stance.lua',   -- L2 HAL: rebaixamento visual per-entidade (State Bag)
  'client/exhaust.lua',  -- L2 HAL: chamas coloridas não-ignitáveis (State Bag)
  'client/bennys.lua',
  'client/mec.lua',
  'client/oficina.lua',
  'client/drift.lua',    -- L2 HAL: mecânica de drift + pontuação bruta (Freio de Mão Hidráulico — FASE 1 ADR #81)
}

dependencies {
  'oxmysql',
  'vhub',
  'vhub_conce',
  'vhub_money',
  'vhub_vehcontrol',
  'vhub_nitro',
}
