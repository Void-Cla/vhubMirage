local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')

vRP = vRP or Proxy.getInterface('vRP')

local Config = module(GetCurrentResourceName(), 'config')

VOIDP = VOIDP or {}
VOIDP.cfg = Config.player or {}
VOIDP.vSERVER = VOIDP.vSERVER or Tunnel.getInterface('void_mochila_prime')
VOIDP.state = VOIDP.state or {
    cancelando = false,
    energetico = false,
    afk_tempo = (VOIDP.cfg.afk and VOIDP.cfg.afk.tempo_limite) or 1800,
    afk_px = 0.0,
    afk_py = 0.0,\n    crouched = false,
}

if VOIDP.cfg.habilitar == false then
    return VOIDP
end

local function aplicarHudEControle()
    local hudCfg = VOIDP.cfg.hud or {}
    if hudCfg.esconder_componentes then
        for _, id in ipairs(hudCfg.esconder_componentes) do
            HideHudComponentThisFrame(id)
        end
    end

    if hudCfg.desativar_wanted then
        SetMaxWantedLevel(0)
        ClearPlayerWantedLevel(PlayerId())
    end

    if hudCfg.ignorar_policia then
        SetEveryoneIgnorePlayer(PlayerPedId(), true)
        SetPlayerCanBeHassledByGangs(PlayerPedId(), false)
        SetIgnoreLowPriorityShockingEvents(PlayerPedId(), true)
        DisablePlayerVehicleRewards(PlayerId())
    end
end

local function aplicarDensidade()
    local dens = VOIDP.cfg.densidade or {}
    local ped = dens.ped or 0.5
    local scenario = dens.scenario or 0.5
    local parked = dens.parked or 0.5
    local vehicles = dens.vehicles or 0.5
    local random = dens.random or 0.5

    SetPedDensityMultiplierThisFrame(ped)
    SetScenarioPedDensityMultiplierThisFrame(scenario, scenario)
    SetParkedVehicleDensityMultiplierThisFrame(parked)
    SetRandomVehicleDensityMultiplierThisFrame(random)
    SetVehicleDensityMultiplierThisFrame(vehicles)
    SetGarbageTrucks(dens.garbage_trucks ~= false)
    SetRandomBoats(dens.random_boats ~= false)
end

local function aplicarDanoArmas()
    local armas = {
        'WEAPON_BAT',
        'WEAPON_BOTTLE',
        'WEAPON_HAMMER',
        'WEAPON_WRENCH',
        'WEAPON_UNARMED',
        'WEAPON_HATCHET',
        'WEAPON_CROWBAR',
        'WEAPON_MACHETE',
        'WEAPON_POOLCUE',
        'WEAPON_KNUCKLE',
        'WEAPON_GOLFCLUB',
        'WEAPON_BATTLEAXE',
        'WEAPON_FLASHLIGHT',
        'WEAPON_NIGHTSTICK',
        'WEAPON_STONE_HATCHET'
    }

    for _, arma in ipairs(armas) do
        N_0x4757f00bc6323cfe(arma, 0.1)
    end

    RemoveAllPickupsOfType('PICKUP_WEAPON_KNIFE')
    RemoveAllPickupsOfType('PICKUP_WEAPON_PISTOL')
    RemoveAllPickupsOfType('PICKUP_WEAPON_MINISMG')
    RemoveAllPickupsOfType('PICKUP_WEAPON_MICROSMG')
    RemoveAllPickupsOfType('PICKUP_WEAPON_PUMPSHOTGUN')
    RemoveAllPickupsOfType('PICKUP_WEAPON_CARBINERIFLE')
    RemoveAllPickupsOfType('PICKUP_WEAPON_SAWNOFFSHOTGUN')
end

local function aplicarPlacas()
    local placas = VOIDP.cfg.placas or {}
    if not placas.habilitar then return end

    local textureDic = CreateRuntimeTxd('duiTxd')
    local object = CreateDui(placas.imagem_url, placas.largura or 540, placas.altura or 300)
    local handle = GetDuiHandle(object)
    CreateRuntimeTextureFromDuiHandle(textureDic, 'duiTex', handle)
    AddReplaceTexture('vehshare', 'plate01', 'duiTxd', 'duiTex')
    AddReplaceTexture('vehshare', 'plate02', 'duiTxd', 'duiTex')
    AddReplaceTexture('vehshare', 'plate03', 'duiTxd', 'duiTex')
    AddReplaceTexture('vehshare', 'plate04', 'duiTxd', 'duiTex')
    AddReplaceTexture('vehshare', 'plate05', 'duiTxd', 'duiTex')

    local object2 = CreateDui(placas.modelo_url, placas.largura or 540, placas.altura or 300)
    local handle2 = GetDuiHandle(object2)
    CreateRuntimeTextureFromDuiHandle(textureDic, 'duiTex2', handle2)
    AddReplaceTexture('vehshare', 'plate01_n', 'duiTxd', 'duiTex2')
    AddReplaceTexture('vehshare', 'plate02_n', 'duiTxd', 'duiTex2')
    AddReplaceTexture('vehshare', 'plate03_n', 'duiTxd', 'duiTex2')
    AddReplaceTexture('vehshare', 'plate04_n', 'duiTxd', 'duiTex2')
    AddReplaceTexture('vehshare', 'plate05_n', 'duiTxd', 'duiTex2')
end

CreateThread(function()
    aplicarPlacas()
end)

CreateThread(function()
    while true do
        aplicarDanoArmas()
        aplicarHudEControle()
        aplicarDensidade()
        Wait(0)
    end
end)

CreateThread(function()
    if VOIDP.cfg.stamina and VOIDP.cfg.stamina.infinito then
        while true do
            Wait(VOIDP.cfg.stamina.intervalo_ms or 4000)
            RestorePlayerStamina(PlayerId(), 1.0)
        end
    end
end)

CreateThread(function()
    StartAudioScene('CHARACTER_CHANGE_IN_SKY_SCENE')
    SetAudioFlag('PoliceScannerDisabled', true)
end)

CreateThread(function()
    if VOIDP.cfg.afk and VOIDP.cfg.afk.habilitar then
        while true do
            Wait(1000)
            local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
            if x == VOIDP.state.afk_px and y == VOIDP.state.afk_py then
                if VOIDP.state.afk_tempo > 0 then
                    VOIDP.state.afk_tempo = VOIDP.state.afk_tempo - 1
                    if VOIDP.state.afk_tempo == (VOIDP.cfg.afk.aviso_segundos or 60) then
                        TriggerEvent('Notify', 'importante', 'Voce sera desconectado em 60 segundos.')
                    end
                else
                    TriggerServerEvent('kickAFK')
                end
            else
                VOIDP.state.afk_tempo = VOIDP.cfg.afk.tempo_limite or 1800
            end
            VOIDP.state.afk_px = x
            VOIDP.state.afk_py = y
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if DoesEntityExist(GetVehiclePedIsTryingToEnter(PlayerPedId())) then
            sleep = 5
            local veh = GetVehiclePedIsTryingToEnter(PlayerPedId())
            if GetVehicleDoorLockStatus(veh) >= 2 or GetPedInVehicleSeat(veh, -1) then
                TriggerServerEvent('TryDoorsEveryone', veh, 2, GetVehicleNumberPlateText(veh))
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    RequestAnimDict('facials@gen_male@variations@normal')
    RequestAnimDict('mp_facial')

    local talkingPlayers = {}
    while true do
        Wait(300)
        for _, player in ipairs(VOIDP.getPlayers and VOIDP.getPlayers() or {}) do
            local boolTalking = NetworkIsPlayerTalking(player)
            if player ~= PlayerId() then
                if boolTalking and not talkingPlayers[player] then
                    PlayFacialAnim(GetPlayerPed(player), 'mic_chatter', 'mp_facial')
                    talkingPlayers[player] = true
                elseif not boolTalking and talkingPlayers[player] then
                    PlayFacialAnim(GetPlayerPed(player), 'mood_normal_1', 'facials@gen_male@variations@normal')
                    talkingPlayers[player] = nil
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        local isweapon, hash = GetCurrentPedWeapon(PlayerPedId(), true)
        local weapongroup = GetWeapontypeGroup(hash)
        if isweapon and weapongroup ~= -728555052 then
            sleep = 5
            SetPlayerLockon(PlayerId(), false)
        else
            SetPlayerLockon(PlayerId(), true)
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local handle, ped = FindFirstPed()
        local finished = false
        repeat
            if not IsEntityDead(ped) then
                SetPedDropsWeaponsWhenDead(ped, false)
            end
            finished, ped = FindNextPed(handle)
        until not finished
        EndFindPed(handle)
    end
end)

return VOIDP

