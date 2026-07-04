-- fxmanifest.lua — pacote ÚNICO de carros add-on (streaming DINÂMICO via glob).
-- NÃO precisa listar arquivo por arquivo: solte a pasta do carro dentro de carmod/
-- e os metas + modelos são detectados sozinhos. O catálogo de venda fica em
-- vhub_conce/shared/catalog.lua (a chave = <modelName> do vehicles.meta, minúsculo).

fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'carmod'
author      'vHub Mirage'
description 'Streaming dinâmico de veículos add-on (glob — solte a pasta e pronto)'
version     '1.0.0'


-- ============================================================
-- STREAMING (100% automático)
-- ============================================================
-- O FiveM auto-streama QUALQUER pasta chamada `stream` em qualquer nível do resource.
-- Você NUNCA lista .yft/.ytd. Funciona com os dois layouts:
--   carmod/stream/<carro>/...      ← layout atual
--   carmod/<carro>/stream/...      ← se você soltar a pasta do mod inteira


-- ============================================================
-- METADADOS (glob recursivo — pega carro novo sozinho)
-- ============================================================
-- `**` = qualquer profundidade. Um carro novo com seus metas (em common/, data/
-- ou na raiz da pasta dele) é detectado SEM editar este arquivo.

files {
    '**/vehicles.meta',
    '**/carvariations.meta',
    '**/carcols.meta',
    '**/handling.meta',
    '**/vehiclelayouts.meta',
}

data_file 'VEHICLE_METADATA_FILE'  '**/vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' '**/carvariations.meta'
data_file 'CARCOLS_FILE'           '**/carcols.meta'
data_file 'HANDLING_FILE'          '**/handling.meta'
data_file 'VEHICLE_LAYOUTS_FILE'   '**/vehiclelayouts.meta'

-- Notas:
--  • carvariations.meta = VEHICLE_VARIATION_FILE (NÃO "..._DATA_FILE" — era o erro antigo).
--  • vehiclelayouts.meta só existe em alguns mods (ex.: supra); o glob ignora quem não tem.
--  • dlctext.meta NÃO é necessário para add-on no FiveM — pode deixar na pasta (ignorado).
