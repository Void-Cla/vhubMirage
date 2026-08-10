---@diagnostic disable: undefined-global
fx_version 'cerulean'
game 'gta5'

name        'vhub_custom'
description 'Oficina vHub — Bennys (estética), Mec (reparo/reboque), Oficina/Engenharia (peças), Drift, Nitro'
version     '2.9.0'
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
  'shared/nitro_cfg.lua',      -- configuração do nitro (FASE 2 ADR #81)
  'shared/parts_catalog.lua',  -- catálogo declarativo de peças de engenharia (ADR #82 FASE 1)
  'shared/compat.lua',         -- resolvedor PURO de compatibilidade de peças (ADR #85 F2.5-A)
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/sql.lua',
  'server/core.lua',
  'server/visual.lua',   -- reidrata State Bags de stance/escapamento/drift a partir da placa
  'server/init.lua',
  'server/bennys.lua',
  'server/mec.lua',
  'server/nitro.lua',    -- escritor único de customization.nitro (FASE 2 ADR #81)
  'server/oficina.lua',
  'server/engine_bay.lua', -- ADR #82 F2.2: leitura gated do motor (imersão capô→engine bay)
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
  'client/nitro.lua',    -- L2 HAL: boost RSHIFT + drain + HUD (FASE 2 ADR #81)
  'client/oficina.lua',
  'client/drift.lua',    -- L2 HAL: mecânica de drift + pontuação bruta (Freio de Mão Hidráulico — FASE 1 ADR #81)
  'client/target_hood.lua', -- L2 HAL: interação capô via vhub_target (ADR #82 F2.2) — soft-dep, pcall
}

dependencies {
  'oxmysql',
  'vhub',
  'vhub_conce',
  'vhub_money',
  'vhub_inventory',
  'vhub_vehcontrol',
}
