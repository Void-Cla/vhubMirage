local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')

vRP = vRP or Proxy.getInterface('vRP')

VOIDP = VOIDP or {}
VOIDP.vSERVER = VOIDP.vSERVER or Tunnel.getInterface('void_mochila_prime')

local function serverInterface()
    return VOIDP.vSERVER or vSERVER
end

RegisterCommand('agachar2', function()
    local ped = PlayerPedId()
    DisableControlAction(0, 36, true)
    if not IsPedInAnyVehicle(ped) then
        RequestAnimSet('move_ped_crouched')
        RequestAnimSet('move_ped_crouched_strafing')
        while not HasAnimSetLoaded('move_ped_crouched') do
            Wait(10)
        end
        if VOIDP.state.crouched then
            ResetPedStrafeClipset(ped)
            ResetPedMovementClipset(ped, 0.25)
            VOIDP.state.crouched = false
        else
            SetPedStrafeClipset(ped, 'move_ped_crouched_strafing')
            SetPedMovementClipset(ped, 'move_ped_crouched', 0.25)
            VOIDP.state.crouched = true
        end
    end
end)

RegisterKeyMapping('agachar2', 'Agachar', 'keyboard', 'LCONTROL')

RegisterCommand('fps', function(_, args)
    if args[1] == 'on' then
        SetTimecycleModifier('cinema')
        TriggerEvent('Notify', 'sucesso', 'Boost de fps ligado!')
    elseif args[1] == 'off' then
        SetTimecycleModifier('default')
        TriggerEvent('Notify', 'sucesso', 'Boost de fps desligado!')
    end
end)

local graficoAtivo = false
RegisterCommand('graficos', function()
    graficoAtivo = not graficoAtivo
    if graficoAtivo then
        SetTimecycleModifier('MP_Powerplay_blend')
        SetExtraTimecycleModifier('reflection_correct_ambient')
    else
        ClearTimecycleModifier()
        ClearExtraTimecycleModifier()
    end
end)

RegisterCommand('attachs', function()
    local ped = PlayerPedId()
    local weapon = GetSelectedPedWeapon(ped)

    if weapon == GetHashKey('WEAPON_COMBATPISTOL') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_PI_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_COMBATPISTOL_CLIP_02'))
    elseif weapon == GetHashKey('WEAPON_SMG') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SCOPE_MACRO_02'))
    elseif weapon == GetHashKey('WEAPON_COMBATPDW') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SCOPE_SMALL'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_AFGRIP'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_COMBATPDW_CLIP_03P'))
    elseif weapon == GetHashKey('WEAPON_PUMPSHOTGUN_MK2') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SIGHTS'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SCOPE_SMALL_MK2'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_PUMPSHOTGUN_MK2_CLIP_ARMORPIERCING'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_MUZZLE_08'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_PUMPSHOTGUN_MK2_CAMO_10'))
    elseif weapon == GetHashKey('WEAPON_CARBINERIFLE') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_AFGRIP'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SCOPE_MEDIUM'))
    elseif weapon == GetHashKey('WEAPON_TACTICALRIFLE') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_AFGRIP'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SCOPE_MEDIUM'))
    elseif weapon == GetHashKey('WEAPON_MICROSMG') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_PI_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SCOPE_MACRO'))
    elseif weapon == GetHashKey('WEAPON_ASSAULTRIFLE') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SCOPE_MACRO'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_AFGRIP'))
    elseif weapon == GetHashKey('WEAPON_ASSAULTRIFLE_MK2') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_FLSH'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_SCOPE_MEDIUM_MK2'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_AR_AFGRIP_02'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_ASSAULTRIFLE_MK2_CLIP_02'))
    elseif weapon == GetHashKey('WEAPON_PISTOL_MK2') then
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_PI_RAIL'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_PI_FLSH_02'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_PISTOL_MK2_CLIP_02'))
        GiveWeaponComponentToPed(ped, weapon, GetHashKey('COMPONENT_AT_PI_SUPP_02'))
    end
end)

RegisterCommand('trunk', function()
    local vehicle = vRP.getNearestVehicle(7)
    if IsEntityAVehicle(vehicle) then
        TriggerEvent('Notify', 'aviso', 'Use o comando menucarro ou pressione f12 para ter acesso ao comando.')
    end
end)

RegisterCommand('capo', function()
    local vehicle = vRP.getNearestVehicle(7)
    if IsEntityAVehicle(vehicle) then
        TriggerEvent('Notify', 'aviso', 'Use o comando menucarro ou pressione f12 para ter acesso ao comando.')
    end
end)

RegisterCommand('descervidro', function()
    local vehicle = vRP.getNearestVehicle(7)
    if IsEntityAVehicle(vehicle) then
        TriggerServerEvent('trywins', VehToNet(vehicle))
    end
end)

RegisterNetEvent('vehmenu:doors')
AddEventHandler('vehmenu:doors', function(index)
    local vehicle = vRP.getNearestVehicle(7)
    if IsEntityAVehicle(vehicle) then
        if parseInt(index) == 5 then
            TriggerServerEvent('trytrunk', VehToNet(vehicle))
        else
            TriggerServerEvent('trydoors', VehToNet(vehicle), index)
        end
    end
end)

RegisterCommand('portas', function()
    local vehicle = vRP.getNearestVehicle(7)
    if IsEntityAVehicle(vehicle) then
        TriggerEvent('Notify', 'aviso', 'Use o comando menucarro ou pressione f12 para ter acesso ao comando.')
    end
end)

RegisterCommand('roll', function(_, args)
    local rolls = tonumber(args[1]) or 1
    local die = tonumber(args[2]) or 6
    local number = 0
    local text = 'Resultado: '
    for _ = rolls, 1, -1 do
        number = number + math.random(1, die)
        text = text .. ' ~g~' .. number .. ' ~w~/ ~g~' .. die
    end
    vRP._playAnim(true, { { 'anim@mp_player_intcelebrationmale@wank', 'wank' } }, false)
    Wait(1500)
    TriggerServerEvent('ChatRoll', text)
    ClearPedTasks(PlayerId())
end)

RegisterCommand('me', function(_, args)
    local text = table.concat(args, ' ')
    if text ~= '' then
        TriggerServerEvent('ChatMe', text)
    end
end)

RegisterCommand('tow', function()
    local vehicle = GetPlayersLastVehicle()
    local vehicletow = IsVehicleModel(vehicle, GetHashKey('flatbed'))

    if vehicletow and not IsPedInAnyVehicle(PlayerPedId()) then
        local rebocado = VOIDP.getVehicleInDirection(GetEntityCoords(PlayerPedId()), GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 5.0, 0.0))
        if IsEntityAVehicle(vehicle) and IsEntityAVehicle(rebocado) then
            TriggerServerEvent('trytow', VehToNet(vehicle), VehToNet(rebocado))
        end
    end
end)

RegisterCommand('seat', function(_, args)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsUsing(ped)
    if IsEntityAVehicle(vehicle) and IsPedInAnyVehicle(ped) then
        local seat = -1
        local slot = parseInt(args[1])
        if slot == 1 then seat = -1
        elseif slot == 2 then seat = 0
        elseif slot == 3 then seat = 1
        elseif slot == 4 then seat = 2
        elseif slot == 5 then seat = 3
        elseif slot == 6 then seat = 4
        elseif slot == 7 then seat = 5
        elseif slot >= 8 then seat = 6
        end
        if IsVehicleSeatFree(vehicle, seat) then
            SetPedIntoVehicle(ped, vehicle, seat)
        end
    end
end)

RegisterCommand('carregar', function()
    if VOIDP.carryingBackInProgress then
        VOIDP.carryingBackInProgress = false
        ClearPedSecondaryTask(PlayerPedId())
        DetachEntity(PlayerPedId(), true, false)
        local closestPlayer = VOIDP.getClosestPlayer(3)
        if closestPlayer then
            local target = GetPlayerServerId(closestPlayer)
            TriggerServerEvent('cmg2_animations:stop', target)
        end
        return
    end

    VOIDP.carryingBackInProgress = true
    local closestPlayer = VOIDP.getClosestPlayer(3)
    if closestPlayer then
        local target = GetPlayerServerId(closestPlayer)
        TriggerServerEvent('cmg2_animations:sync', closestPlayer, 'missfinale_c2mcs_1', 'nm', 'fin_c2_mcs_1_camman', 'firemans_carry', 0.15, 0.27, 0.63, target, 100000, 0.0, 49, 33, 1)
    end
end, false)

RegisterCommand('cavalinho', function()
    if VOIDP.piggyBackInProgress then
        VOIDP.piggyBackInProgress = false
        ClearPedSecondaryTask(PlayerPedId())
        DetachEntity(PlayerPedId(), true, false)
        local closestPlayer = VOIDP.getClosestPlayer(3)
        if closestPlayer then
            local target = GetPlayerServerId(closestPlayer)
            TriggerServerEvent('cmg2_animations:stop', target)
        end
        return
    end

    VOIDP.piggyBackInProgress = true
    local closestPlayer = VOIDP.getClosestPlayer(3)
    if closestPlayer then
        local target = GetPlayerServerId(closestPlayer)
        TriggerServerEvent('cmg2_animations:sync', closestPlayer, 'anim@arena@celeb@flat@paired@no_props@', nil, 'piggyback_c_player_a', 'piggyback_c_player_b', -0.07, 0.0, 0.45, target, 100000, 0.0, 49, 33, 1)
    end
end, false)

RegisterCommand('carregarnpc', function()
    local ped = PlayerPedId()
    local randomico, npcs = FindFirstPed()\n    local success = true\n    repeat
        local distancia = GetDistanceBetweenCoords(GetEntityCoords(ped), GetEntityCoords(npcs), true)
        if not IsPedAPlayer(npcs) and distancia <= 3 and not IsPedInAnyVehicle(ped) and not IsPedInAnyVehicle(npcs) then
            if VOIDP.carregado then
                ClearPedTasksImmediately(VOIDP.carregado)
                DetachEntity(VOIDP.carregado, true, true)
                TaskWanderStandard(VOIDP.carregado, 10.0, 10)
                VOIDP.carregado = false
            else
                AttachEntityToEntity(npcs, ped, 4103, 11816, 0.48, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 2, true)
                VOIDP.carregado = npcs
            end
        end
        success, npcs = FindNextPed(randomico)
    until not success
    EndFindPed(randomico)
end)

RegisterCommand('sequestro2', function()
    local ped = PlayerPedId()
    local random, npc = FindFirstPed()\n    local complete = true\n    repeat
        local distancia = GetDistanceBetweenCoords(GetEntityCoords(ped), GetEntityCoords(npc), true)
        if not IsPedAPlayer(npc) and distancia <= 3 and not IsPedInAnyVehicle(npc) then
            local vehicle = vRP.getNearestVehicle(7)
            if IsEntityAVehicle(vehicle) and vRP.getCarroClass(vehicle) then
                if VOIDP.sequestrado then
                    AttachEntityToEntity(VOIDP.sequestrado, vehicle, GetEntityBoneIndexByName(vehicle, 'bumper_r'), 0.6, -1.2, -0.6, 60.0, -90.0, 180.0, false, false, false, true, 2, true)
                    DetachEntity(VOIDP.sequestrado, true, true)
                    ClearPedTasksImmediately(VOIDP.sequestrado)
                    VOIDP.sequestrado = nil
                else
                    AttachEntityToEntity(npc, vehicle, GetEntityBoneIndexByName(vehicle, 'bumper_r'), 0.6, -0.4, -0.1, 60.0, -90.0, 180.0, false, false, false, true, 2, true)
                    VOIDP.sequestrado = npc
                end
                TriggerServerEvent('trymala', VehToNet(vehicle))
            end
        end
        complete, npc = FindNextPed(random)
    until not complete
    EndFindPed(random)
end)

RegisterCommand('cor', function(_, args)
    local tinta = tonumber(args[1])
    local ped = PlayerPedId()
    local arma = GetSelectedPedWeapon(ped)
    if tinta and tinta >= 0 then
        SetPedWeaponTintIndex(ped, arma, tinta)
    end
end, false)

local temporizador = 0
local IsTiming = 0

RegisterCommand('garmas', function()
    if temporizador == 0 then
        local server = serverInterface()
        if server and server.getGarmas and server.getGarmas() == true then
            temporizador = 10
            local retval = GetPlayerServerId(NetworkGetPlayerIndexFromPed(PlayerPedId()))
            TriggerServerEvent('suricato:source:register', retval)
            IsTiming = 14
            TriggerEvent('progress', 4 * 1000, 'Guardando')
            SetTimeout(4000, function()
                TriggerServerEvent('garmas:suricato')
            end)
        else
            TriggerEvent('Notify', 'negado', 'Aguarde para usar /garmas novamente.')
        end
    else
        TriggerEvent('Notify', 'negado', 'Aguarde ' .. temporizador .. ' para usar /garmas novamente.')
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if temporizador > 0 then
            temporizador = temporizador - 1
        end
        if IsTiming > 0 then
            IsTiming = IsTiming - 1
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if IsTiming > 2 then
            sleep = 5
            local ui = VOIDP.getMinimapAnchor()
            VOIDP.drawTxts(ui.right_x + 0.150, ui.bottom_y - 0.176, 1.0, 1.0, 0.65, 'SE VOCE SAIR DO SERVIDOR, SERA BANIDO', 255, 255, 255, 150)
        elseif IsTiming == 2 or IsTiming == 1 then
            sleep = 5
            local ui = VOIDP.getMinimapAnchor()
            VOIDP.drawTxts(ui.right_x + 0.150, ui.bottom_y - 0.176, 1.0, 1.0, 0.65, 'PRONTO, SINTA-SE LIVRE PARA FAZER O QUE QUISER', 255, 255, 255, 150)
        end
        Wait(sleep)
    end
end)

return VOIDP

