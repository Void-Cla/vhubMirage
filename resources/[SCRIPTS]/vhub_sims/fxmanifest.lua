---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vhub_sims'
author 'vHub Mirage'
version '1.0.2'
description 'Editor autoritativo de aparência e identidade do vHub Mirage.'

dependencies {
  'vhub',
  'oxmysql',
  'vhub_hss',
  'vhub_identity',
  'vhub_money',
  'vhub_groups',
  'vhub_target',
}

shared_scripts {
  'core/shared/config.lua',
  'config/catalog.lua',
  'config/shops.lua',
  'config/blacklist.lua',
  'config/tattoos.lua',
  'core/shared/events.lua',
}

server_scripts {
  'core/shared/apshape.lua',
  'core/server/sql.lua',
  'core/server/core.lua',
  'core/server/session.lua',
  'core/server/pricing.lua',
  'core/server/outfits.lua',
  'core/server/creation.lua',
  'core/server/shops.lua',
  'core/server/init.lua',
  'core/server/exports.lua',
}

client_scripts {
  'core/client/init.lua',
  'core/client/zones.lua',
}

ui_page 'web/bootstrap/index.html'

files {
  'sql/schema.sql',
  'web/bootstrap/index.html',
  'web/bootstrap/bootstrap.js',
  'web/runtime/eventbus.js',
  'web/runtime/store.js',
  'web/runtime/router.js',
  'web/runtime/native.js',
  'web/runtime/module.js',
  'web/shared/tokens.css',
  'web/shared/components.css',
  'web/shared/sims.js',
  'web/modules/studio/index.html',
  'web/modules/studio/style.css',
  'web/modules/studio/services/index.js',
  'web/modules/studio/views/editor.js',
  'web/modules/studio/app.js',
  'web/modules/wizard/index.html',
  'web/modules/wizard/style.css',
  'web/modules/wizard/services/index.js',
  'web/modules/wizard/views/form.js',
  'web/modules/wizard/app.js',
  'web/modules/checkout/index.html',
  'web/modules/checkout/style.css',
  'web/modules/checkout/services/index.js',
  'web/modules/checkout/views/cart.js',
  'web/modules/checkout/app.js',
  'assets/logo.svg',
}
