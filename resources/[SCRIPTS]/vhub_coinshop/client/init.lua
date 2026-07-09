-- client/init.lua — bootstrap do cliente vhub_coinshop: comando, keybind, state local, roteamento NUI

VHubCoin = VHubCoin or {}
local Client = {}
VHubCoin.Client = Client


-- ============================================================
-- STATE LOCAL (efêmero; servidor é verdade — L-02/L-03)
-- ============================================================

Client.isShopOpen     = false
Client.shopItems      = {}
Client.shopCategories = {}


-- ============================================================
-- COMANDO E KEYBIND
-- ============================================================

RegisterCommand(VHubCoin.cfg.command, function()
    if Client.isShopOpen then
        VHubCoin.Shop.closeShop()
    else
        VHubCoin.Shop.openShop()
    end
end, false)

RegisterKeyMapping(VHubCoin.cfg.command, VHubCoin.cfg.keyDescription, 'keyboard', VHubCoin.cfg.key)


-- ============================================================
-- NET EVENTS — server→client (discrete; nunca para estado contínuo)
-- ============================================================

-- saldo de moedas mudou — repassa à NUI se aberta
RegisterNetEvent(VHubCoin.E.COINS_CHANGED, function(coins)
    if Client.isShopOpen then
        SendNUIMessage({ type = 'coinsChanged', coins = coins })
    end
end)

-- servidor pede para spawnar veículo comprado (modelo + placa)
RegisterNetEvent(VHubCoin.E.SPAWN_VEHICLE, function(modelName, plate)
    VHubCoin.VehicleSpawn.spawnPurchased(modelName, plate)
end)


-- ============================================================
-- CLEANUP — onResourceStop (sem leak)
-- ============================================================

AddEventHandler('onResourceStop', function(stopping)
    if stopping ~= GetCurrentResourceName() then return end
    if Client.isShopOpen then
        SetNuiFocus(false, false)
    end
    VHubCoin.TestDrive.cleanup()
end)
