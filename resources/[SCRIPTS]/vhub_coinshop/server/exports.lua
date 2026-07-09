-- server/exports.lua — API pública do vhub_coinshop: callbacks NUI + exports gated para outros resources

VHubCoin = VHubCoin or {}
local Core  = VHubCoin.Core
local Coins = VHubCoin.Coins
local Items = VHubCoin.Items
local Purch = VHubCoin.Purchases

local lib = { callback = {} }
local callbackHandlers = {}

function lib.callback.register(name, handler)
    callbackHandlers[name] = handler
end

RegisterNetEvent('vhub_coinshop:request', function(reqId, name, payload)
    local src = source
    local handler = callbackHandlers[name]
    if not handler then
        TriggerClientEvent('vhub_coinshop:reply', src, reqId, { ok = false, err = 'unknown_callback' })
        return
    end

    local ok, result = pcall(handler, src, payload)
    if not ok then
        TriggerClientEvent('vhub_coinshop:reply', src, reqId, { ok = false, err = 'callback_error' })
        return
    end

    TriggerClientEvent('vhub_coinshop:reply', src, reqId, result)
end)


-- ============================================================
-- HELPER — resposta padrão para NUI callbacks: { ok, data?, err? }
-- ============================================================

local function ok(data) return { ok = true,  data = data } end
local function err(msg) return { ok = false, err = msg } end


-- ============================================================
-- CALLBACKS NUI — registradas via lib.callback (cliente aguarda resposta)
-- ============================================================

-- abre a loja: retorna dados iniciais (itens, categorias, ofertas, saldo, admin, settings, locale, discord, logo)
lib.callback.register('vhub_coinshop:getInitData', function(source)
    if not Core.rate(source, 'openShop', VHubCoin.cfg.rates.openShop) then
        return err(T('purchase_in_progress'))
    end
    local char_id = Core.getCharId(source)
    if not char_id then return err(T('player_not_found')) end

    -- garantia de sessão quente
    if not Core.sessions[source] then
        Core.sessions[source] = { char_id = char_id }
    end

    local itemList = {}
    for _, item in ipairs(Items.list) do
        itemList[#itemList + 1] = Items.publicCopy(item)
    end

    local discordData = VHubCoin.Discord.cached(source)
    if not discordData and VHubCoin.isNonEmptyStr(VHubCoin.cfg.discordBotToken) then
        VHubCoin.Discord.fetch(source, function() end) -- fire-and-forget; próxima abertura usa cache
    end

    return ok({
        items         = itemList,
        categories    = Items.categories,
        deals         = Items.deals,
        coins         = Coins.get(char_id),
        isAdmin       = Core.isAdmin(source),
        settings      = Items.settings,
        dealResetHour = VHubCoin.cfg.dealResetHour,
        logo          = VHubCoin.cfg.logo,
        locale        = VHubCoin.locale,
        playerName    = Core.getPlayerName(source),
        playerAvatar  = discordData and discordData.avatar or '',
    })
end)

-- consulta saldo (NUI pode atualizar display isoladamente) — rate folgado anti-spam
lib.callback.register('vhub_coinshop:getCoins', function(source)
    if not Core.rate(source, 'getCoins', VHubCoin.cfg.rates.getCoins) then
        return ok({ rateLimited = true })
    end
    local char_id = Core.getCharId(source)
    return ok({ coins = char_id and Coins.get(char_id) or 0 })
end)

-- compra item
lib.callback.register('vhub_coinshop:purchaseItem', function(source, data)
    if not Core.rate(source, 'purchaseItem', VHubCoin.cfg.rates.purchaseItem) then
        return err(T('purchase_in_progress'))
    end
    if type(data) ~= 'table' or not VHubCoin.isNonEmptyStr(data.itemId) then
        return err(T('invalid_data'))
    end
    local char_id = Core.getCharId(source)
    if not char_id then return err(T('player_not_found')) end

    local success, message = Purch.buyItem(source, char_id, data.itemId)
    return success and ok({ message = message }) or err(message)
end)

-- compra oferta
lib.callback.register('vhub_coinshop:purchaseDeal', function(source, data)
    if not Core.rate(source, 'purchaseDeal', VHubCoin.cfg.rates.purchaseDeal) then
        return err(T('purchase_in_progress'))
    end
    if type(data) ~= 'table' or not VHubCoin.isNonEmptyStr(data.dealId) then
        return err(T('invalid_data'))
    end
    local char_id = Core.getCharId(source)
    if not char_id then return err(T('player_not_found')) end

    local success, message = Purch.buyDeal(source, char_id, data.dealId)
    return success and ok({ message = message }) or err(message)
end)

-- resgata código Tebex
lib.callback.register('vhub_coinshop:redeemCode', function(source, data)
    if not Core.rate(source, 'redeemCode', VHubCoin.cfg.rates.redeemCode) then
        return err(T('purchase_in_progress'))
    end
    if type(data) ~= 'table' or not VHubCoin.isNonEmptyStr(data.redeemKey) then
        return err(T('invalid_order_number'))
    end
    local char_id = Core.getCharId(source)
    if not char_id then return err(T('player_not_found')) end

    local targetId = (data.targetId and data.targetId ~= '') and data.targetId or nil
    local success, message = Purch.redeemCode(source, char_id, data.redeemKey, targetId)
    return success and ok({ message = message }) or err(message)
end)


-- ============================================================
-- CALLBACKS NUI — ADMIN (todas checam isAdmin + rate)
-- ============================================================

lib.callback.register('vhub_coinshop:getAdminStats', function(source)
    if not Core.isAdmin(source) then return ok({}) end
    return ok(Items.adminStats())
end)

lib.callback.register('vhub_coinshop:getRecentTransactions', function(source)
    if not Core.isAdmin(source) then return ok({}) end
    return ok(Items.recentTransactions())
end)

lib.callback.register('vhub_coinshop:getTopSelling', function(source)
    if not Core.isAdmin(source) then return ok({}) end
    return ok(Items.topSelling())
end)

lib.callback.register('vhub_coinshop:getPurchaseHistory', function(source)
    if not Core.isAdmin(source) then return ok({}) end
    return ok(Items.purchaseHistory())
end)

lib.callback.register('vhub_coinshop:getOnlinePlayers', function(source)
    if not Core.isAdmin(source) then return ok({}) end
    if not Core.rate(source, 'getOnlineList', VHubCoin.cfg.rates.getOnlineList) then
        return ok({ rateLimited = true })
    end
    local list = {}
    for _, idStr in ipairs(GetPlayers()) do
        local id = tonumber(idStr)
        if id then
            local char_id = Core.getCharId(id)
            list[#list + 1] = {
                id    = id,
                name  = Core.getPlayerName(id),
                coins = char_id and Coins.get(char_id) or 0,
            }
        end
    end
    return ok(list)
end)

-- CRUD itens
lib.callback.register('vhub_coinshop:adminCreateItem', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local success, message = Items.adminCreate(source, data)
    return success and ok({ message = message }) or err(message)
end)

lib.callback.register('vhub_coinshop:adminEditItem', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local success, message = Items.adminEdit(source, data)
    return success and ok({ message = message }) or err(message)
end)

lib.callback.register('vhub_coinshop:adminDeleteItem', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local itemId = type(data) == 'table' and data.itemId or data
    local success, message = Items.adminDelete(source, itemId)
    return success and ok({ message = message }) or err(message)
end)

-- CRUD categorias
lib.callback.register('vhub_coinshop:adminCreateCategory', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local success, message = Items.adminCreateCategory(source, data)
    return success and ok({ message = message }) or err(message)
end)

lib.callback.register('vhub_coinshop:adminEditCategory', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local success, message = Items.adminEditCategory(source, data)
    return success and ok({ message = message }) or err(message)
end)

lib.callback.register('vhub_coinshop:adminDeleteCategory', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local categoryId = type(data) == 'table' and data.categoryId or data
    local success, message = Items.adminDeleteCategory(source, categoryId)
    return success and ok({ message = message }) or err(message)
end)

-- CRUD ofertas
lib.callback.register('vhub_coinshop:adminCreateDeal', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local success, message = Items.adminCreateDeal(source, data)
    return success and ok({ message = message }) or err(message)
end)

lib.callback.register('vhub_coinshop:adminDeleteDeal', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local dealId = type(data) == 'table' and data.dealId or data
    local success, message = Items.adminDeleteDeal(source, dealId)
    return success and ok({ message = message }) or err(message)
end)

-- limpar tudo
lib.callback.register('vhub_coinshop:adminClearAll', function(source)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'adminAction', VHubCoin.cfg.rates.adminAction) then return err(T('purchase_in_progress')) end
    local success, message = Items.adminClearAll(source)
    return success and ok({ message = message }) or err(message)
end)

-- give/set coins (admin via painel)
lib.callback.register('vhub_coinshop:adminGiveCoins', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if type(data) ~= 'table' then return err(T('invalid_data')) end
    local targetId = tonumber(data.targetId)
    local amount   = tonumber(data.amount)
    if not (targetId and amount) or amount <= 0 then return err(T('invalid_target_amount')) end
    local targetChar = Core.getCharId(targetId)
    if not targetChar then return err(T('player_not_found')) end

    local old = Coins.get(targetChar)
    Coins.credit(targetChar, amount)
    Coins.notifyChange(targetId, targetChar)
    Core.notify(targetId, T('received_coins', amount), 'success')

    VHubCoin.Webhooks.fire('admin', 'Admin: Give Coins', nil, {
        { name = 'Admin',     value = Core.getPlayerName(source) .. ' (ID: ' .. source .. ')', inline = true },
        { name = 'Alvo',      value = Core.getPlayerName(targetId) .. ' (ID: ' .. targetId .. ')', inline = true },
        { name = 'Quantidade',value = '+' .. tostring(amount) .. ' moedas', inline = true },
        { name = 'Novo Saldo',value = tostring(old + amount), inline = true },
    })
    return ok({ message = T('gave_coins', amount, targetId) })
end)

lib.callback.register('vhub_coinshop:adminSetCoins', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if type(data) ~= 'table' then return err(T('invalid_data')) end
    local targetId = tonumber(data.targetId)
    local amount   = tonumber(data.amount)
    if not (targetId and amount) or amount < 0 then return err(T('invalid_target_amount')) end
    local targetChar = Core.getCharId(targetId)
    if not targetChar then return err(T('player_not_found')) end

    local old = Coins.get(targetChar)
    Coins.set(targetChar, amount)
    Coins.notifyChange(targetId, targetChar)
    Core.notify(targetId, T('coins_set_to', amount), 'info')

    VHubCoin.Webhooks.fire('admin', 'Admin: Set Coins', nil, {
        { name = 'Admin',    value = Core.getPlayerName(source) .. ' (ID: ' .. source .. ')', inline = true },
        { name = 'Alvo',     value = Core.getPlayerName(targetId) .. ' (ID: ' .. targetId .. ')', inline = true },
        { name = 'Mudança',  value = tostring(old) .. ' → ' .. tostring(amount), inline = true },
    })
    return ok({ message = T('set_coins_msg', targetId, amount) })
end)

-- settings UI
lib.callback.register('vhub_coinshop:adminSaveSettings', function(source, data)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    local success, message = Items.adminSaveSettings(source, data)
    return success and ok({ message = message }) or err(message)
end)

lib.callback.register('vhub_coinshop:adminResetSettings', function(source)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    local success, message = Items.adminResetSettings(source)
    return success and ok({ message = message }) or err(message)
end)


-- ============================================================
-- EXPORTS GATED — API pública para outros resources (default-deny, R3)
-- ============================================================

local TRUSTED = {
    ['vhub_admin']      = true,
    ['vhub_money']      = true,
    ['vhub_telemetry']  = true,
}

local function _invoker_allowed()
    local caller = GetInvokingResource()
    if not caller then return true end -- chamada interna do próprio resource
    return TRUSTED[caller] == true
end

-- retorna saldo de moedas do personagem (read-only; público para trusted)
exports('getCoins', function(char_id)
    if not _invoker_allowed() then return nil end
    return Coins.get(char_id)
end)

-- credita moedas a um personagem (escrita gated; só trusted)
exports('creditCoins', function(char_id, amount)
    if not _invoker_allowed() then return false end
    return Coins.credit(char_id, amount)
end)

-- retorna lista de itens públicos (read-only; qualquer resource pode ler)
exports('getItems', function()
    local list = {}
    for _, item in ipairs(Items.list) do
        list[#list + 1] = Items.publicCopy(item)
    end
    return list
end)

-- retorna ofertas ativas (read-only)
exports('getDeals', function()
    return Items.deals
end)
