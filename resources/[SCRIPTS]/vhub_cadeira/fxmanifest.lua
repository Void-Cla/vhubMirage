---@diagnostic disable: undefined-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_cadeira'
author      'vHub Mirage'
version     '1.0.0'
description 'Sentar em props (cadeiras/sofás/camas) via vhub_target — zero framework'

dependency 'vhub_target'

shared_scripts {
  'shared/props.lua',
}

client_scripts {
  'client/init.lua',
}
