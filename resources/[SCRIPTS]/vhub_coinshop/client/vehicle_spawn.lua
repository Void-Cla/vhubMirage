-- client/vehicle_spawn.lua — spawn de veículo comprado (cliente autoritativo; servidor já registrou no conce)

VHubCoin = VHubCoin or {}
local VehicleSpawn = {}
VHubCoin.VehicleSpawn = VehicleSpawn


-- spawna veículo comprado: modelo + placa já registrada no conce (server-side)
function VehicleSpawn.spawnPurchased(modelName, plate)
    if not VHubCoin.isNonEmptyStr(modelName) or not VHubCoin.isNonEmptyStr(plate) then
        TriggerEvent('chat:addMessage', { args = { '[Coinshop]', T('failed_spawn_vehicle') } })
        return
    end

    local ped     = PlayerPedId()
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local forward = GetEntityForwardVector(ped)
    local spawnCoords = coords + forward * VHubCoin.cfg.testDriveSpawnDistance

    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash)

    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 50 do
        Wait(100)
        attempts = attempts + 1
    end
    if not HasModelLoaded(modelHash) then
        TriggerEvent('chat:addMessage', { args = { '[Coinshop]', T('failed_spawn_vehicle') } })
        return
    end

    local vehicle = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, false)
    SetModelAsNoLongerNeeded(modelHash)
    SetVehicleNumberPlateText(vehicle, plate)
    TaskWarpPedIntoVehicle(ped, vehicle, -1)
    SetEntityAsMissionEntity(vehicle, true, true)

    -- tenta dar chaves via vhub_garage se disponível (contrato canônico)
    pcall(function()
        if exports.vhub_garage and exports.vhub_garage.giveKeys then
            exports.vhub_garage:giveKeys(plate)
        end
    end)

    TriggerEvent('chat:addMessage', { args = { '[Coinshop]', T('vehicle_purchased', plate) } })
end

