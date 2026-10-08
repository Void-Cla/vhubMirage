fx_version 'cerulean'
game 'gta5'

author 'vHub tests'
description 'vHub test runner for automated smoke tests (server-side) - execute in test environment only'

dependency 'vhub'

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  '@vhub/shared/sql_script.lua',
  'test_runner.lua',
}
