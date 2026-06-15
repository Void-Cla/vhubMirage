fx_version 'cerulean'
game       'gta5'

author      'vHub Mirage'
description 'Mapa depzitamadasptlnd'
version     '1.0.0'

this_is_a_map 'yes'

-- stream/ é auto-streamado (.ymap .ydr .ytd .ybn .ymf). Aqui só declaramos o archetype.
files {
    'stream/dep_tamadasptlnd.ytyp',
}

-- archetypes dos props/MLO deste mapa. CAMINHO CERTO = o .ytyp que existe no stream/
-- (o original apontava 'schoolmoe.ytyp', sobra de outro mod → arquivo inexistente).
data_file 'DLC_ITYP_REQUEST' 'stream/dep_tamadasptlnd.ytyp'
