Config = {}

-- ============================================================
-- CATEGORIAS (classe GTA → categoria de HUD)
-- ============================================================
-- Classes: 8=moto · 13=bicicleta · 14=barco · 15=heli · 16=avião · resto=carro.
-- Bicicleta usa o HUD bike (digital); barco/heli/avião usam o HUD aéreo (bússola/heading).

Config.VehicleCategories = {
    [0]="carro",[1]="carro",[2]="carro",[3]="carro",[4]="carro",[5]="carro",[6]="carro",
    [7]="carro",[8]="moto",[9]="carro",[10]="carro",[11]="carro",[12]="carro",[13]="bike",
    [14]="aero",[15]="aero",[16]="aero",[17]="carro",[18]="carro",[19]="carro",[20]="carro",
    [21]="carro",[22]="carro"
}


-- ============================================================
-- GALERIA DE HUDs (paths reais — bater com nui/huds/<cat>/<pasta>/)
-- ============================================================
-- Adicionar um HUD = criar a pasta + 1 linha aqui. Cada HUD inclui /nui/velo-core.js (root-relative).

Config.Huds = {
    ["carro"] = {
        { id = "vrm_classic", name = "VRM Clássico", path = "huds/carro/vrm_classic/index.html" },
        { id = "vrm_aut",     name = "VRM Auto",     path = "huds/carro/vrm_aut/index.html" },
    },
    ["moto"] = {
        { id = "moto_default", name = "Moto Padrão", path = "huds/moto/velo_moto_defaut/index.html" },
    },
    ["bike"] = {
        { id = "bike_default", name = "Bike Digital", path = "huds/bike/index.html" },
    },
    ["aero"] = {
        { id = "aero_default", name = "Aviação (Bússola)", path = "huds/aero/helicoptero_defaut/index.html" },
    },
}


-- ============================================================
-- HUD PADRÃO POR CATEGORIA (usado quando o jogador não escolheu)
-- ============================================================

Config.DefaultHuds = {
    ["carro"] = "vrm_classic",
    ["moto"]  = "moto_default",
    ["bike"]  = "bike_default",
    ["aero"]  = "aero_default",
}
