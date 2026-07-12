-- server/commands.lua — comandos admin (coinshop, givecoins, setcoins, coinshop_addcode)

VHubCoin = VHubCoin or {}
local Core  = VHubCoin.Core
local Coins = VHubCoin.Coins


-- ============================================================
-- /coinshop — abre o iPad no app CoinShop (admin vê painel completo) — ADMIN-ONLY
-- Jogador comum usa o app CoinShop do iPad via catálogo do tablet.
-- restricted=false: Core.isAdmin cobre owner uid=1 > ACE vhub.coinshop.admin > vhub_groups.
-- ============================================================

RegisterCommand(VHubCoin.cfg.command, function(source)
    local src = source
    if src == 0 then
        print('[vhub_coinshop] /coinshop abre o iPad — use in-game (admin)')
        return
    end
    if not Core.isAdmin(src) then
        Core.notify(src, T('no_permission'), 'error')
        return
    end
    pcall(function() exports.vhub_ipad:openIpad(src) end)
end, false)


-- ============================================================
-- /givecoins [id] [quantidade] — admin dá moedas a um jogador online
-- ============================================================

RegisterCommand('givecoins', function(source, args)
    local src = source
    if src ~= 0 and not Core.isAdmin(src) then
        Core.notify(src, T('no_permission'), 'error')
        return
    end

    local targetId = tonumber(args[1])
    local amount   = tonumber(args[2])
    if not (targetId and amount) or amount <= 0 then
        local msg = T('usage_givecoins')
        if src ~= 0 then Core.notify(src, msg) else print(msg) end
        return
    end

    local targetChar = Core.getCharId(targetId)
    if not targetChar then
        local msg = T('player_not_found')
        if src ~= 0 then Core.notify(src, msg) else print(msg) end
        return
    end

    local oldCoins = Coins.get(targetChar)
    if not Coins.credit(targetChar, amount) then
        local msg = T('coin_persistence_failed')
        if src ~= 0 then Core.notify(src, msg, 'error') else print(msg) end
        return
    end
    Coins.notifyChange(targetId, targetChar)
    Core.notify(targetId, T('received_coins', amount), 'success')

    VHubCoin.Webhooks.fire('admin', 'Comando: Give Coins', nil, {
        { name = 'Executado Por', value = (src ~= 0 and (Core.getPlayerName(src) .. ' (ID: ' .. src .. ')')) or 'Console', inline = true },
        { name = 'Alvo',          value = Core.getPlayerName(targetId) .. ' (ID: ' .. targetId .. ')', inline = true },
        { name = 'Quantidade',    value = '+' .. tostring(amount) .. ' moedas', inline = true },
        { name = 'Novo Saldo',    value = tostring(oldCoins + amount), inline = true },
    })

    local msg = T('gave_coins', amount, targetId)
    if src ~= 0 then Core.notify(src, msg) else print(msg) end
end, false)


-- ============================================================
-- /setcoins [id] [quantidade] — admin define saldo absoluto
-- ============================================================

RegisterCommand('setcoins', function(source, args)
    local src = source
    if src ~= 0 and not Core.isAdmin(src) then
        Core.notify(src, T('no_permission'), 'error')
        return
    end

    local targetId = tonumber(args[1])
    local amount   = tonumber(args[2])
    if not (targetId and amount) or amount < 0 then
        local msg = T('usage_setcoins')
        if src ~= 0 then Core.notify(src, msg) else print(msg) end
        return
    end

    local targetChar = Core.getCharId(targetId)
    if not targetChar then
        local msg = T('player_not_found')
        if src ~= 0 then Core.notify(src, msg) else print(msg) end
        return
    end

    local oldCoins = Coins.get(targetChar)
    if not Coins.set(targetChar, amount) then
        local msg = T('coin_persistence_failed')
        if src ~= 0 then Core.notify(src, msg, 'error') else print(msg) end
        return
    end
    Coins.notifyChange(targetId, targetChar)
    Core.notify(targetId, T('coins_set_to', amount), 'info')

    VHubCoin.Webhooks.fire('admin', 'Comando: Set Coins', nil, {
        { name = 'Executado Por', value = (src ~= 0 and (Core.getPlayerName(src) .. ' (ID: ' .. src .. ')')) or 'Console', inline = true },
        { name = 'Alvo',          value = Core.getPlayerName(targetId) .. ' (ID: ' .. targetId .. ')', inline = true },
        { name = 'Mudança',       value = tostring(oldCoins) .. ' → ' .. tostring(amount), inline = true },
    })

    local msg = T('set_coins_msg', targetId, amount)
    if src ~= 0 then Core.notify(src, msg) else print(msg) end
end, false)


-- ============================================================
-- /coinshop_addcode <order_number> <coins> — cria código Tebex (console/agent)
-- ============================================================

RegisterCommand('coinshop_addcode', function(source, args)
    local src = tonumber(source) or 0
    if src > 0 and not Core.isAdmin(src) then
        Core.logErr('coinshop_addcode rejeitado: precisa ser console ou admin in-game')
        return
    end

    local orderId = args[1]
    local coins   = tonumber(args[2])
    if not VHubCoin.isNonEmptyStr(orderId) or not coins or coins <= 0 then
        print('[vhub_coinshop] Uso: coinshop_addcode <order_number> <coins>')
        return
    end

    CreateThread(function()
        local exists = SQL.scalar('SELECT id FROM vhub_coinshop_codes WHERE tbx_id = ?', { orderId })
        if exists then
            print('[vhub_coinshop] Código já existe: ' .. orderId)
            return
        end
        SQL.insert(
            'INSERT INTO vhub_coinshop_codes (tbx_id, coins, status) VALUES (?, ?, ?)',
            { orderId, coins, 'pending' }
        )
        print(('[vhub_coinshop] Código criado | Pedido: %s | Moedas: %s'):format(orderId, tostring(coins)))
    end)
end, false)
