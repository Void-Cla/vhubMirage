Config = {}

Config.JerryCanCost = 100
Config.JerryCanCapacity = 25

Config.LiterPrice = 1.7
Config.KwPrice = 0.3

Config.RopeLength = 5.0
Config.RopeMaxLength = 30.0

Config.PumpModels = {
    [-2007231801] = {z = 2.3},
    [1339433404] = {z = 2.3},
    [1694452750] = {z = 2.3},
    [1933174915] = {z = 2.3},
    [-462817101] = {z = 1.8},
    [-469694731] = {z = 1.6},
    [-164877493] = {z = 1.6},
    [1467552538] = {z = 1.6, electric = true},
}

Config.DefaultTankSize = 70.0

Config.TankSizes = {
    ["tug"] = 1000,
    ["winky"] = 50,
}

Config.FuelCaps = {
    ["kamacho"] = {-0.0, 0.55, 0.8},
    ["winky"] = {-0.30, 0.25, 0.65},
}

Config.ElectricVehicles = {
    ["cyclone"] = true,
    ["cyclone2"] = true,
    ["dilettante"] = true,
    ["iwagen"] = true,
    ["imorgon"] = true,
    ["khamelion"] = true,
    ["neon"] = true,
    ["omnisegt"] = true,
    ["raiden"] = true,
    ["surge"] = true,
    ["tezeract"] = true,
    ["virtue"] = true,
    ["voltic"] = true,
}

Config.TimeForCompleteCharge = 40

Config.ClassFuelUsage = {
    [0] = 1.0, [1] = 1.0, [2] = 1.0, [3] = 1.0, [4] = 1.0, [5] = 1.0, [6] = 1.0, [7] = 1.0,
    [8] = 1.0, [9] = 1.0, [10] = 1.0, [11] = 1.0, [12] = 1.0, [13] = 0.0, [14] = 1.0,
    [15] = 1.0, [16] = 1.0, [17] = 1.0, [18] = 1.0, [19] = 1.0, [20] = 1.0, [21] = 0.0
}

Config.ModelFuelUsage = {
    ["tug"] = 0.1,
    ["winky"] = 1.0,
}

Config.Blacklist = {
    ["airtug"] = true,
    ["caddy"] = true,
    ["caddy2"] = true,
    ["caddy3"] = true,
}

Config.FuelUsage = {
    [1.0] = 1.4, [0.9] = 1.2, [0.8] = 1.0, [0.7] = 0.9, [0.6] = 0.8,
    [0.5] = 0.7, [0.4] = 0.5, [0.3] = 0.4, [0.2] = 0.2, [0.1] = 0.1, [0.0] = 0.0
}

Config.KwUsage = {
    [1.0] = 1.4, [0.9] = 1.2, [0.8] = 1.0, [0.7] = 0.9, [0.6] = 0.8,
    [0.5] = 0.7, [0.4] = 0.5, [0.3] = 0.4, [0.2] = 0.001, [0.1] = 0.001, [0.0] = 0.0
}

Config.GasStations = {
    vector3(49.4187, 2778.793, 58.043), vector3(263.894, 2606.463, 44.983),
    vector3(1039.958, 2671.134, 39.550), vector3(1207.260, 2660.175, 37.899),
    vector3(2539.685, 2594.192, 37.944), vector3(2679.858, 3263.946, 55.240),
    vector3(2005.055, 3773.887, 32.403), vector3(1687.156, 4929.392, 42.078),
    vector3(1701.314, 6416.028, 32.763), vector3(179.857, 6602.839, 31.868),
    vector3(-94.4619, 6419.594, 31.489), vector3(-2554.996, 2334.40, 33.078),
    vector3(-1800.375, 803.661, 138.651), vector3(-1437.622, -276.747, 46.207),
    vector3(-2096.243, -320.286, 13.168), vector3(-724.619, -935.1631, 19.213),
    vector3(-526.019, -1211.003, 18.184), vector3(-70.2148, -1761.792, 29.534),
    vector3(265.648, -1261.309, 29.292), vector3(819.653, -1028.846, 26.403),
    vector3(1208.951, -1402.567, 35.224), vector3(1181.381, -330.847, 69.316),
    vector3(620.843, 269.100, 103.089), vector3(2581.321, 362.039, 108.468),
    vector3(176.631, -1562.025, 29.263), vector3(-319.292, -1471.715, 30.549),
    vector3(-66.48, -2532.57, 6.14), vector3(1784.324, 3330.55, 41.253)
}

Config.SuperchargerStations = {
    vector3(153.4138, 6592.721, 30.8449), vector3(2697.205, 3277.662, 54.24057),
    vector3(-2534.736, 2345.22, 32.05991), vector3(645.1025, 280.3252, 102.1716),
    vector3(-729.0958, -911.1166, 18.01393),
}

Config.MaxDistance = 2.0
Config.ActionKey = 38
Config.Texts3d = true
Config.TargetSystem = 'auto' -- 'auto', 'qb-target', 'ox_target'

Config.DisableKeys = {0, 22, 23, 24, 29, 30, 31, 37, 44, 56, 82, 140, 166, 167, 168, 170, 288, 289, 311, 323}
Config.FuelDecor = "_FUEL_LEVEL"
