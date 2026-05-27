local VOID = VOID or {}
local Player = VOID.player or {}

if not Player.isEnabled or not Player.isEnabled() then
    return VOID
end

local cfg = Player.cfg or {}
local Tools = module('vrp', 'lib/Tools')
local idgens = Tools.newIDGenerator()

local roupas = module(GetCurrentResourceName(), 'server/player/roupas') or {}

local function canInteract(source, user_id)
    if vRPclient.getHealth(source) <= 101 then return false end
    if vRPclient.isHandcuffed(source) then return false end
    if vRP.searchReturn and vRP.searchReturn(source, user_id) then return false end
    return true
end

local function listInventory(user_id)
    local data = vRP.getUserDataTable(user_id)
    if data and data.inventory then
        local out = {}
        for _, v in pairs(data.inventory) do
            local item = v.item or v.name or v.key
            local amount = v.amount or v.quantidade or 0
            if item and amount and amount > 0 then
                out[#out + 1] = { item = item, amount = amount }
            end
        end
        return out
    end
    local items = VOID.listarMochila and ({ VOID.listarMochila(user_id) }) or nil
    if items and items[1] then
        local out = {}
        for _, v in pairs(items[1]) do
            out[#out + 1] = { item = v.key, amount = v.amount }
        end
        return out
    end
    return {}
end

local function transferInventory(from_id, to_id)
    local list = listInventory(from_id)
    for _, v in ipairs(list) do
        local weight = vRP.getInventoryWeight(to_id) + vRP.getItemWeight(v.item) * v.amount
        if weight <= vRP.getInventoryMaxWeight(to_id) then
            if vRP.tryGetInventoryItem(from_id, v.item, v.amount) then
                vRP.giveInventoryItem(to_id, v.item, v.amount)
            end
        end
    end
end

local function transferWeapons(from_player, to_id)
    local weapons = vRPclient.replaceWeapons(from_player, {})
    for weapon, info in pairs(weapons or {}) do
        vRP.giveInventoryItem(to_id, 'wbody|' .. weapon, 1)
        local ammo = info.ammo or 0
        if ammo > 0 then
            vRP.giveInventoryItem(to_id, 'wammo|' .. weapon, ammo)
        end
    end
end

RegisterCommand('item', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    if not vRP.hasPermission(user_id, 'admin.permissao') then return end
    local item = args[1]
    local amount = Player.safeNumber(args[2], 1)
    if not item then return end
    vRP.giveInventoryItem(user_id, item, amount)
    local identity = vRP.getUserIdentity(user_id) or {}
    local msg = string.format('[ID]: %s %s %s [PEGOU]: %s [QTD]: %s', user_id, identity.name or '', identity.firstname or '', item, vRP.format(amount))
    Player.sendWebhook(Player.getWebhook('give'), msg)
end)

RegisterCommand('uservehs', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id or not vRP.hasPermission(user_id, 'admin.permissao') then return end
    local nuser_id = parseInt(args[1])
    if not nuser_id then return end
    local vehicle = vRP.query('creative/get_vehicle', { user_id = nuser_id })
    if not vehicle then return end
    local car_names = {}
    for _, v in pairs(vehicle) do
        car_names[#car_names + 1] = '<b>' .. vRP.vehicleName(v.vehicle) .. '</b>'
    end
    local identity = vRP.getUserIdentity(nuser_id) or {}
    TriggerClientEvent('Notify', source, 'importante', 'Veiculos de ' .. (identity.name or '') .. ' ' .. (identity.firstname or '') .. ': ' .. table.concat(car_names, ', '))
end)

RegisterCommand('reskin', function(source)
    local custom = vRPclient.getCustomization(source)
    vRPclient._setCustomization(source, custom)
end)

RegisterCommand('invasao', function(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local x, y, z = vRPclient.getPosition(source)
    if vRPclient.getHealth(source) <= 100 then return end
    if not (vRP.hasPermission(user_id, 'ada.permissao') or vRP.hasPermission(user_id, 'tcp.permissao') or vRP.hasPermission(user_id, 'cv.permissao') or vRP.hasPermission(user_id, 'milicia.permissao')) then
        return
    end
    local policia = vRP.getUsersByPermission('policia.permissao')
    for _, id in pairs(policia) do
        local player = vRP.getUserSource(parseInt(id))
        if player and player ~= source then
            async(function()
                local blip = vRPclient.addBlip(player, x, y, z, 437, 27, 'Localizacao da invasao', 0.8, false)
                TriggerClientEvent('Notify', player, 'negado', 'Localizacao de invasao recebida.')
                vRPclient._playSound(player, '5s_To_Event_Start_Countdown', 'GTAO_FM_Events_Soundset')
                SetTimeout(60000, function()
                    vRPclient.removeBlip(player, blip)
                end)
            end)
        end
    end
    TriggerClientEvent('Notify', source, 'sucesso', 'Localizacao enviada com sucesso.')
end)

RegisterCommand('status', function(source)
    local online = GetNumPlayerIndices()
    local policia = vRP.getUsersByPermission('policia.permissao')
    local paramedico = vRP.getUsersByPermission('paramedico.permissao')
    local mecanico = vRP.getUsersByPermission('mecanico.permissao')
    local staff = vRP.getUsersByPermission('wl.permissao')
    local msg = string.format('<b>Jogadores</b>: %d<br><b>Administracao</b>: %d<br><b>Policiais</b>: %d<br><b>Paramedicos</b>: %d<br><b>Mecanicos</b>: %d', online, #staff, #policia, #paramedico, #mecanico)
    TriggerClientEvent('Notify', source, 'importante', msg, 9000)
end)

RegisterCommand('id', function(source)
    local nplayer = vRPclient.getNearestPlayer(source, 2)
    local nuser_id = vRP.getUserId(nplayer)
    if not nuser_id then return end
    local identity = vRP.getUserIdentity(nuser_id)
    if not identity then return end
    vRPclient.setDiv(source, 'completerg', '.div_completerg { background-color: rgba(0,0,0,0.60); font-size: 13px; font-family: arial; color: #fff; width: 420px; padding: 20px 20px 5px; bottom: 8%; right: 2.5%; position: absolute; border: 1px solid rgba(255,255,255,0.2); letter-spacing: 0.5px; } .local { width: 220px; padding-bottom: 15px; float: left; } .local2 { width: 200px; padding-bottom: 15px; float: left; } .local b, .local2 b { color: #d1257d; }', '<div class="local"><b>Passaporte:</b> ( ' .. vRP.format(identity.user_id) .. ' )</div>')
    vRP.request(source, 'Deseja fechar o registro geral?', 1000)
    vRPclient.removeDiv(source, 'completerg')
end)

RegisterCommand('equipar', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local weapon = args[1]
    if not weapon or weapon == 'mochila' then return end
    if not string.find(weapon, 'wbody|') then
        weapon = 'wbody|' .. weapon
    end
    if vRP.tryGetInventoryItem(user_id, weapon, 1) then
        local give = {}
        local gun = weapon:gsub('wbody|', '')
        give[gun] = { ammo = 0 }
        vRPclient._giveWeapons(source, give)
        Player.sendWebhook(Player.getWebhook('equipar'), '[ID]: ' .. user_id .. ' EQUIPOU: ' .. weapon)
    else
        Player.notify(source, 'negado', 'Armamento nao encontrado.')
    end
end)

RegisterCommand('moc', function(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    TriggerClientEvent('chatMessage', source, '', {}, '^4- -  ^5M O C H I L A^4  - -')
    local list = listInventory(user_id)
    for _, v in ipairs(list) do
        TriggerClientEvent('chatMessage', source, '', {}, '     ' .. vRP.format(parseInt(v.amount)) .. 'x ' .. Player.getItemLabel(v.item))
    end
end)

RegisterCommand('revistar', function(source)
    local user_id = vRP.getUserId(source)
    local nplayer = vRPclient.getNearestPlayer(source, 2)
    local nuser_id = vRP.getUserId(nplayer)
    if not nuser_id then return end
    TriggerClientEvent('Notify', nplayer, 'aviso', 'Voce esta sendo revistado.')
    local list = listInventory(nuser_id)
    TriggerClientEvent('chatMessage', source, '', {}, '^4- -  ^5M O C H I L A^4  - -')
    for _, v in ipairs(list) do
        TriggerClientEvent('chatMessage', source, '', {}, '     ' .. vRP.format(parseInt(v.amount)) .. 'x ' .. Player.getItemLabel(v.item))
    end
    local weapons = vRPclient.getWeapons(nplayer)
    for k, v in pairs(weapons or {}) do
        if v.ammo and v.ammo > 0 then
            TriggerClientEvent('chatMessage', source, '', {}, '     1x ' .. vRP.itemNameList('wbody|' .. k) .. ' | ' .. vRP.format(parseInt(v.ammo)) .. 'x Municao')
        else
            TriggerClientEvent('chatMessage', source, '', {}, '     1x ' .. vRP.itemNameList('wbody|' .. k))
        end
    end
    local money = vRP.getMoney(nuser_id)
    TriggerClientEvent('chatMessage', source, '', {}, '     $' .. vRP.format(parseInt(money)) .. ' Dolares')
end)

RegisterCommand('sequestro', function(source)
    local nplayer = vRPclient.getNearestPlayer(source, 5)
    if not nplayer then return end
    if vRPclient.isHandcuffed(nplayer) then
        if not vRPclient.getNoCarro(source) then
            local vehicle = vRPclient.getNearestVehicle(source, 7)
            if vehicle and vRPclient.getCarroClass(source, vehicle) then
                vRPclient.setMalas(nplayer)
            end
        elseif vRPclient.isMalas(nplayer) then
            vRPclient.setMalas(nplayer)
        end
    else
        Player.notify(source, 'aviso', 'A pessoa precisa estar algemada para colocar ou retirar do porta-malas.')
    end
end)

RegisterCommand('tratamento', function(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    if not (vRP.hasPermission(user_id, 'paramedico.permissao') or vRP.hasPermission(user_id, 'dono.permissao')) then return end
    local nplayer = vRPclient.getNearestPlayer(source, 3)
    if nplayer and not vRPclient.isComa(nplayer) then
        TriggerClientEvent('tratamento', nplayer)
        Player.notify(source, 'sucesso', 'Tratamento iniciado com sucesso.', 10000)
    end
end)

RegisterCommand('motor', function(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local mPlaca, mName, mNet = vRPclient.ModelName(source, 7)
    local mPlacaUser = vRP.getUserByRegistration(mPlaca)
    if not mPlacaUser then return end
    if not vRP.hasPermission(user_id, 'mecanico.permissao') then return end
    if vRP.tryGetInventoryItem(user_id, 'militec', 1) then
        TriggerClientEvent('cancelando', source, true)
        vRPclient._playAnim(source, false, { { 'mini@repair', 'fixing_a_player' } }, true)
        TriggerClientEvent('progress', source, 10000, 'reparando')
        SetTimeout(10000, function()
            TriggerClientEvent('cancelando', source, false)
            vRPclient._stopAnim(source, false)
            TriggerEvent('trymotor', mNet)
        end)
    end
end)

RegisterCommand('reparar', function(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local mPlaca, mName, mNet = vRPclient.ModelName(source, 7)
    local mPlacaUser = vRP.getUserByRegistration(mPlaca)
    if not mPlacaUser then return end
    if not vRP.hasPermission(user_id, 'mecanico.permissao') then return end
    if vRP.tryGetInventoryItem(user_id, 'repairkit', 1) then
        TriggerClientEvent('cancelando', source, true)
        vRPclient._playAnim(source, false, { { 'mini@repair', 'fixing_a_player' } }, true)
        TriggerClientEvent('progress', source, 10000, 'reparando')
        SetTimeout(10000, function()
            TriggerClientEvent('cancelando', source, false)
            vRPclient._stopAnim(source, false)
            TriggerEvent('tryreparar', mNet)
        end)
    end
end)

RegisterCommand('enviar', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local nplayer = vRPclient.getNearestPlayer(source, 2)
    local nuser_id = vRP.getUserId(nplayer)
    if not nuser_id then
        Player.notify(source, 'negado', 'Nenhum jogador proximo.')
        return
    end

    local amount = tonumber(args[1])
    if amount then
        if vRP.tryPayment(user_id, amount) then
            vRP.giveMoney(nuser_id, amount)
            Player.notify(source, 'sucesso', 'Enviou $' .. vRP.format(amount) .. ' dolares.')
            Player.notify(nplayer, 'sucesso', 'Recebeu $' .. vRP.format(amount) .. ' dolares.')
            Player.sendWebhook(Player.getWebhook('enviar_dinheiro'), '[ID]: ' .. user_id .. ' ENVIOU $' .. vRP.format(amount) .. ' PARA ' .. nuser_id)
        end
        return
    end

    local item = args[1]
    local qtd = Player.safeNumber(args[2], 1)
    if not item then return end
    if vRP.getInventoryWeight(nuser_id) + vRP.getItemWeight(item) * qtd <= vRP.getInventoryMaxWeight(nuser_id) then
        if vRP.tryGetInventoryItem(user_id, item, qtd) then
            vRP.giveInventoryItem(nuser_id, item, qtd)
            Player.notify(source, 'sucesso', 'Enviou ' .. vRP.format(qtd) .. 'x ' .. Player.getItemLabel(item) .. '.')
            Player.notify(nplayer, 'sucesso', 'Recebeu ' .. vRP.format(qtd) .. 'x ' .. Player.getItemLabel(item) .. '.')
            Player.sendWebhook(Player.getWebhook('enviar_item'), '[ID]: ' .. user_id .. ' ENVIOU ' .. vRP.format(qtd) .. 'x ' .. item .. ' PARA ' .. nuser_id)
        end
    else
        Player.notify(source, 'negado', 'Mochila do jogador nao suporta esse peso.')
    end
end)

RegisterCommand('roubar', function(source)
    local user_id = vRP.getUserId(source)
    local nplayer = vRPclient.getNearestPlayer(source, 2)
    if not nplayer then return end
    local nuser_id = vRP.getUserId(nplayer)
    local policia = vRP.getUsersByPermission('policia.permissao')
    if #policia == 0 then
        Player.notify(source, 'aviso', 'Numero insuficiente de policiais no momento.')
        return
    end
    if not vRP.request(nplayer, 'Voce esta sendo roubado, deseja passar tudo?', 30) then
        Player.notify(source, 'importante', 'A pessoa esta resistindo ao roubo.')
        return
    end

    transferInventory(nuser_id, user_id)
    transferWeapons(nplayer, user_id)
    local nmoney = vRP.getMoney(nuser_id)
    if vRP.tryPayment(nuser_id, nmoney) then
        vRP.giveMoney(user_id, nmoney)
    end
    vRPclient.setStandBY(source, parseInt(600))
    Player.notify(source, 'sucesso', 'Roubo concluido com sucesso.')
end)

RegisterCommand('saquear', function(source)
    local user_id = vRP.getUserId(source)
    local nplayer = vRPclient.getNearestPlayer(source, 2)
    if not nplayer then return end
    if not vRPclient.isInComa(nplayer) then return end
    local nuser_id = vRP.getUserId(nplayer)
    local policia = vRP.getUsersByPermission('policia.permissao')
    if #policia == 0 then
        Player.notify(source, 'aviso', 'Numero insuficiente de policiais no momento.')
        return
    end

    transferInventory(nuser_id, user_id)
    transferWeapons(nplayer, user_id)
    local nmoney = vRP.getMoney(nuser_id)
    if vRP.tryPayment(nuser_id, nmoney) then
        vRP.giveMoney(user_id, nmoney)
    end
    Player.notify(source, 'sucesso', 'Saque realizado com sucesso.')
    Player.sendWebhook(Player.getWebhook('saquear'), '[ID]: ' .. user_id .. ' saqueou ' .. nuser_id)
end)

RegisterCommand('call', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local tipo = tostring(args[1] or '')
    if tipo == '' then return end

    local descricao = vRP.prompt(source, 'Descricao:', '')
    if descricao == '' then return end

    local mapa = {
        policia = 'policia.permissao',
        paramedico = 'paramedico.permissao',
        mecanico = 'mecanico.permissao',
        taxista = 'taxista.permissao',
        advogado = 'advogado.permissao',
        juiz = 'juiz.permissao',
        conce = 'conce.permissao',
        news = 'news.permissao',
        speed = 'speed.permissao',
        suporte = 'suporte.permissao'
    }

    local perm = mapa[tipo]
    if not perm then return end
    local players = vRP.getUsersByPermission(perm)
    local x, y, z = vRPclient.getPosition(source)
    local identity = vRP.getUserIdentity(user_id) or {}

    for _, id in pairs(players) do
        local player = vRP.getUserSource(parseInt(id))
        if player and player ~= source then
            async(function()
                local ok = vRP.request(player, 'Aceitar o chamado de ' .. (identity.name or '') .. ' ' .. (identity.firstname or '') .. '?', 30)
                if ok then
                    TriggerClientEvent('Notify', source, 'sucesso', 'Chamado aceito por um profissional.')
                    vRPclient._playSound(player, 'CONFIRM_BEEP', 'HUD_MINI_GAME_SOUNDSET')
                    local blip = vRPclient.addBlip(player, x, y, z, 1, 5, 'Chamado', 0.6, false)
                    SetTimeout(60000, function()
                        vRPclient.removeBlip(player, blip)
                    end)
                else
                    Player.notify(source, 'aviso', 'Chamado recusado por um profissional.')
                end
            end)
        end
    end
end)

RegisterCommand('mec', function(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    if not vRP.hasPermission(user_id, 'mecanico.permissao') then return end
    TriggerClientEvent('Notify', source, 'importante', 'Use /call mecanico para atender chamados.')
end)

RegisterCommand('mr', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local permission = 'mecanico.permissao'
    if not vRP.hasPermission(user_id, permission) then return end
    local mec = vRP.getUsersByPermission(permission)
    local identity = vRP.getUserIdentity(user_id) or {}
    for _, id in pairs(mec) do
        local player = vRP.getUserSource(parseInt(id))
        if player then
            TriggerClientEvent('chatMessage', player, 'MECANICO', { 0, 153, 204 }, identity.name .. ' ' .. identity.firstname .. ': ' .. table.concat(args or {}, ' '))
        end
    end
end)

RegisterCommand('card', function(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local identity = vRP.getUserIdentity(user_id)
    if not identity then return end
    local cd = math.random(1, 13)
    local naipe = math.random(1, 4)
    TriggerClientEvent('CartasMe', -1, source, identity.name, cd, naipe)
end)

local function sendClothingEvent(source, event, args)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    if not canInteract(source, user_id) then return end
    TriggerClientEvent(event, source, args[1], args[2])
end

RegisterCommand('mascara', function(source, args) sendClothingEvent(source, 'setmascara', args) end)
RegisterCommand('blusa', function(source, args) sendClothingEvent(source, 'setblusa', args) end)
RegisterCommand('colete', function(source, args) sendClothingEvent(source, 'setcolete', args) end)
RegisterCommand('jaqueta', function(source, args) sendClothingEvent(source, 'setjaqueta', args) end)
RegisterCommand('maos', function(source, args) sendClothingEvent(source, 'setmaos', args) end)
RegisterCommand('calca', function(source, args) sendClothingEvent(source, 'setcalca', args) end)
RegisterCommand('acessorios', function(source, args) sendClothingEvent(source, 'setacessorios', args) end)
RegisterCommand('sapatos', function(source, args) sendClothingEvent(source, 'setsapatos', args) end)
RegisterCommand('chapeu', function(source, args) sendClothingEvent(source, 'setchapeu', args) end)
RegisterCommand('oculos', function(source, args) sendClothingEvent(source, 'setoculos', args) end)

RegisterCommand('roupas', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id or not canInteract(source, user_id) then return end
    local tipo = args[1]
    if tipo then
        local custom = roupas[tostring(tipo)]
        if custom then
            local old_custom = vRPclient.getCustomization(source)
            local idle_copy = vRP.save_idle_custom(source, old_custom)
            idle_copy.modelhash = nil
            if custom[old_custom.modelhash] then
                for k, v in pairs(custom[old_custom.modelhash]) do
                    idle_copy[k] = v
                end
            end
            vRPclient._playAnim(source, true, { { 'clothingshirt', 'try_shirt_positive_d' } }, false)
            Wait(2500)
            vRPclient._stopAnim(source, true)
            vRPclient._setCustomization(source, idle_copy)
        end
    else
        vRPclient._playAnim(source, true, { { 'clothingshirt', 'try_shirt_positive_d' } }, false)
        Wait(2500)
        vRPclient._stopAnim(source, true)
        vRP.removeCloak(source)
    end
end)

RegisterCommand('roupas2', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id or not canInteract(source, user_id) then return end
    if not (vRP.hasPermission(user_id, 'admin.permissao') or vRP.hasPermission(user_id, 'paramedico.permissao')) then return end
    local nplayer = vRPclient.getNearestPlayer(source, 2)
    if not nplayer then return end
    local tipo = args[1]
    if tipo then
        local custom = roupas[tostring(tipo)]
        if custom then
            local old_custom = vRPclient.getCustomization(nplayer)
            local idle_copy = vRP.save_idle_custom(nplayer, old_custom)
            idle_copy.modelhash = nil
            if custom[old_custom.modelhash] then
                for k, v in pairs(custom[old_custom.modelhash]) do
                    idle_copy[k] = v
                end
            end
            vRPclient._setCustomization(nplayer, idle_copy)
        end
    else
        vRP.removeCloak(nplayer)
    end
end)

RegisterCommand('paypal', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local action = args[1]
    if action == 'sacar' and parseInt(args[2]) > 0 then
        local consulta = vRP.getUData(user_id, 'vRP:paypal')
        local saldo = json.decode(consulta) or 0
        local valor = parseInt(args[2])
        if saldo >= valor then
            vRP.giveBankMoney(user_id, valor)
            vRP.setUData(user_id, 'vRP:paypal', json.encode(saldo - valor))
            Player.notify(source, 'sucesso', 'Efetuou o saque de $' .. vRP.format(valor) .. ' da sua conta paypal.')
        else
            Player.notify(source, 'negado', 'Dinheiro insuficiente em sua conta paypal.')
        end
    elseif action == 'trans' and parseInt(args[2]) > 0 and parseInt(args[3]) > 0 then
        local target_id = parseInt(args[2])
        local valor = parseInt(args[3])
        local consulta = vRP.getUData(target_id, 'vRP:paypal')
        local saldo = json.decode(consulta) or 0
        local banco = vRP.getBankMoney(user_id)
        if banco >= valor then
            vRP.setBankMoney(user_id, banco - valor)
            vRP.setUData(target_id, 'vRP:paypal', json.encode(saldo + valor))
            Player.notify(source, 'sucesso', 'Enviou $' .. vRP.format(valor) .. ' ao passaporte ' .. vRP.format(target_id) .. '.')
            Player.sendWebhook(Player.getWebhook('paypal'), '[ID]: ' .. user_id .. ' ENVIOU $' .. vRP.format(valor) .. ' PARA ' .. target_id)
            local player = vRP.getUserSource(target_id)
            if player then
                Player.notify(player, 'importante', 'Voce recebeu $' .. vRP.format(valor) .. ' na conta paypal.')
            end
        else
            Player.notify(source, 'negado', 'Dinheiro insuficiente.')
        end
    end
end)

RegisterCommand('cobrar', function(source, args)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local consulta = vRPclient.getNearestPlayer(source, 2)
    local nuser_id = vRP.getUserId(consulta)
    if not nuser_id then return end
    local valor = parseInt(args[1])
    if valor <= 0 then return end
    local banco = vRP.getBankMoney(nuser_id)
    local identity = vRP.getUserIdentity(user_id) or {}
    local identityu = vRP.getUserIdentity(nuser_id) or {}
    if vRP.request(consulta, 'Deseja pagar $' .. vRP.format(valor) .. ' reais para ' .. (identity.name or '') .. ' ' .. (identity.firstname or '') .. '?', 30) then
        if banco >= valor then
            vRP.setBankMoney(nuser_id, banco - valor)
            vRP.giveBankMoney(user_id, valor)
            vRPclient._playAnim(source, true, { { 'mp_common', 'givetake1_a' } }, false)
            Player.notify(source, 'sucesso', 'Recebeu $' .. vRP.format(valor) .. ' de ' .. (identityu.name or '') .. ' ' .. (identityu.firstname or '') .. '.')
            Player.notify(consulta, 'importante', 'Pagamento realizado com sucesso.')
        else
            Player.notify(source, 'negado', 'Dinheiro insuficiente.')
        end
    end
end)

RegisterCommand('limpar', function(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    if not vRP.hasPermission(user_id, 'admin.permissao') then return end
    local list = listInventory(user_id)
    for _, v in ipairs(list) do
        vRP.tryGetInventoryItem(user_id, v.item, v.amount)
    end
    Player.notify(source, 'importante', 'Seu inventario foi limpo.')
end)

return VOID

