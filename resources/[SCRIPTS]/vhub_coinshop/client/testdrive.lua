-- client/testdrive.lua — test-drive de veículo (efêmero, routing bucket, teleport via owner do ped)

VHubCoin = VHubCoin or {}
local Client = VHubCoin.Client
local TestDrive = {}
VHubCoin.TestDrive = TestDrive


-- state local efêmero (servidor decide verdade — L-02)
TestDrive.active         = false
TestDrive.vehicle        = nil
TestDrive._timeoutThread = nil


-- ============================================================
-- PEDIR TEST-DRIVE — cliente envia intenção; servidor pode validar/rate
-- ============================================================

-- solicita test-drive do item (vehicle); recebe { ok, message }
function TestDrive.request(data)
    if TestDrive.active then
        return { ok = false, err = T('test_drive_already_active') }
    end
    if type(data) ~= 'table' or not VHubCoin.isNonEmptyStr(data.itemId) then
        return { ok = false, err = T('vehicle_not_found') }
    end

    -- busca o item no cache local do cliente
    local vehicleItem
    for _, item in ipairs(Client.shopItems) do
        if item.id == data.itemId and item.category == 'vehicle' then
            vehicleItem = item
            break
        end
    end
    if not vehicleItem then
        return { ok = false, err = T('vehicle_not_found') }
    end

    -- fecha a NUI antes de iniciar o test-drive
    VHubCoin.Shop.closeShop()

    -- limpa veículo órfão de test-drive anterior (caso exista)
    TestDrive._cleanupVehicle()

    -- posição de retorno é capturada pelo SERVER (getPosition no setBucket) — não salvamos
    -- coord no client (evita 2ª fonte de verdade + payload de teleport, L-04/L-16)

    -- carrega modelo do veículo
    local modelHash = GetHashKey(vehicleItem.spawnName)
    RequestModel(modelHash)

    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 50 do
        Wait(100)
        attempts = attempts + 1
    end
    if not HasModelLoaded(modelHash) then
        return { ok = false, err = T('failed_load_vehicle') }
    end

    TestDrive.active = true

    -- fade out; o teleport de IDA é feito pelo SERVER (dono do ped, L-16): ele isola
    -- em bucket E teleporta para o local de test-drive (coord vem da shared config).
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(50) end

    -- server: isola em bucket 2 + teleporta ao local de test-drive (via owner do ped)
    TriggerServerEvent(VHubCoin.S.SET_BUCKET)
    Wait(600)   -- aguarda bucket + teleport server→client aplicarem

    -- spawn do veículo efêmero (cliente autoritativo pois é missão, prefixo CS, não-persistente).
    -- ped já foi teleportado pelo server; nasce à frente dele com o heading do próprio ped.
    local pedNow       = PlayerPedId()
    local forward      = GetEntityForwardVector(pedNow)
    local pedCoords    = GetEntityCoords(pedNow)
    local pedHeading   = GetEntityHeading(pedNow)
    local spawnCoords  = pedCoords + forward * VHubCoin.cfg.testDriveSpawnDistance
    local vehicle      = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, pedHeading, true, false)
    TestDrive.vehicle  = vehicle

    SetModelAsNoLongerNeeded(modelHash)
    TaskWarpPedIntoVehicle(pedNow, vehicle, -1)
    SetVehicleNumberPlateText(vehicle, VHubCoin.cfg.testDrivePlatePrefix .. math.random(100, 999))
    SetEntityAsMissionEntity(vehicle, true, true)

    DoScreenFadeIn(500)
    while not IsScreenFadedIn() do Wait(50) end

    -- notifica início
    TriggerEvent('chat:addMessage', { args = { '[Coinshop]', T('test_drive_started', VHubCoin.cfg.testDriveDuration) } })

    -- thread de duração (condição de saída explícita — L-18)
    TestDrive._timeoutThread = CreateThread(function()
        local elapsed  = 0
        local duration = VHubCoin.cfg.testDriveDuration * 1000
        while elapsed < duration and TestDrive.active do
            Wait(500)
            elapsed = elapsed + 500
            -- se o veículo sumiu ou o ped saiu, encerra antes
            local ped = PlayerPedId()
            if not TestDrive.vehicle or not DoesEntityExist(TestDrive.vehicle) then break end
            if GetVehiclePedIsIn(ped, false) ~= TestDrive.vehicle then break end
        end
        TestDrive.finish()
    end)

    return { ok = true, data = { message = T('test_drive_started_msg') } }
end


-- ============================================================
-- ENCERRAR TEST-DRIVE
-- ============================================================

-- encerra o test-drive: remove veículo, restaura posição, volta ao bucket 0
function TestDrive.finish()
    if not TestDrive.active then return end
    TestDrive.active = false

    if TestDrive._timeoutThread then
        TestDrive._timeoutThread = nil
    end

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(50) end

    TestDrive._cleanupVehicle()

    Wait(200)

    -- server: sai do bucket + teleporta o ped de volta à ORIGEM (verdade server-side;
    -- o server salvou a coord no setBucket via getPosition — nada de coord no payload, L-04).
    TriggerServerEvent(VHubCoin.S.RESET_BUCKET)

    Wait(600)   -- aguarda bucket + teleport server→client aplicarem
    DoScreenFadeIn(500)

    TriggerEvent('chat:addMessage', { args = { '[Coinshop]', T('test_drive_ended') } })
end


-- ============================================================
-- CLEANUP
-- ============================================================

-- remove veículo de test-drive ativo (deleta duplicatas pela placa nativa)
function TestDrive._cleanupVehicle()
    if TestDrive.vehicle and DoesEntityExist(TestDrive.vehicle) then
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) == TestDrive.vehicle then
            TaskLeaveVehicle(ped, TestDrive.vehicle, 16)
            Wait(800)
        end
        SetEntityAsMissionEntity(TestDrive.vehicle, true, true)
        DeleteEntity(TestDrive.vehicle)
    end
    TestDrive.vehicle = nil
end

-- chamado em onResourceStop — libera tudo (retorno pelo owner server-side, L-16)
function TestDrive.cleanup()
    TestDrive._cleanupVehicle()
    if TestDrive.active then
        TriggerServerEvent(VHubCoin.S.RESET_BUCKET)
        TestDrive.active = false
    end
end

