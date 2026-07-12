-- shared/config.lua — configuração do domínio de abastecimento vHub

VHubFuel = VHubFuel or {}

local C = {
  TickMs = 1000,                 -- budget: 1 Hz somente com sessão ativa
  SessionTimeoutMs = 180000,
  RateStartMs = 750,
  PlayerVehicleDistance = 4.0,
  StationRadius = 28.0,
  RopeLength = 5.0,
  RopeMaxLength = 18.0,
  RopeType = 1,
  FuelPerTick = 1.0,
  ChargePerTick = 1.0,
  PricePerPercent = 10,
  ElectricPricePerPercent = 6,
  JerryCanCost = 300,
  JerryCanFuel = 25.0,
  JerryCanItem = 'fuel_can',
  ActionKey = 38,
  NozzleModel = joaat('prop_cs_fuel_nozle'),
  JerryCanModel = joaat('prop_jerrycan_01a'),
  NozzleHand = {
    bone = 28422,
    offset = vec3(0.0549, 0.049, 0.0),
    rotation = vec3(-50.0, -90.0, -50.0),
  },
  NozzleCapRotation = vec3(-50.0, 0.0, -90.0),
  NozzleTipOffset = vec3(0.0, -0.019, -0.1749),
}

C.PumpModels = {
  [-2007231801] = { z = 2.3 },
  [1339433404]  = { z = 2.3 },
  [1694452750]  = { z = 2.3 },
  [1933174915]  = { z = 2.3 },
  [-462817101]  = { z = 1.8 },
  [-469694731]  = { z = 1.6 },
  [-164877493]  = { z = 1.6 },
  [1467552538]  = { z = 1.6, electric = true },
}

C.ElectricModels = {
  [joaat('cyclone')] = true, [joaat('cyclone2')] = true, [joaat('dilettante')] = true,
  [joaat('iwagen')] = true, [joaat('imorgon')] = true, [joaat('khamelion')] = true,
  [joaat('neon')] = true, [joaat('omnisegt')] = true, [joaat('raiden')] = true,
  [joaat('surge')] = true, [joaat('tezeract')] = true, [joaat('virtue')] = true,
  [joaat('voltic')] = true,
}

C.FuelCaps = {
  [joaat('kamacho')] = vec3(0.0, 0.55, 0.8),
  [joaat('winky')] = vec3(-0.30, 0.25, 0.65),
}

C.GasStations = {
  vec3(49.4187, 2778.793, 58.043), vec3(263.894, 2606.463, 44.983),
  vec3(1039.958, 2671.134, 39.550), vec3(1207.260, 2660.175, 37.899),
  vec3(2539.685, 2594.192, 37.944), vec3(2679.858, 3263.946, 55.240),
  vec3(2005.055, 3773.887, 32.403), vec3(1687.156, 4929.392, 42.078),
  vec3(1701.314, 6416.028, 32.763), vec3(179.857, 6602.839, 31.868),
  vec3(-94.4619, 6419.594, 31.489), vec3(-2554.996, 2334.40, 33.078),
  vec3(-1800.375, 803.661, 138.651), vec3(-1437.622, -276.747, 46.207),
  vec3(-2096.243, -320.286, 13.168), vec3(-724.619, -935.1631, 19.213),
  vec3(-526.019, -1211.003, 18.184), vec3(-70.2148, -1761.792, 29.534),
  vec3(265.648, -1261.309, 29.292), vec3(819.653, -1028.846, 26.403),
  vec3(1208.951, -1402.567, 35.224), vec3(1181.381, -330.847, 69.316),
  vec3(620.843, 269.100, 103.089), vec3(2581.321, 362.039, 108.468),
  vec3(176.631, -1562.025, 29.263), vec3(-319.292, -1471.715, 30.549),
  vec3(-66.48, -2532.57, 6.14), vec3(1784.324, 3330.55, 41.253),
}

C.ElectricStations = {
  vec3(153.4138, 6592.721, 30.8449), vec3(2697.205, 3277.662, 54.24057),
  vec3(-2534.736, 2345.22, 32.05991), vec3(645.1025, 280.3252, 102.1716),
  vec3(-729.0958, -911.1166, 18.01393),
}

VHubFuel.Config = C
