local VOID = VOID or {}
local Player = VOID.player or {}

if not Player.isEnabled or not Player.isEnabled() then
    return VOID
end

local cfg = Player.cfg or {}
local bandagem = {}

CreateThread(function()
    while true do
        Wait(1000)
        for user_id, tempo in pairs(bandagem) do
            if tempo > 0 then
                bandagem[user_id] = tempo - 1
            end
        end
    end
end)

function Player.canUseItem(user_id, item, quantidade, source)
    if item == 'bandagem' then
        local vida = vRPclient.getHealth(source)
        if vida <= 101 or vida >= 400 then
            return false, 'Voce nao pode utilizar de vida cheia ou nocauteado.'
        end
        local tempo = bandagem[user_id] or 0
        if tempo > 0 then
            return false, 'Voce precisa aguardar ' .. tempo .. ' segundos para utilizar outra bandagem.'
        end
    elseif item == 'capuz' then
        local nplayer = vRPclient.getNearestPlayer(source, 2)
        if not nplayer or nplayer == 0 then
            return false, 'Nenhum jogador proximo.'
        end
    end
    return true
end

local function consumirAnimacao(source, item)
    TriggerClientEvent('void_mochila_prime:consumirItem', source, item)
end

local function handleLockpick(source, user_id, tipo)
    local pickCfg = (tipo == 'masterpick' and cfg.masterpick) or cfg.lockpick or {}
    local minPolice = pickCfg.policia_minima or 0
    local tempo = pickCfg.tempo_ms or 30000
    local chance = pickCfg.chance_sucesso or 20

    local mPlaca, mName, mNet = vRPclient.ModelName(source, 7)
    if not mName or not mNet then
        Player.notify(source, 'negado', 'Nenhum veiculo proximo.')
        vRP.giveInventoryItem(user_id, tipo, 1)
        return
    end

    local policia = vRP.getUsersByPermission('policia.permissao')
    if #policia < minPolice then
        Player.notify(source, 'aviso', 'Numero insuficiente de policiais no momento para iniciar o roubo.')
        vRP.giveInventoryItem(user_id, tipo, 1)
        return
    end

    if vRP.hasPermission(user_id, 'policia.permissao') then
        TriggerClientEvent('syncLock', -1, mNet)
        return
    end

    TriggerClientEvent('cancelando', source, true)
    vRPclient._playAnim(source, false, { { 'amb@prop_human_parking_meter@female@idle_a', 'idle_a_female' } }, true)
    TriggerClientEvent('progress', source, tempo, 'roubando')

    SetTimeout(tempo, function()
        TriggerClientEvent('cancelando', source, false)
        vRPclient._stopAnim(source, false)

        local owner_id = vRP.getUserByRegistration(mPlaca)
        local sucesso = owner_id == nil or math.random(100) <= chance
        if sucesso then
            TriggerClientEvent('syncLock', -1, mNet)
            TriggerClientEvent('vrp_sound:source', source, 'lock', 0.1)
            Player.notify(source, 'sucesso', 'Veiculo destrancado.')
            return
        end

        Player.notify(source, 'negado', 'Roubo do veiculo falhou e as autoridades foram acionadas.')
        for _, id in pairs(policia) do
            local player = vRP.getUserSource(parseInt(id))
            if player then
                local x, y, z = vRPclient.getPosition(source)
                local texto = 'Roubo de veiculo em andamento.'
                TriggerClientEvent('Notify', player, 'aviso', texto)
                local blipId = vRPclient.addBlip(player, x, y, z, 10, 5, 'Ocorrencia', 0.5, false)
                SetTimeout(20000, function()
                    vRPclient.removeBlip(player, blipId)
                end)
            end
        end
    end)
end

AddEventHandler('void_mochila_prime:itemUsed', function(user_id, item, tipo, quantidade)
    local source = vRP.getUserSource(user_id)
    if not source then
        return
    end

    if item == 'bandagem' then
        bandagem[user_id] = 60
        TriggerClientEvent('bandagem', source)
        Player.notify(source, 'sucesso', 'Bandagem utilizada com sucesso.')
        return
    end

    if item == 'mochila' then
        if vRP.varyExp then
            vRP.varyExp(user_id, 'physical', 'strength', 650)
        end
        Player.notify(source, 'sucesso', 'Mochila utilizada com sucesso.')
        return
    end

    if item == 'capuz' then
        local nplayer = vRPclient.getNearestPlayer(source, 2)
        if nplayer and not vRPclient.isHandcuffed(source) then
            vRPclient.setCapuz(nplayer)
            vRP.closeMenu(nplayer)
            Player.notify(source, 'sucesso', 'Capuz utilizado com sucesso.')
        else
            Player.notify(source, 'negado', 'Nenhum jogador proximo.')
        end
        vRP.giveInventoryItem(user_id, item, quantidade or 1)
        return
    end

    if item == 'energetico' then
        consumirAnimacao(source, item)
        local mult = (cfg.energetico and cfg.energetico.multiplicador) or 1.15
        TriggerClientEvent('void_mochila_prime:energetico', source, true, mult)
        local dur = (cfg.energetico and cfg.energetico.duracao_ms) or 60000
        SetTimeout(dur, function()
            TriggerClientEvent('void_mochila_prime:energetico', source, false, 1.0)
            Player.notify(source, 'aviso', 'O efeito do energetico passou e o coracao voltou ao normal.')
        end)
        return
    end

    if item == 'lockpick' or item == 'masterpick' then
        handleLockpick(source, user_id, item)
        return
    end

    local bebidas = {
        cerveja = true,
        tequila = true,
        vodka = true,
        whisky = true,
        conhaque = true,
        absinto = true
    }

    local drogas = {
        maconha = true,
        metanfetamina = true,
        cocaina = true
    }

    if bebidas[item] or drogas[item] then
        consumirAnimacao(source, item)
        Player.notify(source, 'sucesso', Player.getItemLabel(item) .. ' utilizada com sucesso.')
        return
    end
end)

return VOID
