-- server/exports.lua — API pública do vhub_coinshop: callbacks NUI + exports gated para outros resources

VHubCoin = VHubCoin or {}
local Core  = VHubCoin.Core
local Coins = VHubCoin.Coins
local Items = VHubCoin.Items

local lib = { callback = {} }
local callbackHandlers = {}

function lib.callback.register(name, handler)
    callbackHandlers[name] = handler
end

RegisterNetEvent('vhub_coinshop:request', function(reqId, name, payload)
    local src = source
    if type(src) ~= 'number' or src <= 0 or not GetPlayerName(src) then return end
    if type(reqId) ~= 'number' or reqId % 1 ~= 0 or reqId < 1 or reqId > 2147483647 then return end
    if type(name) ~= 'string' or #name > 100 then return end
    local handler = callbackHandlers[name]
    if not handler then
        TriggerClientEvent('vhub_coinshop:reply', src, reqId, { ok = false, err = 'unknown_callback' })
        return
    end

    local ok, result = pcall(handler, src, payload)
    if not ok then
        -- NUNCA engolir em silêncio (C2 do gate #58): a falha fantasma do "F5 pisca e some" nasceu aqui
        Core.logErr(('callback %s (reqId=%s, src=%s) estourou: %s')
            :format(tostring(name), tostring(reqId), tostring(src), tostring(result)))
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
-- CALLBACKS NUI — painel ADMIN (/coinshop). A superfície de JOGADOR da NUI
-- fullscreen foi REMOVIDA (#59): compra/oferta/resgate/test-drive vivem no
-- app do iPad via ipad_relay.lua (mesmo domínio Purchases — escritor único).
-- ============================================================

-- helper: snapshot das listas frescas pós-mutação (mata o stale-list do painel — #59/T.4)
local function refreshIpadCatalog()
    if VHubCoin.IpadRelay_PushCatalog then VHubCoin.IpadRelay_PushCatalog() end
end

local function freshLists(kind)
    local out = {}
    if kind == 'items' or kind == 'all' then
        local list = {}
        for _, item in ipairs(Items.list) do list[#list + 1] = Items.publicCopy(item, true) end
        out.items = list
    end
    if kind == 'categories' or kind == 'all' then out.categories = Items.categories end
    if kind == 'deals' or kind == 'all' then out.deals = Items.deals end
    refreshIpadCatalog()
    return out
end

-- abre o painel: retorna dados iniciais (itens, categorias, ofertas, saldo, settings, locale, logo)
lib.callback.register('vhub_coinshop:getInitData', function(source)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, 'openShop', VHubCoin.cfg.rates.openShop) then
        return err(T('purchase_in_progress'))
    end
    local char_id = Core.getCharId(source)
    if not char_id then return err(T('player_not_found')) end

    -- garantia de sessão quente
    if not Core.sessions[source] then
        Core.sessions[source] = { char_id = char_id }
    end

    return ok(Core.buildShopData(source, char_id, true))
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

-- helper: gate padrão de mutação admin (permissão + rate) — retorna err() pronto ou nil
local function adminGate(source, rateKey, rateMs)
    if not Core.isAdmin(source) then return err(T('no_permission')) end
    if not Core.rate(source, rateKey or 'adminAction', rateMs or VHubCoin.cfg.rates.adminAction) then
        return err(T('purchase_in_progress'))
    end
    return nil
end

-- CRUD itens (retorno carrega as listas frescas — o painel re-renderiza sem reabrir)
lib.callback.register('vhub_coinshop:adminCreateItem', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local success, message = Items.adminCreate(source, data)
    if not success then return err(message) end
    local out = freshLists('items') out.message = message
    return ok(out)
end)

lib.callback.register('vhub_coinshop:adminEditItem', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local success, message = Items.adminEdit(source, data)
    if not success then return err(message) end
    local out = freshLists('items') out.message = message
    return ok(out)
end)

lib.callback.register('vhub_coinshop:adminDeleteItem', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local itemId = type(data) == 'table' and data.itemId or data
    local success, message = Items.adminDelete(source, itemId)
    if not success then return err(message) end
    local out = freshLists('items') out.message = message
    return ok(out)
end)

-- CRUD categorias
lib.callback.register('vhub_coinshop:adminCreateCategory', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local success, message = Items.adminCreateCategory(source, data)
    if not success then return err(message) end
    local out = freshLists('categories') out.message = message
    return ok(out)
end)

lib.callback.register('vhub_coinshop:adminEditCategory', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local success, message = Items.adminEditCategory(source, data)
    if not success then return err(message) end
    local out = freshLists('categories') out.message = message
    return ok(out)
end)

lib.callback.register('vhub_coinshop:adminDeleteCategory', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local categoryId = type(data) == 'table' and data.categoryId or data
    local success, message = Items.adminDeleteCategory(source, categoryId)
    if not success then return err(message) end
    -- deletar categoria desvincula itens — devolve os 2 slices
    local out = freshLists('all') out.message = message
    return ok(out)
end)

-- CRUD ofertas/combos
lib.callback.register('vhub_coinshop:adminCreateDeal', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local success, message = Items.adminCreateDeal(source, data)
    if not success then return err(message) end
    local out = freshLists('deals') out.message = message
    return ok(out)
end)

lib.callback.register('vhub_coinshop:adminEditDeal', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local success, message = Items.adminEditDeal(source, data)
    if not success then return err(message) end
    local out = freshLists('deals') out.message = message
    return ok(out)
end)

lib.callback.register('vhub_coinshop:adminDeleteDeal', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local dealId = type(data) == 'table' and data.dealId or data
    local success, message = Items.adminDeleteDeal(source, dealId)
    if not success then return err(message) end
    local out = freshLists('deals') out.message = message
    return ok(out)
end)

-- CÓDIGOS de resgate (chave gerada SERVER-side; mostrada 1x ao admin — #59/4.1)
lib.callback.register('vhub_coinshop:adminCreateCode', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local coins = type(data) == 'table' and tonumber(data.coins) or tonumber(data)
    local success, keyOrMsg = Items.adminCreateCode(source, coins)
    if not success then return err(keyOrMsg) end
    return ok({ key = keyOrMsg, codes = Items.adminListCodes() })
end)

lib.callback.register('vhub_coinshop:adminListCodes', function(source)
    if not Core.isAdmin(source) then return ok({ codes = {} }) end
    return ok({ codes = Items.adminListCodes() })
end)

lib.callback.register('vhub_coinshop:adminDeleteCode', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    local key = type(data) == 'table' and data.key or data
    local success, message = Items.adminDeleteCode(source, key)
    if not success then return err(message) end
    return ok({ message = message, codes = Items.adminListCodes() })
end)

-- limpar tudo
lib.callback.register('vhub_coinshop:adminClearAll', function(source)
    local deny = adminGate(source) if deny then return deny end
    local success, message = Items.adminClearAll(source)
    if not success then return err(message) end
    local out = freshLists('all') out.message = message
    return ok(out)
end)

-- importação: preview não muta; exec cria apenas rascunhos não publicados
lib.callback.register('vhub_coinshop:adminImportPreview', function(source, data)
    local deny = adminGate(source, 'importPreview', VHubCoin.cfg.rates.importPreview)
    if deny then return deny end
    if not VHubCoin.Import then return err('Importador indisponível.') end
    local success, result = VHubCoin.Import.preview(source, data)
    return success and ok(result) or err(result)
end)

lib.callback.register('vhub_coinshop:adminImportRun', function(source, data)
    local deny = adminGate(source, 'importRun', VHubCoin.cfg.rates.importRun)
    if deny then return deny end
    if not VHubCoin.Import then return err('Importador indisponível.') end
    local success, result = VHubCoin.Import.run(source, data)
    if not success then return err(result) end
    refreshIpadCatalog()
    return ok(result)
end)

-- give/set coins (admin via painel)
lib.callback.register('vhub_coinshop:adminGiveCoins', function(source, data)
    local deny = adminGate(source) if deny then return deny end
    if type(data) ~= 'table' then return err(T('invalid_data')) end
    local targetId = tonumber(data.targetId)
    local amount   = tonumber(data.amount)
    if not (targetId and amount) or amount <= 0 then return err(T('invalid_target_amount')) end
    local targetChar = Core.getCharId(targetId)
    if not targetChar then return err(T('player_not_found')) end

    local old = Coins.get(targetChar)
    if not Coins.credit(targetChar, amount) then return err(T('coin_persistence_failed')) end
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
    local deny = adminGate(source) if deny then return deny end
    if type(data) ~= 'table' then return err(T('invalid_data')) end
    local targetId = tonumber(data.targetId)
    local amount   = tonumber(data.amount)
    if not (targetId and amount) or amount < 0 then return err(T('invalid_target_amount')) end
    local targetChar = Core.getCharId(targetId)
    if not targetChar then return err(T('player_not_found')) end

    local old = Coins.get(targetChar)
    if not Coins.set(targetChar, amount) then return err(T('coin_persistence_failed')) end
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
    local deny = adminGate(source) if deny then return deny end
    local success, message = Items.adminSaveSettings(source, data)
    return success and ok({ message = message }) or err(message)
end)

lib.callback.register('vhub_coinshop:adminResetSettings', function(source)
    local deny = adminGate(source) if deny then return deny end
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
        if item.published then
        list[#list + 1] = Items.publicCopy(item)
        end
    end
    return list
end)

-- retorna ofertas ativas (read-only)
exports('getDeals', function()
    return Items.publicDeals()
end)

-- cria código de resgate com `coins` moedas e retorna a chave gerada server-side
-- (escrita gated; seam para PSP/Tebex futuro — o webhook de pagamento confirma e
--  chama este export ou creditCoins; export-first, decisão #35/#59)
exports('createRedeemCode', function(coins)
    if not _invoker_allowed() then return nil end
    local success, keyOrMsg = Items.adminCreateCode(0, coins)
    return success and keyOrMsg or nil
end)
