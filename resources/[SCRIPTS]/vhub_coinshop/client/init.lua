-- client/init.lua — bootstrap do cliente vhub_coinshop: state local, net events

VHubCoin = VHubCoin or {}
local Client = {}
VHubCoin.Client = Client


-- ============================================================
-- STATE LOCAL (efêmero; servidor é verdade — L-02/L-03)
-- ============================================================

Client.isShopOpen = false


-- ============================================================
-- NET EVENTS — server→client (discrete; nunca para estado contínuo)
-- (keybind F5 e comando client REMOVIDOS — decisão #58: /coinshop é
--  server-side admin-only; jogador abre a loja pelo app do iPad)
-- ============================================================

-- servidor autorizou (/coinshop admin): abre a NUI fullscreen com painel completo
RegisterNetEvent(VHubCoin.E.OPEN_SHOP_ADMIN, function()
    if Client.isShopOpen then
        VHubCoin.Shop.closeShop()
    else
        VHubCoin.Shop.openShop()
    end
end)

-- saldo de moedas mudou — repassa à NUI se aberta
RegisterNetEvent(VHubCoin.E.COINS_CHANGED, function(coins)
    if Client.isShopOpen then
        SendNUIMessage({ type = 'coinsChanged', coins = coins })
    end
end)

-- ============================================================
-- CLEANUP — onResourceStop (sem leak)
-- ============================================================

AddEventHandler('onResourceStop', function(stopping)
    if stopping ~= GetCurrentResourceName() then return end
    if Client.isShopOpen then
        SetNuiFocus(false, false)
    end
end)
