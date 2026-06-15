-- vhub_spawselector/shared/config.lua
-- Locations da eleição de spawn. Campo opcional `Perm`: exigência server-side
--   (uid=1 > ACE "vhub.<perm>" > vhub_groups). Sem Perm = público.

Config = {}

Config.Location = {
    [1] = {
        Coords = vector4(324.9939, -229.552, 54.221, 167.54),
        Name = "Motel",
        Description = "Click on select to go to Pink cage Motel",
        Image = "motel.png"
    },
    [2] = {
        Coords = vector4(420.4171, -965.907, 29.398, 8.92),
        Name = "Police Department",
        Description = "Click on select to go to LSPD",
        Image = "lspd.png",
        Perm = "spawn.lspd"   -- somente polícia (vhub_groups) vê/usa este ponto
    },
    [3] = {
        Coords = vector4(-277.146, -881.197, 31.546, 351.19),
        Name = "Central parking",
        Description = "Click on select to go to central parking",
        Image = "parking.png"
    },
    [4] = {
        Coords = vector4(2049.449, 3731.146, 32.862, 306.22),
        Name = "Sandy Shores",
        Description = "Click on select to go to Sandy Shores",
        Image = "sandy.png"
    },
    [5] = {
        Coords = vector4(-187.425, -1312.40, 31.295, 269.87),
        Name = "Mechanic",
        Description = "Click on select to go to mechanic location",
        Image = "mechanic.png"
    }
}

-- Card "Última localização": fechar a UI (X) ou não escolher = pos salva.
Config.LastLocation = {
    Name = "Last Location",
    Description = "The last location you were in",
    MiniTxt = "main"
}
