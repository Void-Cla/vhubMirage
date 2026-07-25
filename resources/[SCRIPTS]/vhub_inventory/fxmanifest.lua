---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_inventory'
author      'vHub Mirage'
version     '2.8.0'
description 'Inventário server-authoritative: mochila, baús, drops e Player Hub (topbar identidade + sidebar nav).'

-- Hard deps: core + driver SQL. Identity/Survival sao SOFT (via exports com pcall).
dependencies {
  'vhub',
  'oxmysql',
}

shared_scripts {
  'config/inventory.lua',   -- catalogo de itens (tags) + ajustes
  'shared/events.lua',      -- VHubInvE.* (fonte unica de nomes de evento)
  'shared/utils.lua',       -- helpers puros (peso, slot, validacao)
}

server_scripts {
  'server/sql.lua',            -- exports.oxmysql wrappers + schema
  'server/migrations.lua',     -- runner forward-only (corre sempre no boot, independente de vnext)
  'server/state.lua',          -- kernel VRAM F2: singleflight load, CAS flush, drain (gated por vnext)
  'server/transaction.lua',    -- slot-lock + op dedup CAS (gated por vnext)
  'server/items.lua',          -- catalogo: def/peso/serial/validacao
  'server/backpack.lua',       -- mochila: cache VRAM (online) + slots + delta + flush triplo
  'server/item_use.lua',       -- dispatcher de handlers de uso (registrados por terceiros)
  'server/containers.lua',     -- baús: cache + mutex + open-guard + viewers + flush triplo
  'server/transfer.lua',       -- transferencias atomicas mochila <-> baú
  'server/drops.lua',          -- itens no chão: CAS pickup, TTL, bucket-scoped
  'server/p2p.lua',            -- transferencia direta entre jogadores proximos
  'server/init.lua',           -- boot, schema, sessoes, net events
  'server/exports.lua',        -- API publica (_invoker_allowed nos mutadores)
  'server/dev.lua',            -- comandos de TESTE (/item) — desligavel via Inventory.Dev
}

client_scripts {
  'client/bridge.lua',      -- foco NUI mochila, abrir/fechar, callbacks, snapshot/delta
  'client/containers.lua',  -- HAL de baús: markers + porta-malas (natives) + callbacks
  'client/playerhud.lua',   -- HUD (char_id + identidade)
}

ui_page 'web/index.html'

files {
  'web/index.html',
  'web/bootstrap.js',
  'web/runtime/*.js',
  'web/shared/*.css',
  'web/shared/*.js',
  'web/modules/hud/*',
  'web/modules/hotbar/*',
  'web/modules/backpack/*',
  'web/modules/container/*',
}
