---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_conce'
author      'vHub Mirage'
version     '0.4.4'
-- Responsabilidade ÚNICA: identidade do veículo — relação CHAVE↔PLACA↔DONO,
-- concessionária (compra/test-drive/estoque/placa única), emissão/clone/
-- empréstimo/revogação de chave, cron 24h e status/IPVA.
-- Renderiza apenas blips e NPCs próprios no cliente (presence.lua).
-- Não guarda físico (CORE) nem dinheiro (vhub_money). Ver metas/organização estrutural.md.
description 'Concessionária + autoridade chave/placa/dono do veículo (server-authoritative)'

dependencies {
  'vhub',
  'vhub_inventory',
  'vhub_money',
  'oxmysql',
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/utils.lua',
  'shared/catalog.lua',
}

client_scripts {
  'client/presence.lua',
}

server_scripts {
  'server/sql.lua',
  'server/core.lua',
  'server/vstate.lua',
  'server/dealership.lua',
  'server/exports.lua',
  'server/init.lua',
}
