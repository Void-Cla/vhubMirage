---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_ferinha'
author      'vHub Mirage'
version     '0.1.0'
-- Responsabilidade ÚNICA: marketplace — leilões + venda P2P de chaves de
-- veículo, chaves de casa e itens. Consome conce:transferOwner (dono real),
-- vhub_inventory (itens/chaves) e vhub_money (economia). Não persiste dono
-- nem físico. Ver metas/organização estrutural.md (FASE 4).
description 'Marketplace vHub: leilões + venda P2P (chaves de veículo/casa, itens)'

dependencies {
  'vhub',
  'vhub_conce',
  'vhub_inventory',
  'vhub_money',
  'oxmysql',
}

shared_scripts {
  'shared/config.lua',
}

server_scripts {
  'server/sql.lua',
  'server/core.lua',
  'server/auction.lua',
  'server/exports.lua',
  'server/init.lua',
}
