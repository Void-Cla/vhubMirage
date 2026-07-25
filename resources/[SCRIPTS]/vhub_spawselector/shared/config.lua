-- vhub_spawselector/shared/config.lua
-- Locations da eleição de spawn. Campo opcional `Perm`: exigência server-side
--   (uid=1 > ACE "vhub.<perm>" > vhub_groups). Sem Perm = público.

Config = {}

Config.Location = {
    [1] = {
        Coords = vector4(324.9939, -229.552, 54.221, 167.54),
        Name = "Motel",
        Description = "Nascer no motel da cidade.",
        Image = "Motel.png"
    },
    [2] = {
        Coords = vector4(420.4171, -965.907, 29.398, 8.92),
        Name = "Departamento de Polícia",
        Description = "Nascer em frente à LSPD.",
        Image = "lspd.png",
        Perm = "spawn.lspd"   -- somente polícia (vhub_groups) vê/usa este ponto
    },
    [3] = {
        Coords = vector4(-277.146, -881.197, 31.546, 351.19),
        Name = "Estacionamento Central",
        Description = "Nascer no estacionamento central.",
        Image = "parking.png"
    },
    [4] = {
        Coords = vector4(2049.449, 3731.146, 32.862, 306.22),
        Name = "Sandy Shores",
        Description = "Nascer em Sandy Shores.",
        Image = "sandy.png"
    },
    [5] = {
        Coords = vector4(-187.425, -1312.40, 31.295, 269.87),
        Name = "Mecânica",
        Description = "Nascer em frente à mecânica.",
        Image = "mechanic.png"
    }
}

-- Card "Última localização": fechar a UI (X) ou não escolher = pos salva.
Config.LastLocation = {
    Name = "Última localização",
    Description = "Retornar à última posição salva.",
    MiniTxt = "Atual"
}
