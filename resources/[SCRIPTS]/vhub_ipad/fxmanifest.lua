---@diagnostic disable: undefined-global, lowercase-global

fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_ipad'
author      'vHub Mirage'
version     '3.0.0'
description 'Tablet iOS-style — plataforma de apps vHub (registry server-authoritative, estado per-char)'

-- vhub = core (getUser/hasPerm). vhub_inventory = soft-dep (item 'ipad', verificado em runtime).
dependencies {
  'vhub',
}


-- ============================================================
-- SHARED — config, eventos, validador de manifest (sem estado)
-- ============================================================

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/manifest_schema.lua',
}


-- ============================================================
-- SERVER — ordem: sql → state → registry → exports → init
-- ============================================================

server_scripts {
  'server/bootstrap.lua',
  'server/sql.lua',
  'server/state.lua',
  'server/registry.lua',
  'server/exports.lua',
  'server/relay.lua',
  'server/init.lua',
}


-- ============================================================
-- CLIENT
-- ============================================================

client_scripts {
  'client/init.lua',
}


-- ============================================================
-- NUI
-- ============================================================

ui_page 'web/index.html'

files {
  'web/index.html',

  -- runtime (engine NUI — 5 arquivos; core.js é fork owned/divergente do racha)
  'web/runtime/bus.js',
  'web/runtime/store.js',
  'web/runtime/bridge.js',
  'web/runtime/sand.js',
  'web/runtime/core.js',

  -- shared (tema, reset, layout do shell, utils, shell controller)
  'web/shared/reset.css',
  'web/shared/tokens.css',
  'web/shared/shell.css',
  'web/shared/utils.js',
  'web/shared/shell.js',

  -- módulos builtin
  'web/modules/home/home.html',
  'web/modules/home/home.css',
  'web/modules/home/home.js',

  'web/modules/settings/settings.html',
  'web/modules/settings/settings.css',
  'web/modules/settings/settings.js',

  'web/modules/store/store.html',
  'web/modules/store/store.css',
  'web/modules/store/store.js',

  'web/modules/relogio/relogio.html',
  'web/modules/relogio/relogio.css',
  'web/modules/relogio/relogio.js',

  'web/modules/racha/racha.html',
  'web/modules/racha/racha.css',
  'web/modules/racha/racha.js',
}
