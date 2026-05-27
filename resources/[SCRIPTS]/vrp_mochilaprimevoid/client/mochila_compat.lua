local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')

vRP = Proxy.getInterface('vRP')

local MochilaCompat = {}
Tunnel.bindInterface('void_mochila', MochilaCompat)

local blockButtons = false
local registerCoords = {}

local plateX = -1133.31
local plateY = 2694.2
local plateZ = 18.81

local fishingX = -1306.9
local fishingY = 5823.34
local fishingZ = 2.31

RegisterNetEvent('void_mochila:Close')
AddEventHandler('void_mochila:Close', function()
    if VOIDC and VOIDC.fechar then
        VOIDC.fechar()
    end
end)

function MochilaCompat.plateDistance()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped) then
        local vehicle = GetVehiclePedIsUsing(ped)
        if GetPedInVehicleSeat(vehicle, -1) == ped then
            local x, y, z = table.unpack(GetEntityCoords(ped))
            local distance = GetDistanceBetweenCoords(x, y, z, plateX, plateY, plateZ, true)
            if distance <= 3.0 then
                FreezeEntityPosition(GetVehiclePedIsUsing(ped), true)
                return true
            end
        end
    end
    return false
end

function MochilaCompat.plateApply(plate)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsUsing(ped)
    if IsEntityAVehicle(vehicle) then
        SetVehicleNumberPlateText(vehicle, plate)
        FreezeEntityPosition(vehicle, false)
    end
end

function MochilaCompat.repairVehicle(index, status)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToEnt(index)
        if DoesEntityExist(v) then
            SetEntityAsMissionEntity(v, true, true)
            local fuel = GetVehicleFuelLevel(v)
            if status then
                SetVehicleFixed(v)
                SetVehicleFuelLevel(v, fuel)
                SetVehicleDeformationFixed(v)
                SetVehicleUndriveable(v, false)
            else
                SetVehicleEngineHealth(v, 1000.0)
                SetVehicleBodyHealth(v, 1000.0)
                SetVehicleFuelLevel(v, fuel)
            end
        end
    end
end

function MochilaCompat.repairTires(index)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToEnt(index)
        if DoesEntityExist(v) then
            for i = 0, 8 do
                SetVehicleTyreFixed(v, i)
            end
        end
    end
end

function MochilaCompat.lockpickVehicle(index)
    if NetworkDoesNetworkIdExist(index) then
        local v = NetToEnt(index)
        if DoesEntityExist(v) then
            SetEntityAsMissionEntity(v, true, true)
            if GetVehicleDoorsLockedForPlayer(v, PlayerId()) == 1 then
                SetVehicleDoorsLocked(v, false)
                SetVehicleDoorsLockedForAllPlayers(v, false)
            else
                SetVehicleDoorsLocked(v, true)
                SetVehicleDoorsLockedForAllPlayers(v, true)
            end
            SetVehicleLights(v, 2)
            Wait(200)
            SetVehicleLights(v, 0)
            Wait(200)
            SetVehicleLights(v, 2)
            Wait(200)
            SetVehicleLights(v, 0)
        end
    end
end

function MochilaCompat.blockButtons(status)
    blockButtons = status == true
end

CreateThread(function()
    while true do
        local time = 500
        if blockButtons then
            time = 4
            BlockWeaponWheelThisFrame()
            DisableControlAction(0, 56, true)
            DisableControlAction(0, 57, true)
            DisableControlAction(0, 73, true)
            DisableControlAction(0, 29, true)
            DisableControlAction(0, 47, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 20, true)
            DisableControlAction(0, 288, true)
            DisableControlAction(0, 289, true)
            DisableControlAction(0, 105, true)
            DisableControlAction(0, 170, true)
            DisableControlAction(0, 187, true)
            DisableControlAction(0, 189, true)
            DisableControlAction(0, 190, true)
            DisableControlAction(0, 188, true)
            DisableControlAction(0, 327, true)
            DisableControlAction(0, 311, true)
            DisableControlAction(0, 344, true)
            DisableControlAction(0, 182, true)
            DisableControlAction(0, 245, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 243, true)
        end
        Wait(time)
    end
end)

function MochilaCompat.parachuteColors()
    GiveWeaponToPed(PlayerPedId(), 'GADGET_PARACHUTE', 1, false, true)
    SetPedParachuteTintIndex(PlayerPedId(), math.random(7))
end

function MochilaCompat.checkObjects(prop)
    local ped = PlayerPedId()
    local x, y, z = table.unpack(GetEntityCoords(ped))
    if DoesObjectOfTypeExistAtCoords(x, y, z, 0.7, GetHashKey(prop), true) then
        return true
    end
    return false
end

function MochilaCompat.checkFountain()
    local ped = PlayerPedId()
    local x, y, z = table.unpack(GetEntityCoords(ped))
    if DoesObjectOfTypeExistAtCoords(x, y, z, 0.7, GetHashKey('prop_watercooler'), true) or DoesObjectOfTypeExistAtCoords(x, y, z, 0.7, GetHashKey('prop_watercooler_dark'), true) then
        return true, 'fountain'
    end
    return false
end

function MochilaCompat.cashRegister()
    local ped = PlayerPedId()
    local x, y, z = table.unpack(GetEntityCoords(ped))

    for _, v in pairs(registerCoords) do
        local distance = GetDistanceBetweenCoords(x, y, z, v[1], v[2], v[3], true)
        if distance <= 1 then
            return false, v[1], v[2], v[3]
        end
    end

    local object = GetClosestObjectOfType(x, y, z, 0.4, GetHashKey('prop_till_01'), 0, 0, 0)
    if DoesEntityExist(object) then
        local x2, y2, z2 = table.unpack(GetEntityCoords(object))
        SetEntityHeading(ped, GetEntityHeading(object) - 360.0)
        SetPedComponentVariation(ped, 5, 45, 0, 2)
        return true, x2, y2, z2
    end

    return false
end

function MochilaCompat.updateRegister(status)
    registerCoords = status
end

function MochilaCompat.fishingStatus()
    local ped = PlayerPedId()
    local x, y, z = table.unpack(GetEntityCoords(ped))
    local distance = GetDistanceBetweenCoords(x, y, z, fishingX, fishingY, fishingZ, true)
    return distance <= 400
end

function MochilaCompat.fishingAnim()
    local ped = PlayerPedId()
    if IsEntityPlayingAnim(ped, 'amb@world_human_stand_fishing@idle_a', 'idle_c', 3) then
        return true
    end
    return false
end

function MochilaCompat.startFrequency(frequency)
    if exports and exports.tokovoip_script and exports.tokovoip_script.addPlayerToRadio then
        TriggerEvent('radio:outServers')
        exports.tokovoip_script:addPlayerToRadio(frequency)
    end
end

RegisterNetEvent('recarregar:animacao')
AddEventHandler('recarregar:animacao', function()
    TaskReloadWeapon(PlayerPedId())
end)


