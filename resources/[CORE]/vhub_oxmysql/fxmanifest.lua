-- fxmanifest.lua — vhub_oxmysql
-- Este resource é o único ponto de contato entre o vHub e o banco de dados.
-- Deve ser carregado DEPOIS do oxmysql e ANTES do vhub no server.cfg.
fx_version 'cerulean'
game      'gta5'
lua54     'yes'

name        'vhub_oxmysql'
author      'vHub Mirage'
version     '1.0.0'
description 'Driver de banco de dados do vHub Mirage — adapter sobre oxmysql com pool, retry, batch e circuit breaker.'

-- oxmysql precisa estar iniciado para os exports existirem
dependency 'oxmysql'

server_scripts {
  'driver.lua',   -- implementação do driver (único arquivo)
}
