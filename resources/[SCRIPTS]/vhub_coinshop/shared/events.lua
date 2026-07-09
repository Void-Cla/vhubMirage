-- shared/events.lua — registro único de nomes de evento do vhub_coinshop (global, sem return)

VHubCoin = VHubCoin or {}

-- eventos server→client (TriggerClientEvent) — discrete, nunca para estado contínuo
-- (NOTIFY/TESTDRIVE_* removidos: nunca disparados pelo server — o fluxo real é
--  Core.notify via exports.vhub e test-drive 100% client-driven; L-15)
VHubCoin.E = {
    -- notifica o cliente que o saldo de moedas mudou (discreto; NUI atualiza display)
    COINS_CHANGED  = 'vhub_coinshop:coinsChanged',
    -- pede ao cliente que spawne o veículo comprado (modelo + placa)
    SPAWN_VEHICLE   = 'vhub_coinshop:spawnPurchasedVehicle',
}

-- eventos client→server (RegisterNetEvent) — intenção, nunca verdade
VHubCoin.S = {
    SET_BUCKET  = 'vhub_coinshop:setTestDriveBucket',
    RESET_BUCKET = 'vhub_coinshop:resetBucket',
}

-- ações NUI (RegisterNUICallback) — snake_case, o cliente envia só intenção/IDs
VHubCoin.NUI = {
    CLOSE              = 'close',
    NOTIFY             = 'notify',
    PURCHASE_ITEM      = 'purchaseItem',
    PURCHASE_DEAL      = 'purchaseDeal',
    REDEEM_CODE        = 'redeemCode',
    TEST_DRIVE         = 'testDrive',
    GET_ADMIN_STATS    = 'getAdminStats',
    GET_RECENT_TX      = 'getRecentTransactions',
    GET_TOP_SELLING    = 'getTopSelling',
    GET_PURCHASE_HIST  = 'getPurchaseHistory',
    GET_ONLINE_PLAYERS = 'getOnlinePlayers',
    ADMIN_GIVE_COINS   = 'adminGiveCoins',
    ADMIN_SET_COINS    = 'adminSetCoins',
    ADMIN_CREATE_ITEM  = 'adminCreateItem',
    ADMIN_EDIT_ITEM    = 'adminEditItem',
    ADMIN_DELETE_ITEM  = 'adminDeleteItem',
    ADMIN_CREATE_CAT   = 'adminCreateCategory',
    ADMIN_EDIT_CAT     = 'adminEditCategory',
    ADMIN_DELETE_CAT   = 'adminDeleteCategory',
    ADMIN_CREATE_DEAL  = 'adminCreateDeal',
    ADMIN_DELETE_DEAL  = 'adminDeleteDeal',
    ADMIN_CLEAR_ALL    = 'adminClearAll',
    ADMIN_SAVE_SETS    = 'adminSaveSettings',
    ADMIN_RESET_SETS   = 'adminResetSettings',
}
