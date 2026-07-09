-- client/nui.lua — abertura/fechamento da NUI e callbacks RegisterNUICallback (relay puro de intenção)
-- ATENÇÃO: VHubCoin.NUI é a tabela de NOMES de callback (shared/events.lua) — o módulo de
-- funções deste arquivo é VHubCoin.Shop (a colisão de nomes era a causa do
-- "RegisterNuiCallbackType: Argument at index 0 was null": sobrescrevia os nomes com {}).
---@diagnostic disable: undefined-global

VHubCoin = VHubCoin or {}
local Client = VHubCoin.Client
local Shop = {}
VHubCoin.Shop = Shop

local lib = { callback = {} }
local pendingCallbacks = {}
local nextCallbackId = 0

function lib.callback.await(name, _timeout, payload)
    nextCallbackId = nextCallbackId + 1
    local reqId = nextCallbackId
    local p = promise.new()
    pendingCallbacks[reqId] = function(result)
        p:resolve(result)
    end

    TriggerServerEvent('vhub_coinshop:request', reqId, name, payload)
    return Citizen.Await(p)
end

RegisterNetEvent('vhub_coinshop:reply', function(reqId, result)
    local resolver = pendingCallbacks[reqId]
    if not resolver then return end
    pendingCallbacks[reqId] = nil
    resolver(result)
end)


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- abre a loja: busca dados iniciais no servidor, envia `open` à NUI
function Shop.openShop()
    if Client.isShopOpen then return end
    Client.isShopOpen = true
    SetNuiFocus(true, true)

    -- aguarda dados do servidor (lib.callback.await é não-bloqueante dentro de thread)
    CreateThread(function()
        local data = lib.callback.await('vhub_coinshop:getInitData', false)
        if not Client.isShopOpen then return end -- usuário fechou antes da resposta
        if not data or not data.ok then
            Client.isShopOpen = false
            SetNuiFocus(false, false)
            return
        end
        local d = data.data or {}
        Client.shopItems      = d.items or {}
        Client.shopCategories = d.categories or {}

        SendNUIMessage({
            type        = 'open',
            items       = Client.shopItems,
            categories  = Client.shopCategories,
            deals       = d.deals or {},
            coins       = d.coins or 0,
            playerName  = d.playerName or 'Jogador',
            playerAvatar = d.playerAvatar or '',
            isAdmin     = d.isAdmin or false,
            dealResetHour = d.dealResetHour or 0,
            logo        = d.logo or '',
            settings    = d.settings or {},
            locale      = d.locale or VHubCoin.locale,
        })
    end)
end

-- fecha a loja: drop focus + avisa NUI para esconder (RAF/interval mortos)
function Shop.closeShop()
    if not Client.isShopOpen then return end
    Client.isShopOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end


-- ============================================================
-- NUI CALLBACKS — relay puro (só intenção; servidor decide — §3.9)
-- ============================================================

RegisterNUICallback(VHubCoin.NUI.CLOSE, function(_, cb)
    Shop.closeShop()
    cb({ ok = true })
end)

RegisterNUICallback(VHubCoin.NUI.NOTIFY, function(data, cb)
    if type(data) == 'table' and VHubCoin.isNonEmptyStr(data.message) then
        TriggerEvent('chat:addMessage', { args = { '[Coinshop]', data.message } })
    end
    cb({ ok = true })
end)

-- o saldo pós-compra é atualizado pelo evento COINS_CHANGED (server dispara notifyChange
-- em buyItem/buyDeal/redeemCode → client/init.lua repassa à NUI); sem getCoins redundante.
RegisterNUICallback(VHubCoin.NUI.PURCHASE_ITEM, function(data, cb)
    CreateThread(function()
        local result = lib.callback.await('vhub_coinshop:purchaseItem', false, data)
        cb(result or { ok = false, err = 'no_response' })
    end)
end)

RegisterNUICallback(VHubCoin.NUI.PURCHASE_DEAL, function(data, cb)
    CreateThread(function()
        local result = lib.callback.await('vhub_coinshop:purchaseDeal', false, data)
        cb(result or { ok = false, err = 'no_response' })
    end)
end)

RegisterNUICallback(VHubCoin.NUI.REDEEM_CODE, function(data, cb)
    CreateThread(function()
        local result = lib.callback.await('vhub_coinshop:redeemCode', false, data)
        cb(result or { ok = false, err = 'no_response' })
    end)
end)

RegisterNUICallback(VHubCoin.NUI.TEST_DRIVE, function(data, cb)
    CreateThread(function()
        local result = VHubCoin.TestDrive.request(data)
        cb(result or { ok = false, err = 'no_response' })
    end)
end)


-- ============================================================
-- ADMIN — callbacks NUI (relay para lib.callback.await)
-- ============================================================

local function adminCall(name, data)
    return lib.callback.await(name, false, data)
end

RegisterNUICallback(VHubCoin.NUI.GET_ADMIN_STATS,    function(_, cb) CreateThread(function() cb(adminCall('vhub_coinshop:getAdminStats', nil)) end) end)
RegisterNUICallback(VHubCoin.NUI.GET_RECENT_TX,      function(_, cb) CreateThread(function() cb(adminCall('vhub_coinshop:getRecentTransactions', nil)) end) end)
RegisterNUICallback(VHubCoin.NUI.GET_TOP_SELLING,    function(_, cb) CreateThread(function() cb(adminCall('vhub_coinshop:getTopSelling', nil)) end) end)
RegisterNUICallback(VHubCoin.NUI.GET_PURCHASE_HIST,  function(_, cb) CreateThread(function() cb(adminCall('vhub_coinshop:getPurchaseHistory', nil)) end) end)
RegisterNUICallback(VHubCoin.NUI.GET_ONLINE_PLAYERS, function(_, cb) CreateThread(function() cb(adminCall('vhub_coinshop:getOnlinePlayers', nil)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_GIVE_COINS,   function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminGiveCoins', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_SET_COINS,    function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminSetCoins', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_CREATE_ITEM,  function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminCreateItem', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_EDIT_ITEM,    function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminEditItem', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_DELETE_ITEM,  function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminDeleteItem', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_CREATE_CAT,   function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminCreateCategory', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_EDIT_CAT,     function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminEditCategory', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_DELETE_CAT,   function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminDeleteCategory', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_CREATE_DEAL,  function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminCreateDeal', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_DELETE_DEAL,  function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminDeleteDeal', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_CLEAR_ALL,    function(_, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminClearAll', nil)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_SAVE_SETS,    function(d, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminSaveSettings', d)) end) end)
RegisterNUICallback(VHubCoin.NUI.ADMIN_RESET_SETS,   function(_, cb) CreateThread(function() cb(adminCall('vhub_coinshop:adminResetSettings', nil)) end) end)


