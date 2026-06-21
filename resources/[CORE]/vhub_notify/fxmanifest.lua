fx_version 'cerulean'
games { 'gta5', 'rdr3' }
lua54 'yes'

description 'vHub Mirage — toast global de notificacao (canal unico vHub:notify)'
author 'vHub Mirage'
version '1.0.0'

client_script 'cl_main.lua'
server_script 'sv_main.lua'

ui_page 'src/index.html'

files {
    'src/*.*',
}
