-- server/purchases.lua — compras de itens/ofertas e resgate de códigos Tebex (server-authoritative, atômico)

VHubCoin = VHubCoin or {}
local Core   = VHubCoin.Core
local Coins  = VHubCoin.Coins
local Items  = VHubCoin.Items
local Purch  = {}
VHubCoin.Purchases = Purch


-- ============================================================
-- HELPERS DE ENTREGA — item/arma/veículo
-- ============================================================

-- entrega um item de inventário via exports.vhub_inventory (pcall na fronteira externa — R7)
-- giveItem retorna boolean estrito: false = negado/falhou → NÃO conta como entrega
local function deliverItem(src, itemName, count)
    if not VHubCoin.isNonEmptyStr(itemName) then return false end
    local ok, res = pcall(function()
        return exports.vhub_inventory:giveItem(src, itemName, VHubCoin.clamp(count or 1, 1, 1000))
    end)
    return ok and res == true
end

-- entrega uma arma equipando no ped via vhub_hss (dono do ped).
-- DÍVIDA TÉCNICA: arma de SESSÃO — não persiste no relog/respawn. Persistência de
-- arma é domínio futuro (vhub_weapon_state, ainda inexistente). A UI do coinshop
-- deve indicar "arma de sessão". (Decisão do arquiteto — fronteira F3.)
local function deliverWeapon(src, weaponName, ammo)
    if not VHubCoin.isNonEmptyStr(weaponName) then return false end
    local weapons = { [weaponName] = { ammo = VHubCoin.clamp(ammo or 250, 0, 9999) } }
    local ok, delivered = pcall(function()
        return exports.vhub_hss:giveWeapons(src, weapons, false)
    end)
    return ok and delivered == true
end

-- concede o veículo comprado via exports.vhub_conce:grantVehicle (escritor único da
-- placa/chave/registro — Doutrina da Placa). grantVehicle NÃO cobra: o débito de
-- moedas é feito por buyItem ANTES (e estornado se aqui falhar). (Fronteira F2.)
-- retorna placa ou nil
local function deliverVehicle(src, spawnName)
    if not VHubCoin.isNonEmptyStr(spawnName) then return nil end

    local ok, res = pcall(function()
        return exports.vhub_conce:grantVehicle(src, spawnName)
    end)
    if ok and type(res) == 'table' and res.ok and VHubCoin.isNonEmptyStr(res.plate) then
        return res.plate
    end

    local code = (type(res) == 'table' and res.code) or 'export_fail'
    Core.logErr('deliverVehicle: grantVehicle falhou; spawnName=', spawnName, 'code=', code)
    return nil
end


-- ============================================================
-- COMPRA DE ITEM
-- ============================================================

-- compra um item do catálogo (validação → debit atômico → entrega → audit)
function Purch.buyItem(src, char_id, itemId)
    if not char_id or not VHubCoin.isNonEmptyStr(itemId) then
        return false, T('item_not_found')
    end
    if Coins.isLocked(char_id) then return false, T('purchase_in_progress') end

    local item = Items.find(itemId)
    if not item or item.published ~= true then return false, T('item_not_found') end

    local currentBalance = Coins.get(char_id)
    if currentBalance < item.price then return false, T('not_enough_coins') end

    -- debit atômico (lock + setCData)
    if not Coins.tryDebit(char_id, item.price) then
        return false, T('purchase_in_progress')
    end

    -- entrega por categoria (falha → reembolso atômico)
    local delivered = false
    local successMessage = T('purchase_successful')
    if item.category == 'vehicle' then
        local plate = deliverVehicle(src, item.spawnName)
        if plate then
            delivered = true
            successMessage = T('vehicle_purchased', plate)
        end
    elseif item.category == 'weapon' then
        if VHubCoin.isNonEmptyStr(item.itemName) then
            delivered = deliverItem(src, item.itemName, item.itemCount or 1)
        elseif VHubCoin.isNonEmptyStr(item.weaponName) then
            delivered = deliverWeapon(src, item.weaponName, 250)
        end
    elseif item.category == 'item' or item.category == 'tool' then
        if VHubCoin.isNonEmptyStr(item.itemName) then
            delivered = deliverItem(src, item.itemName, item.itemCount or 1)
        end
    end

    if not delivered then
        -- reembolso (credita de volta)
        local refunded = Coins.credit(char_id, item.price)
        Coins.releaseLock(char_id)
        if not refunded then
            Core.logErr('reembolso de compra falhou char=' .. tostring(char_id) .. ' item=' .. itemId)
            return false, T('coin_persistence_failed')
        end
        local reason = item.category == 'vehicle' and T('failed_register_vehicle') or T('failed_give_item')
        return false, reason
    end

    -- audit (fire-and-forget; não bloqueia a resposta)
    SQL.execute(
        'INSERT INTO vhub_coinshop_purchases (char_id, item_id, price) VALUES (?, ?, ?)',
        { char_id, itemId, item.price }
    )
    Coins.releaseLock(char_id)

    -- notifica cliente do novo saldo
    Coins.notifyChange(src, char_id)

    -- webhook de auditoria
    VHubCoin.Webhooks.fire('purchases', 'Item Comprado', nil, {
        { name = 'Jogador',     value = Core.getPlayerName(src) .. ' (ID: ' .. src .. ')', inline = true },
        { name = 'Char ID',     value = tostring(char_id),                                  inline = true },
        { name = 'Item',        value = item.name .. ' (`' .. itemId .. '`)',               inline = false },
        { name = 'Categoria',   value = item.category,                                      inline = true },
        { name = 'Preço',       value = tostring(item.price) .. ' moedas',                  inline = true },
        {
            name = 'Saldo',
            value = tostring(currentBalance) .. ' → ' .. tostring(currentBalance - item.price),
            inline = true,
        },
    })

    return true, successMessage
end


-- ============================================================
-- COMPRA DE OFERTA (DEAL)
-- ============================================================

-- compra uma oferta promocional (vários itens, preço único)
function Purch.buyDeal(src, char_id, dealId)
    if not char_id or not VHubCoin.isNonEmptyStr(dealId) then
        return false, T('deal_not_found')
    end
    if Coins.isLocked(char_id) then return false, T('purchase_in_progress') end

    -- busca a oferta no cache (já filtrada por expiração)
    local deal
    for _, d in ipairs(Items.deals) do
        if d.id == dealId then deal = d break end
    end
    if not deal then return false, T('deal_not_found') end
    if #deal.items == 0 then return false, T('deal_no_items') end
    for _, dealItem in ipairs(deal.items) do
        local listed = Items.find(dealItem.id)
        if not listed or listed.published ~= true then return false, T('deal_not_found') end
    end

    local currentBalance = Coins.get(char_id)
    if currentBalance < deal.price then return false, T('not_enough_coins') end

    if not Coins.tryDebit(char_id, deal.price) then
        return false, T('purchase_in_progress')
    end

    -- entrega cada item; coleta falhas (parcial = mantém, total = reembolso)
    local failedItems = {}
    for _, dealItem in ipairs(deal.items) do
        local item = Items.find(dealItem.id)
        if not item then
            failedItems[#failedItems + 1] = dealItem.id
        elseif item.category == 'vehicle' then
            local plate = deliverVehicle(src, item.spawnName)
            if plate then
                Core.notify(src, T('vehicle_purchased', plate), 'success')
            else
                failedItems[#failedItems + 1] = item.name
            end
        elseif item.category == 'weapon' then
            local ok = false
            if VHubCoin.isNonEmptyStr(item.itemName) then
                ok = deliverItem(src, item.itemName, item.itemCount or 1)
            elseif VHubCoin.isNonEmptyStr(item.weaponName) then
                ok = deliverWeapon(src, item.weaponName, 250)
            end
            if not ok then failedItems[#failedItems + 1] = item.name end
        elseif item.category == 'item' or item.category == 'tool' then
            local ok = VHubCoin.isNonEmptyStr(item.itemName)
                and deliverItem(src, item.itemName, item.itemCount or 1)
                or false
            if not ok then failedItems[#failedItems + 1] = item.name end
        end
    end

    -- TODOS falharam → reembolso total
    if #failedItems == #deal.items then
        local refunded = Coins.credit(char_id, deal.price)
        Coins.releaseLock(char_id)
        if not refunded then
            Core.logErr('reembolso de oferta falhou char=' .. tostring(char_id) .. ' deal=' .. dealId)
            return false, T('coin_persistence_failed')
        end
        return false, T('failed_give_item')
    end

    -- falhas parciais → notifica mas mantém compra
    if #failedItems > 0 then
        Core.notify(src, 'Alguns itens falharam: ' .. table.concat(failedItems, ', '), 'warning')
    end

    SQL.execute(
        'INSERT INTO vhub_coinshop_purchases (char_id, item_id, price) VALUES (?, ?, ?)',
        { char_id, dealId, deal.price }
    )
    Coins.releaseLock(char_id)
    Coins.notifyChange(src, char_id)

    VHubCoin.Webhooks.fire('purchases', 'Oferta Comprada', nil, {
        { name = 'Jogador', value = Core.getPlayerName(src) .. ' (ID: ' .. src .. ')', inline = true },
        { name = 'Char ID', value = tostring(char_id), inline = true },
        { name = 'Oferta',  value = deal.name .. ' (`' .. dealId .. '`)', inline = false },
        { name = 'Itens',   value = tostring(#deal.items) .. ' item(ns)', inline = true },
        { name = 'Preço',   value = tostring(deal.price) .. ' moedas', inline = true },
        {
            name = 'Saldo',
            value = tostring(currentBalance) .. ' → ' .. tostring(currentBalance - deal.price),
            inline = true,
        },
    })

    return true, T('deal_purchased')
end


-- ============================================================
-- RESGATE DE CÓDIGO TEBEX
-- ============================================================

-- resgata um código Tebex (idempotente: status pending→redeemed atômico via UPDATE condicional)
function Purch.redeemCode(src, char_id, redeemKey, targetId)
    if not char_id or not VHubCoin.isNonEmptyStr(redeemKey) then
        return false, T('invalid_order_number')
    end
    local key = tostring(redeemKey):gsub('%s+', '')
    if key == '' then return false, T('invalid_order_number') end

    local rows = SQL.query('SELECT id, coins, status FROM vhub_coinshop_codes WHERE tbx_id = ?', { key })
    if not rows or #rows == 0 then return false, T('invalid_order_detailed') end

    local codeRow = rows[1]
    if codeRow.status == 'redeemed' then return false, T('order_already_redeemed') end

    -- resolve alvo (self ou presente para outro online)
    local targetSrc    = src
    local targetCharId = char_id
    if targetId and targetId ~= '' then
        local targetNum = tonumber(targetId)
        if not targetNum then return false, T('target_not_found') end
        local targetChar = Core.getCharId(targetNum)
        if not targetChar then return false, T('target_not_found') end
        targetSrc    = targetNum
        targetCharId = targetChar
    end

    -- UPDATE condicional atômico: só marca redeemed se ainda estava pending
    local affected = SQL.execute(
        'UPDATE vhub_coinshop_codes SET status = ?, redeemed_by = ?, redeemed_at = NOW() ' ..
        'WHERE tbx_id = ? AND status = ?',
        { 'redeemed', targetCharId, key, 'pending' }
    )
    if not affected or affected == 0 then return false, T('order_already_redeemed') end

    local coinsToAdd = tonumber(codeRow.coins) or 0
    local oldCoins   = Coins.get(targetCharId)
    if not Coins.credit(targetCharId, coinsToAdd) then
        SQL.execute(
            'UPDATE vhub_coinshop_codes SET status = ?, redeemed_by = NULL, redeemed_at = NULL ' ..
            'WHERE tbx_id = ? AND status = ? AND redeemed_by = ?',
            { 'pending', key, 'redeemed', targetCharId }
        )
        Core.logErr('resgate revertido: crédito CData falhou key=' .. key)
        return false, T('coin_persistence_failed')
    end

    -- audit
    SQL.insert(
        'INSERT INTO vhub_coinshop_redeems (char_id, redeem_key, coins_added) VALUES (?, ?, ?)',
        { targetCharId, key, coinsToAdd }
    )

    -- sync de saldo SEMPRE no alvo (self ou presente) — antes o resgate para si
    -- mesmo nunca disparava notifyChange e a UI ficava com saldo stale (#59)
    Coins.notifyChange(targetSrc, targetCharId)
    if targetSrc ~= src then
        Core.notify(targetSrc, T('received_coins_gift', coinsToAdd), 'success')
    end

    VHubCoin.Webhooks.fire('redeems',
        (targetSrc ~= src) and 'Código Resgatado (Presente)' or 'Código Resgatado', nil, {
            { name = 'Resgatado Por', value = Core.getPlayerName(src) .. ' (ID: ' .. src .. ')', inline = true },
            { name = 'Char ID',       value = tostring(char_id), inline = true },
            { name = 'TBX ID',        value = '`' .. key .. '`', inline = false },
            { name = 'Moedas',        value = tostring(coinsToAdd), inline = true },
            { name = 'Novo Saldo',    value = tostring(oldCoins + coinsToAdd), inline = true },
        })

    return true, T('successfully_redeemed', coinsToAdd)
end
