local VOID = VOID or {}
local Config = VOID.cfg
local Const = VOID.const

VOID.bausAbertos = VOID.bausAbertos or {}

local vRPPrime = VOID.interface

local function atualizarUI(src)
    TriggerClientEvent('Inventory:Update', src)
end

local function notificar(src, tipo, msg)
    TriggerClientEvent('Notify', src, tipo or 'aviso', msg or '', (Config.notificacoes and Config.notificacoes.tempo_exibicao) or 5000)
end

VOID.notificar = notificar

local function validarCooldownBau(user_id, tipo)
    if VOID.validarCooldownBau then
        return VOID.validarCooldownBau(user_id, tipo)
    end
    return true
end

local function aplicarAntiflood(source, acao)
    if vRP.antiflood then
        pcall(vRP.antiflood, source, acao, 3)
    end
end

function vRPPrime.requestMochila()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end
    return VOID.listarMochila(user_id)
end

function vRPPrime.useItem(itemName, tipo, quantidade)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    if VOID.player and VOID.player.canUseItem then
        local okUso, erroUso = VOID.player.canUseItem(user_id, itemName, quantidade or 1, source)
        if not okUso then
            notificar(source, 'negado', erroUso or 'Nao foi possivel usar o item.')
            return false
        end
    end

    local ok, erro = VOID.removerItemSeguro(user_id, itemName, quantidade or 1, Const.TIPO_ARMAZENAMENTO.MOCHILA)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel usar o item: ' .. tostring(erro))
        return false
    end

    TriggerEvent('void_mochila_prime:itemUsed', user_id, itemName, tipo or 'usar', quantidade or 1)
    TriggerClientEvent('void_mochila_prime:itemUsed', source, itemName, tipo or 'usar', quantidade or 1)
    atualizarUI(source)
    return true
end

function vRPPrime.dropItem(itemName, quantidade)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    local x, y, z = vRPclient.getPosition(source)
    local ok, erro = VOID.droparItemSeguro(user_id, itemName, quantidade or 1, { x = x, y = y, z = z })
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel dropar: ' .. tostring(erro))
        return false
    end

    atualizarUI(source)
    return true
end

function vRPPrime.sendItem(itemName, quantidade)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    local nplayer = vRPclient.getNearestPlayer(source, 2)
    if not nplayer or nplayer == 0 then
        notificar(source, 'negado', 'Nenhum jogador proximo.')
        return false
    end

    local nuser_id = vRP.getUserId(nplayer)
    if not nuser_id then
        notificar(source, 'negado', 'Jogador invalido.')
        return false
    end

    local ok, erro = VOID.transferirItemParaJogador(user_id, nuser_id, itemName, quantidade or 1)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel enviar: ' .. tostring(erro))
        return false
    end

    notificar(source, 'sucesso', 'Item enviado com sucesso.')
    notificar(nplayer, 'sucesso', 'Voce recebeu um item.')
    atualizarUI(source)
    atualizarUI(nplayer)
    return true
end

function vRPPrime.requestBau()
    local source = source
    local user_id = vRP.getUserId(source)
    local bau = VOID.bausAbertos[user_id]
    if not bau then return nil end

    local inventario, pesoMochila, maxPesoMochila = VOID.listarMochila(user_id)
    local inventarioBau, pesoBau = VOID.listarContainer(bau.tipo, bau.container_id)

    return {
        inventario = inventario,
        pesoMochila = pesoMochila,
        maxPesoMochila = maxPesoMochila,
        inventarioBau = inventarioBau,
        pesoBau = pesoBau,
        maxPesoBau = bau.peso_max or 0,
        bauNome = bau.nome or bau.nome_normalizado or '',
        bauTipo = bau.tipo
    }
end

function vRPPrime.storeItem(itemName, quantidade)
    local source = source
    local user_id = vRP.getUserId(source)
    local bau = VOID.bausAbertos[user_id]
    if not bau then
        notificar(source, 'negado', 'Nenhum bau aberto.')
        return false
    end

    aplicarAntiflood(source, 'storeItem')

    local okCooldown, restante = validarCooldownBau(user_id, bau.tipo)
    if not okCooldown then
        notificar(source, 'aviso', 'Aguarde ' .. tostring(restante) .. 's para repetir.')
        return false
    end

    local ok, erro = VOID.moverItemMochilaParaContainer(user_id, itemName, quantidade or 1, bau.tipo, bau.container_id, bau.peso_max)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel guardar: ' .. tostring(erro))
        return false
    end

    if bau.tipo == Const.TIPO_ARMAZENAMENTO.BAU_FACCAO then
        if VOID.registrarWebhookBau then
            VOID.registrarWebhookBau(bau.nome or bau.nome_normalizado or '', 'guardou', user_id, itemName, quantidade or 1)
        end
        TriggerClientEvent('Creative:UpdateChest', source, 'updateChest')
    elseif bau.tipo == Const.TIPO_ARMAZENAMENTO.BAU_VEICULO then
        if VOID.registrarWebhookBauVeiculo then
            VOID.registrarWebhookBauVeiculo(bau.nome, user_id, 'guardou', itemName, quantidade or 1, bau.container_id)
        end
        TriggerClientEvent('Creative:UpdateTrunk', source, 'updateMochila')
    end

    TriggerClientEvent('Inventory:Update', source, 'updateMochila')
    return true
end

function vRPPrime.takeItem(itemName, quantidade)
    local source = source
    local user_id = vRP.getUserId(source)
    local bau = VOID.bausAbertos[user_id]
    if not bau then
        notificar(source, 'negado', 'Nenhum bau aberto.')
        return false
    end

    aplicarAntiflood(source, 'takeItem')

    local okCooldown, restante = validarCooldownBau(user_id, bau.tipo)
    if not okCooldown then
        notificar(source, 'aviso', 'Aguarde ' .. tostring(restante) .. 's para repetir.')
        return false
    end

    local ok, erro = VOID.moverItemContainerParaMochila(user_id, itemName, quantidade or 1, bau.tipo, bau.container_id)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel retirar: ' .. tostring(erro))
        return false
    end

    if bau.tipo == Const.TIPO_ARMAZENAMENTO.BAU_FACCAO then
        if VOID.registrarWebhookBau then
            VOID.registrarWebhookBau(bau.nome or bau.nome_normalizado or '', 'retirou', user_id, itemName, quantidade or 1)
        end
        TriggerClientEvent('Creative:UpdateChest', source, 'updateChest')
    elseif bau.tipo == Const.TIPO_ARMAZENAMENTO.BAU_VEICULO then
        if VOID.registrarWebhookBauVeiculo then
            VOID.registrarWebhookBauVeiculo(bau.nome, user_id, 'retirou', itemName, quantidade or 1, bau.container_id)
        end
        TriggerClientEvent('Creative:UpdateTrunk', source, 'updateMochila')
    end

    TriggerClientEvent('Inventory:Update', source, 'updateMochila')
    return true
end

function vRPPrime.marketGetData()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end
    return VOID.obterMarketplaceData(user_id)
end

function vRPPrime.marketListItem(itemName, quantidade, preco, descricao)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    local ok, erro = VOID.criarAnuncioMarketplace(user_id, itemName, quantidade, preco, descricao)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel anunciar: ' .. tostring(erro))
        return false
    end

    notificar(source, 'sucesso', 'Item anunciado.')
    atualizarUI(source)
    return true
end

function vRPPrime.marketBuyItem(marketplaceId)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    local ok, erro = VOID.comprarItemSeguro(user_id, marketplaceId)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel comprar: ' .. tostring(erro))
        return false
    end

    notificar(source, 'sucesso', 'Compra realizada!')
    atualizarUI(source)
    return true
end

function vRPPrime.marketCancelItem(marketplaceId)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    local ok, erro = VOID.cancelarAnuncio(user_id, marketplaceId)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel cancelar: ' .. tostring(erro))
        return false
    end

    notificar(source, 'sucesso', 'Anuncio cancelado.')
    atualizarUI(source)
    return true
end

function vRPPrime.lojasProximas()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end

    local x, y, z = vRPclient.getPosition(source)
    local raio = (Config.lojas and Config.lojas.raio_atuacao_padrao) or 3
    local lojas = vRP.query('lojas/obter_lojas_proximas', { x = x, y = y, raio = raio })
    return lojas
end

function vRPPrime.lojaDados(lojaId)
    local resolver = VOID.resolverLojaId or function(id)
        local rows = vRP.query('lojas/obter_loja', { loja_id = id })
        return id, rows[1]
    end
    local lojaResolvida, loja = resolver(lojaId)
    if not loja then return nil end

    local itens = vRP.query('lojas/obter_itens_loja', { loja_id = lojaResolvida })
    return { loja = loja, itens = itens }
end

function vRPPrime.comprarLoja(lojaId, itemName, quantidade)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    local ok, erro = VOID.comprarDaLoja(user_id, lojaId, itemName, quantidade)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel comprar: ' .. tostring(erro))
        return false
    end

    notificar(source, 'sucesso', 'Compra realizada!')
    atualizarUI(source)
    return true
end

function vRPPrime.venderLoja(lojaId, itemName, quantidade)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    local ok, erro = VOID.venderParaLoja(user_id, lojaId, itemName, quantidade)
    if not ok then
        notificar(source, 'negado', 'Nao foi possivel vender: ' .. tostring(erro))
        return false
    end

    notificar(source, 'sucesso', 'Venda realizada!')
    atualizarUI(source)
    return true
end

return VOID
