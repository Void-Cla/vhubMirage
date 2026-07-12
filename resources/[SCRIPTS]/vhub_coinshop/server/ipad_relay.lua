-- server/ipad_relay.lua — app CoinShop no iPad (broker vhub_ipad): relay zero-trust + push
--
-- Superfície JOGADOR: navegar catálogo, comprar item/oferta, resgatar código, test-drive, Pix.
-- Superfície ADMIN:   CRUD itens/cats/deals/códigos, dar moedas, stats, import, settings.
-- REGRA 1 do manual: corpo em CreateThread (yield não cruza a fronteira C do export).
-- REGRA 2: src é a única identidade; toda ação revalida char + rate server-side.

VHubCoin = VHubCoin or {}
local Core  = VHubCoin.Core
local Coins = VHubCoin.Coins
local Items = VHubCoin.Items
local Purch = VHubCoin.Purchases

local APP_ID = 'coinshop'


-- ============================================================
-- HELPERS — push ao app (owner-binding do broker) + sanitização
-- ============================================================

-- empurra dados de volta ao app do iPad (pcall na fronteira externa — R7)
local function push(src, action, data)
    pcall(function() return exports.vhub_ipad:appPush(src, APP_ID, action, data) end)
end

-- resposta padrão de ação: { ok, action, message }
local function pushResult(src, action, okFlag, message)
    push(src, 'result', { ok = okFlag == true, action = action, message = tostring(message or '') })
end

-- string sã do payload NUI: tostring + trim + cap (anti-DoS de domínio)
local function str(v, cap)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    return s:sub(1, cap or 64)
end

-- guard de admin: push 'denied' e retorna false se não for admin
local function requireAdmin(src)
    if Core.isAdmin(src) then return true end
    push(src, 'denied', { reason = 'sem_permissao' })
    return false
end


-- ============================================================
-- AÇÕES JOGADOR — cada uma revalida rate + char (zero-trust, L-01)
-- ============================================================

local actions = {}

-- último snapshot servido por src — quando o rate barra, serve o cache em vez de
-- silêncio (o "app abre vazio" do bug (b) #59); limpo em playerDropped
local _lastSnap = {}

-- invalida o snapshot em cache do src (chamado por Coins.notifyChange para garantir
-- que a próxima abertura do iPad após doação/set de coins não sirva dado stale)
function VHubCoin.IpadRelay_InvalidateSnap(src)
    if src then _lastSnap[src] = nil end
end

-- sincroniza o catálogo alterado para tablets abertos sem criar estado paralelo
function VHubCoin.IpadRelay_PushCatalog()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then
            local ok, open = pcall(function() return exports.vhub_ipad:isOpen(src) end)
            local charId = ok and open and Core.getCharId(src) or nil
            if charId then
                local isAdm = Core.isAdmin(src)
                local snap = Core.buildShopData(src, charId, isAdm)
                _lastSnap[src] = snap
                push(src, 'data', snap)
            end
        end
    end
end

-- abre o app: snapshot da loja (com isAdmin quando for admin)
actions.open = function(src, char_id, _)
    if not Core.rate(src, 'openShop', VHubCoin.cfg.rates.openShop) then
        if _lastSnap[src] then
            push(src, 'data', _lastSnap[src])
        else
            pushResult(src, 'open', false, 'Aguarde um instante e tente de novo.')
        end
        return
    end
    local isAdm = Core.isAdmin(src)
    local snap = Core.buildShopData(src, char_id, isAdm)
    _lastSnap[src] = snap
    push(src, 'data', snap)
end

-- compra item do catálogo (mesmo domínio da NUI fullscreen — escritor único)
actions.buy_item = function(src, char_id, data)
    if not Core.rate(src, 'purchaseItem', VHubCoin.cfg.rates.purchaseItem) then
        return pushResult(src, 'buy_item', false, T('purchase_in_progress'))
    end
    local itemId = str(data.itemId)
    if not itemId then return pushResult(src, 'buy_item', false, T('item_not_found')) end

    local okBuy, message = Purch.buyItem(src, char_id, itemId)
    pushResult(src, 'buy_item', okBuy, message)
    push(src, 'coins', { coins = Coins.get(char_id) })
end

-- compra oferta promocional
actions.buy_deal = function(src, char_id, data)
    if not Core.rate(src, 'purchaseDeal', VHubCoin.cfg.rates.purchaseDeal) then
        return pushResult(src, 'buy_deal', false, T('purchase_in_progress'))
    end
    local dealId = str(data.dealId)
    if not dealId then return pushResult(src, 'buy_deal', false, T('deal_not_found')) end

    local okBuy, message = Purch.buyDeal(src, char_id, dealId)
    pushResult(src, 'buy_deal', okBuy, message)
    push(src, 'coins', { coins = Coins.get(char_id) })
end

-- resgata código Tebex (targetId opcional = presente para jogador online)
actions.redeem = function(src, char_id, data)
    if not Core.rate(src, 'redeemCode', VHubCoin.cfg.rates.redeemCode) then
        return pushResult(src, 'redeem', false, T('purchase_in_progress'))
    end
    local redeemKey = str(data.redeemKey, 100)
    if not redeemKey then return pushResult(src, 'redeem', false, T('invalid_order_number')) end
    local targetId = str(data.targetId, 8)

    local okRedeem, message = Purch.redeemCode(src, char_id, redeemKey, targetId)
    pushResult(src, 'redeem', okRedeem, message)
    push(src, 'coins', { coins = Coins.get(char_id) })
end

-- compra de moedas via Pix (#60)
actions.pix_create = function(src, char_id, data)
    if not Core.rate(src, 'purchaseItem', VHubCoin.cfg.rates.purchaseItem) then
        return push(src, 'pix', { ok = false, code = 'rate', message = T('purchase_in_progress') })
    end

    local packageId = str(data.packageId)
    local pack = nil
    for _, p in ipairs(VHubCoin.cfg.pix.packages) do
        if p.id == packageId then pack = p break end
    end
    if not pack then
        return push(src, 'pix', { ok = false, code = 'pacote_invalido', message = 'Pacote não encontrado.' })
    end

    if VHubCoin.cfg.pix.enabled ~= true then
        return push(src, 'pix', {
            ok = false, code = 'pix_disabled',
            message = 'Pagamento Pix ainda não está habilitado nesta cidade. Fale com a staff.',
        })
    end

    if VHubCoin.cfg.pix.provider == 'mercadopago' and VHubCoin.Pix and VHubCoin.Pix.handleCreate then
        VHubCoin.Pix.handleCreate(src, char_id, pack, push)
        return
    end

    Core.logErr('pix_create: cfg.pix.enabled=true mas provider desconhecido: ' .. tostring(VHubCoin.cfg.pix.provider))
    push(src, 'pix', { ok = false, code = 'pix_sem_provider', message = 'Pix indisponível no momento.' })
end

-- ============================================================
-- AÇÕES ADMIN — todas exigem requireAdmin(src) antes de qualquer op
-- ============================================================

-- retorna snapshot com isAdmin=true (inclui logo, avatar, campos admin)
actions.admin_open = function(src, char_id, _)
    if not requireAdmin(src) then return end
    local snap = Core.buildShopData(src, char_id, true)
    _lastSnap[src] = snap
    push(src, 'data', snap)
end

-- estatísticas do painel admin (totais, receita, resgates)
actions.admin_stats = function(src, _, _)
    if not requireAdmin(src) then return end
    local stats = Items.adminStats()
    push(src, 'admin_stats', { ok = true, data = stats })
end

-- transações recentes
actions.admin_recent_tx = function(src, _, _)
    if not requireAdmin(src) then return end
    local rows = Items.recentTransactions()
    push(src, 'admin_recent_tx', { ok = true, data = rows })
end

-- itens mais vendidos
actions.admin_top_selling = function(src, _, _)
    if not requireAdmin(src) then return end
    local rows = Items.topSelling()
    push(src, 'admin_top_selling', { ok = true, data = rows })
end

-- histórico de compras (últimas 50)
actions.admin_purchase_history = function(src, _, _)
    if not requireAdmin(src) then return end
    local rows = Items.purchaseHistory()
    push(src, 'admin_purchase_history', { ok = true, data = rows })
end

-- lista jogadores online com nome + coins
actions.admin_online_players = function(src, _, _)
    if not requireAdmin(src) then return end
    local players = {}
    for _, id in ipairs(GetPlayers()) do
        local pid = tonumber(id)
        if pid then
            local charId = Core.getCharId(pid)
            if charId then
                players[#players + 1] = {
                    src    = pid,
                    name   = Core.getPlayerName(pid),
                    coins  = Coins.get(charId),
                    charId = charId,
                }
            end
        end
    end
    push(src, 'admin_online_players', { ok = true, data = players })
end

-- dá moedas a jogador online
actions.admin_give_coins = function(src, _, data)
    if not requireAdmin(src) then return end
    local targetId = tonumber(data.targetId)
    local amount   = tonumber(data.amount)
    if not targetId or not amount or amount <= 0 then
        return push(src, 'admin_give_coins', { ok = false, err = 'args_invalidos' })
    end
    local targetChar = Core.getCharId(targetId)
    if not targetChar then
        return push(src, 'admin_give_coins', { ok = false, err = T('player_not_found') })
    end
    if not Coins.credit(targetChar, amount) then
        return push(src, 'admin_give_coins', { ok = false, err = T('coin_persistence_failed') })
    end
    Coins.notifyChange(targetId, targetChar)
    Core.notify(targetId, T('received_coins', amount), 'success')
    push(src, 'admin_give_coins', { ok = true, coins = Coins.get(targetChar) })
    push(src, 'admin_online_players', { ok = true, data = {} }) -- sinaliza re-fetch
    VHubCoin.IpadRelay_InvalidateSnap(src)
end

-- define saldo absoluto de moedas
actions.admin_set_coins = function(src, _, data)
    if not requireAdmin(src) then return end
    local targetId = tonumber(data.targetId)
    local amount   = tonumber(data.amount)
    if not targetId or amount == nil or amount < 0 then
        return push(src, 'admin_set_coins', { ok = false, err = 'args_invalidos' })
    end
    local targetChar = Core.getCharId(targetId)
    if not targetChar then
        return push(src, 'admin_set_coins', { ok = false, err = T('player_not_found') })
    end
    if not Coins.set(targetChar, amount) then
        return push(src, 'admin_set_coins', { ok = false, err = T('coin_persistence_failed') })
    end
    Coins.notifyChange(targetId, targetChar)
    Core.notify(targetId, T('coins_set_to', amount), 'info')
    push(src, 'admin_set_coins', { ok = true, coins = Coins.get(targetChar) })
    VHubCoin.IpadRelay_InvalidateSnap(src)
end

-- cria item no catálogo
actions.admin_create_item = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminCreate(src, data)
    push(src, 'admin_create_item', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- edita item existente
actions.admin_edit_item = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminEdit(src, data)
    push(src, 'admin_edit_item', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- remove item do catálogo
actions.admin_delete_item = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminDelete(src, data)
    push(src, 'admin_delete_item', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- cria categoria
actions.admin_create_cat = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminCreateCategory(src, data)
    push(src, 'admin_create_cat', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- edita categoria
actions.admin_edit_cat = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminEditCategory(src, data)
    push(src, 'admin_edit_cat', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- remove categoria
actions.admin_delete_cat = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminDeleteCategory(src, data)
    push(src, 'admin_delete_cat', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- cria deal/oferta
actions.admin_create_deal = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminCreateDeal(src, data)
    push(src, 'admin_create_deal', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- edita deal/oferta
actions.admin_edit_deal = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminEditDeal(src, data)
    push(src, 'admin_edit_deal', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- remove deal/oferta
actions.admin_delete_deal = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminDeleteDeal(src, data)
    push(src, 'admin_delete_deal', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- cria código Tebex
actions.admin_create_code = function(src, _, data)
    if not requireAdmin(src) then return end
    local coins  = tonumber(data.coins)
    local orderId = str(data.orderId, 100)
    if not coins or coins <= 0 or not orderId then
        return push(src, 'admin_create_code', { ok = false, err = 'args_invalidos' })
    end
    local ok, msg = Items.adminCreateCode(src, { coins = coins, orderId = orderId })
    push(src, 'admin_create_code', { ok = ok, err = not ok and msg or nil })
end

-- lista todos os códigos Tebex
actions.admin_list_codes = function(src, _, _)
    if not requireAdmin(src) then return end
    local codes = Items.adminListCodes()
    push(src, 'admin_list_codes', { ok = true, data = codes })
end

-- remove código Tebex (somente pending)
actions.admin_delete_code = function(src, _, data)
    if not requireAdmin(src) then return end
    local codeId = tonumber(data.codeId)
    if not codeId then return push(src, 'admin_delete_code', { ok = false, err = 'id_invalido' }) end
    local ok, msg = Items.adminDeleteCode(src, { id = codeId })
    push(src, 'admin_delete_code', { ok = ok, err = not ok and msg or nil })
end

-- limpa todo o catálogo (itens + cats + deals)
actions.admin_clear_all = function(src, _, _)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminClearAll(src)
    push(src, 'admin_clear_all', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- salva configurações visuais (UI)
actions.admin_save_settings = function(src, _, data)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminSaveSettings(src, data)
    push(src, 'admin_save_settings', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- reseta configurações visuais para padrão
actions.admin_reset_settings = function(src, _, _)
    if not requireAdmin(src) then return end
    local ok, msg = Items.adminResetSettings(src)
    push(src, 'admin_reset_settings', { ok = ok, err = not ok and msg or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end

-- retorna snapshot de veículos da concessionária (para o picker admin de spawn_name)
actions.admin_list_conce_vehicles = function(src, _, _)
    if not requireAdmin(src) then return end
    if not Core.rate(src, 'adminCatalog', VHubCoin.cfg.rates.adminCatalog) then
        return push(src, 'admin_list_conce_vehicles', { ok = false, err = 'rate_limit' })
    end
    local ok, rows = pcall(function() return exports.vhub_conce:getCatalogSnapshot() end)
    push(src, 'admin_list_conce_vehicles', {
        ok   = ok and type(rows) == 'table',
        data = (ok and type(rows) == 'table') and rows or {},
    })
end

-- retorna itens do inventário (para o picker admin de item_name / weapon_name)
actions.admin_list_inventory_items = function(src, _, _)
    if not requireAdmin(src) then return end
    if not Core.rate(src, 'adminCatalog', VHubCoin.cfg.rates.adminCatalog) then
        return push(src, 'admin_list_inventory_items', { ok = false, err = 'rate_limit' })
    end
    local ok, rows = pcall(function() return exports.vhub_inventory:getItemsSnapshot() end)
    push(src, 'admin_list_inventory_items', {
        ok   = ok and type(rows) == 'table',
        data = (ok and type(rows) == 'table') and rows or {},
    })
end

-- preview de importação (sem persistir)
actions.admin_import_preview = function(src, _, data)
    if not requireAdmin(src) then return end
    if not (VHubCoin.Import and VHubCoin.Import.preview) then
        return push(src, 'admin_import_preview', { ok = false, err = 'import_indisponivel' })
    end
    local ok, result = VHubCoin.Import.preview(src, data)
    push(src, 'admin_import_preview', { ok = ok, data = result, err = not ok and result or nil })
end

-- executa importação em massa
actions.admin_import_run = function(src, _, data)
    if not requireAdmin(src) then return end
    if not (VHubCoin.Import and VHubCoin.Import.run) then
        return push(src, 'admin_import_run', { ok = false, err = 'import_indisponivel' })
    end
    local ok, result = VHubCoin.Import.run(src, data)
    push(src, 'admin_import_run', { ok = ok, data = result, err = not ok and result or nil })
    if ok then VHubCoin.IpadRelay_PushCatalog() end
end


-- ============================================================
-- EXPORT ipadRelay — receptor único das ações do app (broker opaco)
-- ============================================================

exports('ipadRelay', function(src, action, data)
    if type(src) ~= 'number' or not GetPlayerName(src) then return false end
    if type(action) ~= 'string' or not actions[action] then return false end
    data = (type(data) == 'table') and data or {}

    CreateThread(function()                     -- REGRA 1: yield nunca cruza o export
        local ok, err = pcall(function()
            local char_id = Core.getCharId(src) -- REGRA 2: identidade só do server
            if not char_id then
                return push(src, 'denied', { reason = 'sem_char' })
            end
            actions[action](src, char_id, data)
        end)
        if not ok then
            Core.logErr(('ipadRelay %s (src=%s) estourou: %s'):format(action, tostring(src), tostring(err)))
            pushResult(src, action, false, 'falha interna — avise um admin')
        end
    end)

    return true   -- resposta imediata; resultado volta por appPush
end)


-- limpa o snapshot em cache do jogador que saiu (sem leak por src)
AddEventHandler('playerDropped', function()
    _lastSnap[source] = nil
end)
