VOIDP = VOIDP or {}

RegisterNetEvent('engine:vehTuning')
AddEventHandler('engine:vehTuning', function()
    local vehicle = GetVehiclePedIsUsing(PlayerPedId())
    if not IsEntityAVehicle(vehicle) then return end

    local motor = GetVehicleMod(vehicle, 11)
    local freio = GetVehicleMod(vehicle, 12)
    local transmissao = GetVehicleMod(vehicle, 13)
    local suspensao = GetVehicleMod(vehicle, 15)
    local blindagem = GetVehicleMod(vehicle, 16)
    local body = GetVehicleBodyHealth(vehicle)
    local engine = GetVehicleEngineHealth(vehicle)
    local fuel = GetVehicleFuelLevel(vehicle)

    local function nivelTexto(valor, max)
        if valor == -1 then return 'Desativado' end
        return 'Nivel ' .. (valor + 1) .. ' / ' .. max
    end

    motor = nivelTexto(motor, GetNumVehicleMods(vehicle, 11))
    freio = nivelTexto(freio, GetNumVehicleMods(vehicle, 12))
    transmissao = nivelTexto(transmissao, GetNumVehicleMods(vehicle, 13))
    suspensao = nivelTexto(suspensao, GetNumVehicleMods(vehicle, 15))
    blindagem = nivelTexto(blindagem, GetNumVehicleMods(vehicle, 16))

    TriggerEvent('Notify', 'importante', '<b>Motor:</b> ' .. motor .. '<br><b>Freio:</b> ' .. freio .. '<br><b>Transmissao:</b> ' .. transmissao .. '<br><b>Suspensao:</b> ' .. suspensao .. '<br><b>Blindagem:</b> ' .. blindagem .. '<br><b>Chassi:</b> ' .. parseInt(body / 10) .. '%<br><b>Engine:</b> ' .. parseInt(engine / 10) .. '%<br><b>Gasolina:</b> ' .. parseInt(fuel) .. '%', 15000)
end)

RegisterNetEvent('Firecracker')
AddEventHandler('Firecracker', function()
    if not HasNamedPtfxAssetLoaded('scr_indep_fireworks') then
        RequestNamedPtfxAsset('scr_indep_fireworks')
        while not HasNamedPtfxAssetLoaded('scr_indep_fireworks') do
            RequestNamedPtfxAsset('scr_indep_fireworks')
            Wait(10)
        end
    end

    local mHash = GetHashKey('ind_prop_firework_03')
    RequestModel(mHash)
    while not HasModelLoaded(mHash) do
        RequestModel(mHash)
        Wait(10)
    end

    local explosives = 25
    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.6, 0.0)
    local firecracker = CreateObjectNoOffset(mHash, coords.x, coords.y, coords.z, true, false, false)
    PlaceObjectOnGroundProperly(firecracker)
    FreezeEntityPosition(firecracker, true)
    SetModelAsNoLongerNeeded(mHash)

    Wait(10000)

    repeat
        UseParticleFxAssetNextCall('scr_indep_fireworks')
        StartNetworkedParticleFxNonLoopedAtCoord('scr_indep_firework_trailburst', coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 2.5, false, false, false, false)
        explosives = explosives - 1
        Wait(2000)
    until explosives == 0

    TriggerServerEvent('tryDeleteEntity', ObjToNet(firecracker))
end)

RegisterNetEvent('cancelando')
AddEventHandler('cancelando', function(status)
    VOIDP.state.cancelando = status
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if VOIDP.state.cancelando then
            sleep = 5
            BlockWeaponWheelThisFrame()
            DisableControlAction(0, 29, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 47, true)
            DisableControlAction(0, 56, true)
            DisableControlAction(0, 57, true)
            DisableControlAction(0, 73, true)
            DisableControlAction(0, 137, true)
            DisableControlAction(0, 166, true)
            DisableControlAction(0, 167, true)
            DisableControlAction(0, 169, true)
            DisableControlAction(0, 170, true)
            DisableControlAction(0, 182, true)
            DisableControlAction(0, 187, true)
            DisableControlAction(0, 188, true)
            DisableControlAction(0, 189, true)
            DisableControlAction(0, 190, true)
            DisableControlAction(0, 243, true)
            DisableControlAction(0, 245, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 288, true)
            DisableControlAction(0, 289, true)
            DisableControlAction(0, 311, true)
            DisableControlAction(0, 344, true)
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('bandagem')
AddEventHandler('bandagem', function()
    local ped = PlayerPedId()
    local bandagem = 0
    repeat
        Wait(600)
        bandagem = bandagem + 1
        if GetEntityHealth(ped) > 101 then
            SetEntityHealth(ped, GetEntityHealth(ped) + 1)
        end
    until GetEntityHealth(ped) >= 400 or GetEntityHealth(ped) <= 101 or bandagem == 60
    TriggerEvent('Notify', 'sucesso', 'Tratamento concluido.')
end)

local tratamento = false
RegisterNetEvent('tratamento')
AddEventHandler('tratamento', function()
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    local armour = GetPedArmour(ped)

    SetEntityHealth(ped, health)
    SetPedArmour(ped, armour)

    if tratamento then return end
    tratamento = true
    TriggerEvent('Notify', 'sucesso', 'Tratamento iniciado, aguarde a liberacao do paramedico.', 8000)
    TriggerEvent('resetWarfarina')
    TriggerEvent('resetDiagnostic')

    repeat
        Wait(600)
        if GetEntityHealth(ped) > 101 then
            SetEntityHealth(ped, GetEntityHealth(ped) + 1)
        end
    until GetEntityHealth(ped) >= 400 or GetEntityHealth(ped) <= 101

    TriggerEvent('Notify', 'sucesso', 'Tratamento concluido.', 8000)
    tratamento = false
end)

RegisterNetEvent('void_mochila_prime:energetico')
AddEventHandler('void_mochila_prime:energetico', function(status, multiplier)
    VOIDP.state.energetico = status
    if status then
        SetRunSprintMultiplierForPlayer(PlayerId(), multiplier or 1.15)
    else
        SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if VOIDP.state.energetico then
            sleep = 5
            RestorePlayerStamina(PlayerId(), 1.0)
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('void_mochila_prime:consumirItem')
AddEventHandler('void_mochila_prime:consumirItem', function(item)
    local bebida = {
        cerveja = true,
        tequila = true,
        vodka = true,
        whisky = true,
        conhaque = true,
        absinto = true,
        energetico = true
    }

    if bebida[item] then
        TriggerEvent('cancelando', true)
        RequestAnimDict('amb@world_human_drinking@beer@male@idle_a')
        while not HasAnimDictLoaded('amb@world_human_drinking@beer@male@idle_a') do
            Wait(10)
        end
        TaskPlayAnim(PlayerPedId(), 'amb@world_human_drinking@beer@male@idle_a', 'idle_a', 8.0, -8.0, -1, 49, 0, false, false, false)
        TriggerEvent('progress', 10000, 'bebendo')
        Wait(10000)
        ClearPedTasks(PlayerPedId())
        StartScreenEffect('RaceTurbo', 180, false)
        StartScreenEffect('DrugsTrevorClownsFight', 180, false)
        TriggerEvent('cancelando', false)
        return
    end

    local drogas = {
        maconha = true,
        metanfetamina = true,
        cocaina = true
    }

    if drogas[item] then
        RequestAnimDict('mp_player_int_uppersmoke')
        while not HasAnimDictLoaded('mp_player_int_uppersmoke') do
            Wait(10)
        end
        TaskPlayAnim(PlayerPedId(), 'mp_player_int_uppersmoke', 'mp_player_int_smoke', 8.0, -8.0, -1, 49, 0, false, false, false)
        TriggerEvent('progress', 10000, 'fumando')
        Wait(10000)
        ClearPedTasks(PlayerPedId())
        StartScreenEffect('RaceTurbo', 180, false)
        StartScreenEffect('DrugsTrevorClownsFight', 180, false)
    end
end)

RegisterNetEvent('DisplayMe')
AddEventHandler('DisplayMe', function(text, source)
    local display = true
    local id = GetPlayerFromServerId(source)
    CreateThread(function()
        while display do
            Wait(1)
            local coordsMe = GetEntityCoords(GetPlayerPed(id), false)
            local coords = GetEntityCoords(PlayerPedId(), false)
            local distance = Vdist2(coordsMe, coords)
            if distance <= 30 then
                VOIDP.drawText3d(coordsMe.x, coordsMe.y, coordsMe.z + 0.10, text)
            end
        end
    end)
    Wait(7000)
    display = false
end)

RegisterNetEvent('DisplayRoll')
AddEventHandler('DisplayRoll', function(text, source)
    local display = true
    local id = GetPlayerFromServerId(source)
    CreateThread(function()
        while display do
            Wait(1)
            local coordsMe = GetEntityCoords(GetPlayerPed(id), false)
            local coords = GetEntityCoords(PlayerPedId(), false)
            local distance = Vdist2(coordsMe, coords)
            if distance <= 30 then
                VOIDP.drawText3d(coordsMe.x, coordsMe.y, coordsMe.z + 0.10, text)
            end
        end
    end)
    Wait(7000)
    display = false
end)

RegisterNetEvent('CartasMe')
AddEventHandler('CartasMe', function(id, name, cd, naipe)
    local card = {
        [1] = '^2A',
        [2] = '^41',
        [3] = '^42',
        [4] = '^43',
        [5] = '^44',
        [6] = '^45',
        [7] = '^46',
        [8] = '^47',
        [9] = '^48',
        [10] = '^49',
        [11] = '^1J',
        [12] = '^1Q',
        [13] = '^1K'
    }
    local tipos = {
        [1] = '^8<3',
        [2] = '^8<>',
        [3] = '^9^^',
        [4] = '^9vv'
    }

    local monid = PlayerId()
    local sonid = GetPlayerFromServerId(id)
    if sonid == monid then
        TriggerEvent('chatMessage', '', {}, '^3* ' .. name .. ' tirou do baralho a carta: ' .. (card[cd] or '') .. (tipos[naipe] or ''))
    elseif #(GetEntityCoords(GetPlayerPed(monid)) - GetEntityCoords(GetPlayerPed(sonid))) < 6.0 then
        TriggerEvent('chatMessage', '', {}, '^3* ' .. name .. ' tirou do baralho a carta: ' .. (card[cd] or '') .. (tipos[naipe] or ''))
    end
end)

local function setClothing(component, modelo, cor)
    local ped = PlayerPedId()
    if GetEntityHealth(ped) <= 101 then return end
    if VOIDP.vSERVER and VOIDP.vSERVER.checkRoupas and not VOIDP.vSERVER.checkRoupas() then return end

    if modelo == nil then
        SetPedComponentVariation(ped, component, 0, 0, 2)
        return
    end
    SetPedComponentVariation(ped, component, parseInt(modelo), parseInt(cor), 2)
end

RegisterNetEvent('setmascara')
AddEventHandler('setmascara', function(modelo, cor)
    if modelo == nil then
        vRP._playAnim(true, { { 'missfbi4', 'takeoff_mask' } }, false)
        Wait(1100)
        ClearPedTasks(PlayerPedId())
        SetPedComponentVariation(PlayerPedId(), 1, 0, 0, 2)
        return
    end
    vRP._playAnim(true, { { 'misscommon@van_put_on_masks', 'put_on_mask_ps' } }, false)
    Wait(1500)
    ClearPedTasks(PlayerPedId())
    setClothing(1, modelo, cor)
end)

RegisterNetEvent('setblusa')
AddEventHandler('setblusa', function(modelo, cor)
    setClothing(8, modelo, cor)
end)

RegisterNetEvent('setcolete')
AddEventHandler('setcolete', function(modelo, cor)
    setClothing(9, modelo, cor)
end)

RegisterNetEvent('setjaqueta')
AddEventHandler('setjaqueta', function(modelo, cor)
    setClothing(11, modelo, cor)
end)

RegisterNetEvent('setmaos')
AddEventHandler('setmaos', function(modelo, cor)
    setClothing(3, modelo, cor)
end)

RegisterNetEvent('setcalca')
AddEventHandler('setcalca', function(modelo, cor)
    setClothing(4, modelo, cor)
end)

RegisterNetEvent('setacessorios')
AddEventHandler('setacessorios', function(modelo, cor)
    setClothing(7, modelo, cor)
end)

RegisterNetEvent('setsapatos')
AddEventHandler('setsapatos', function(modelo, cor)
    setClothing(6, modelo, cor)
end)

RegisterNetEvent('setchapeu')
AddEventHandler('setchapeu', function(modelo, cor)
    local ped = PlayerPedId()
    if modelo == nil then
        ClearPedProp(ped, 0)
        return
    end
    SetPedPropIndex(ped, 0, parseInt(modelo), parseInt(cor), true)
end)

RegisterNetEvent('setoculos')
AddEventHandler('setoculos', function(modelo, cor)
    local ped = PlayerPedId()
    if modelo == nil then
        ClearPedProp(ped, 1)
        return
    end
    SetPedPropIndex(ped, 1, parseInt(modelo), parseInt(cor), true)
end)

return VOIDP

RegisterNetEvent('cmg2_animations:syncTarget')
AddEventHandler('cmg2_animations:syncTarget', function(target, animationLib, animation2, distans, distans2, height, length, spin, controlFlag)
    local playerPed = PlayerPedId()
    local targetPed = GetPlayerPed(GetPlayerFromServerId(target))
    RequestAnimDict(animationLib)
    while not HasAnimDictLoaded(animationLib) do
        Wait(10)
    end
    if spin == nil then spin = 180.0 end
    AttachEntityToEntity(playerPed, targetPed, 0, distans2, distans, height, 0.5, 0.5, spin, false, false, false, false, 2, false)
    TaskPlayAnim(playerPed, animationLib, animation2, 8.0, -8.0, length, controlFlag or 0, 0, false, false, false)
end)

RegisterNetEvent('cmg2_animations:syncMe')
AddEventHandler('cmg2_animations:syncMe', function(animationLib, animation, length, controlFlag)
    local playerPed = PlayerPedId()
    RequestAnimDict(animationLib)
    while not HasAnimDictLoaded(animationLib) do
        Wait(10)
    end
    TaskPlayAnim(playerPed, animationLib, animation, 8.0, -8.0, length, controlFlag or 0, 0, false, false, false)
    Wait(length)
end)

RegisterNetEvent('cmg2_animations:cl_stop')
AddEventHandler('cmg2_animations:cl_stop', function()
    ClearPedSecondaryTask(PlayerPedId())
    DetachEntity(PlayerPedId(), true, false)
end)
