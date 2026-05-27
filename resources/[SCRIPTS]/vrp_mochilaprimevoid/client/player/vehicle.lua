VOIDP = VOIDP or {}

local function getVehicleInDirection(coordFrom, coordTo)
    local rayHandle = StartShapeTestRay(coordFrom.x, coordFrom.y, coordFrom.z, coordTo.x, coordTo.y, coordTo.z, 10, PlayerPedId(), 0)
    local _, _, _, _, vehicle = GetShapeTestResult(rayHandle)
    if IsEntityAVehicle(vehicle) then
        return vehicle
    end
    return nil
end

VOIDP.getVehicleInDirection = getVehicleInDirection

RegisterNetEvent('synctrunk')
AddEventHandler('synctrunk', function(index)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToVeh(index)
        local isopen = GetVehicleDoorAngleRatio(v, 5)
        if DoesEntityExist(v) and IsEntityAVehicle(v) then
            if isopen == 0 then
                SetVehicleDoorOpen(v, 5, 0, 0)
            else
                SetVehicleDoorShut(v, 5, 0)
            end
        end
    end
end)

RegisterNetEvent('void_mochila_prime:trunkState')
AddEventHandler('void_mochila_prime:trunkState', function(index, abrir)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToVeh(index)
        if DoesEntityExist(v) and IsEntityAVehicle(v) then
            if abrir then
                SetVehicleDoorOpen(v, 5, false, false)
            else
                SetVehicleDoorShut(v, 5, false)
            end
        end
    end
end)

RegisterNetEvent('synchood')
AddEventHandler('synchood', function(index)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToVeh(index)
        local isopen = GetVehicleDoorAngleRatio(v, 4)
        if DoesEntityExist(v) and IsEntityAVehicle(v) then
            if isopen == 0 then
                SetVehicleDoorOpen(v, 4, 0, 0)
            else
                SetVehicleDoorShut(v, 4, 0)
            end
        end
    end
end)

RegisterNetEvent('syncwins')
AddEventHandler('syncwins', function(index)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToVeh(index)
        if DoesEntityExist(v) and IsEntityAVehicle(v) then
            if not IsVehicleWindowIntact(v, 0) then
                RollUpWindow(v, 0)
                RollUpWindow(v, 1)
                RollUpWindow(v, 2)
                RollUpWindow(v, 3)
            else
                RollDownWindow(v, 0)
                RollDownWindow(v, 1)
                RollDownWindow(v, 2)
                RollDownWindow(v, 3)
            end
        end
    end
end)

RegisterNetEvent('syncdoors')
AddEventHandler('syncdoors', function(index, door)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToVeh(index)
        if DoesEntityExist(v) and IsEntityAVehicle(v) then
            if GetVehicleDoorAngleRatio(v, door) == 0 then
                SetVehicleDoorOpen(v, door, false, false)
            else
                SetVehicleDoorShut(v, door, false)
            end
        end
    end
end)

RegisterNetEvent('synctow')
AddEventHandler('synctow', function(vehid, rebid)
    if NetworkDoesNetworkIdExist(vehid) and NetworkDoesNetworkIdExist(rebid) then
        local vehicle = NetToVeh(vehid)
        local rebocado = NetToVeh(rebid)
        if DoesEntityExist(vehicle) and DoesEntityExist(rebocado) then
            if not VOIDP.reboque then
                if vehicle ~= rebocado then
                    local min = GetModelDimensions(GetEntityModel(rebocado))
                    AttachEntityToEntity(rebocado, vehicle, GetEntityBoneIndexByName(vehicle, 'bodyshell'), 0, -2.2, 0.4 - min.z, 0, 0, 0, true, true, false, true, 0, true)
                    VOIDP.reboque = rebocado
                end
            else
                AttachEntityToEntity(VOIDP.reboque, vehicle, 20, -0.5, -13.0, -0.3, 0.0, 0.0, 0.0, false, false, true, false, 20, true)
                DetachEntity(VOIDP.reboque, false, false)
                PlaceObjectOnGroundProperly(VOIDP.reboque)
                VOIDP.reboque = nil
            end
        end
    end
end)

RegisterNetEvent('repararpneus')
AddEventHandler('repararpneus', function(vehicle)
    SetVehicleTyreFixed(vehicle, 1)
    SetVehicleTyreFixed(vehicle, 2)
    SetVehicleTyreFixed(vehicle, 3)
    SetVehicleTyreFixed(vehicle, 4)
end)

RegisterNetEvent('reparar')
AddEventHandler('reparar', function()
    local vehicle = vRP.getNearestVehicle(3)
    if IsEntityAVehicle(vehicle) then
        TriggerServerEvent('tryreparar', VehToNet(vehicle))
    end
end)

RegisterNetEvent('syncreparar')
AddEventHandler('syncreparar', function(index)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToVeh(index)
        local fuel = GetVehicleFuelLevel(v)
        if DoesEntityExist(v) and IsEntityAVehicle(v) then
            SetVehicleFixed(v)
            SetVehicleDirtLevel(v, 0.0)
            SetVehicleUndriveable(v, false)
            SetVehicleOnGroundProperly(v)
            SetVehicleFuelLevel(v, fuel)
        end
    end
end)

RegisterNetEvent('repararmotor')
AddEventHandler('repararmotor', function()
    local vehicle = vRP.getNearestVehicle(3)
    if IsEntityAVehicle(vehicle) then
        TriggerServerEvent('trymotor', VehToNet(vehicle))
    end
end)

RegisterNetEvent('syncmotor')
AddEventHandler('syncmotor', function(index)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToVeh(index)
        if DoesEntityExist(v) and IsEntityAVehicle(v) then
            SetVehicleEngineHealth(v, 1000.0)
        end
    end
end)

return VOIDP

RegisterNetEvent('syncLock')
AddEventHandler('syncLock', function(index)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToVeh(index)
        if DoesEntityExist(v) and IsEntityAVehicle(v) then
            local lock = GetVehicleDoorLockStatus(v)
            if lock == 1 then
                SetVehicleDoorsLocked(v, 2)
            else
                SetVehicleDoorsLocked(v, 1)
            end
        end
    end
end)

RegisterNetEvent('SyncDoorsEveryone')
AddEventHandler('SyncDoorsEveryone', function(veh, doors)
    if DoesEntityExist(veh) then
        SetVehicleDoorsLocked(veh, doors)
    end
end)
