local Config = VOIDC.cfg

local function setFocus(status)
    SetNuiFocus(status, status)
    SetCursorLocation(0.5, 0.5)
    TriggerEvent('hudOff', status)
    if status then
        TransitionToBlurred(500)
    else
        TransitionFromBlurred(500)
    end
end

function VOIDC.abrirMochila()
    if VOIDC.state.aberto then return end
    local identidade = vSERVER.Identidade()
    local foto, ok = vSERVER.fotoPerfil()
    local inventario, peso, maxpeso = vSERVER.requestMochila()

    VOIDC.state.aberto = true
    VOIDC.state.contexto = 'mochila'

    setFocus(true)
    SendNUIMessage({
        action = 'open',
        contexto = 'mochila',
        mochila = inventario,
        peso = peso,
        maxpeso = maxpeso,
        identidade = identidade,
        foto = foto,
        foto_ok = ok,
        binds = VOIDC.state.binds
    })
end

function VOIDC.abrirBau()
    if VOIDC.state.aberto then return end
    local dados = vSERVER.requestBau()
    if not dados then return end

    VOIDC.state.aberto = true
    VOIDC.state.contexto = 'bau'

    setFocus(true)
    SendNUIMessage({
        action = 'open',
        contexto = 'bau',
        dados = dados,
        binds = VOIDC.state.binds
    })
end

function VOIDC.abrirMarket()
    if VOIDC.state.aberto then return end
    local dados = vSERVER.marketGetData()
    if not dados then return end

    VOIDC.state.aberto = true
    VOIDC.state.contexto = 'market'

    setFocus(true)
    SendNUIMessage({
        action = 'open',
        contexto = 'market',
        dados = dados,
        binds = VOIDC.state.binds
    })
end

function VOIDC.abrirLoja(lojas)
    if VOIDC.state.aberto then return end

    VOIDC.state.aberto = true
    VOIDC.state.contexto = 'loja'

    setFocus(true)
    SendNUIMessage({
        action = 'open',
        contexto = 'loja',
        dados = { lojas = lojas or {} },
        binds = VOIDC.state.binds
    })
end

function VOIDC.fechar()
    if not VOIDC.state.aberto then return end
    VOIDC.state.aberto = false
    VOIDC.state.contexto = 'mochila'
    setFocus(false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('invClose', function(_, cb)
    VOIDC.fechar()
    if cb then cb('ok') end
    vSERVER.fecharBau()
end)

RegisterNUICallback('requestMochila', function(_, cb)
    local inventario, peso, maxpeso = vSERVER.requestMochila()
    cb({ inventario = inventario, peso = peso, maxpeso = maxpeso })
end)

RegisterNUICallback('requestBau', function(_, cb)
    local dados = vSERVER.requestBau()
    cb(dados or {})
end)

RegisterNUICallback('useItem', function(data, cb)
    vSERVER.useItem(data.item, data.type or 'usar', data.amount or 1)
    if cb then cb('ok') end
end)

RegisterNUICallback('dropItem', function(data, cb)
    vSERVER.dropItem(data.item, data.amount or 1)
    if cb then cb('ok') end
end)

RegisterNUICallback('sendItem', function(data, cb)
    vSERVER.sendItem(data.item, data.amount or 1)
    if cb then cb('ok') end
end)

RegisterNUICallback('storeItem', function(data, cb)
    vSERVER.storeItem(data.item, data.amount or 1)
    if cb then cb('ok') end
end)

RegisterNUICallback('takeItem', function(data, cb)
    vSERVER.takeItem(data.item, data.amount or 1)
    if cb then cb('ok') end
end)

RegisterNUICallback('marketGetData', function(_, cb)
    local dados = vSERVER.marketGetData()
    cb(dados or {})
end)

RegisterNUICallback('marketListItem', function(data, cb)
    vSERVER.marketListItem(data.item, data.amount or 1, data.price or 0, data.description or '')
    if cb then cb('ok') end
end)

RegisterNUICallback('marketBuyItem', function(data, cb)
    vSERVER.marketBuyItem(data.marketplace_id)
    if cb then cb('ok') end
end)

RegisterNUICallback('marketCancelItem', function(data, cb)
    vSERVER.marketCancelItem(data.marketplace_id)
    if cb then cb('ok') end
end)

RegisterNUICallback('lojasProximas', function(_, cb)
    local lojas = vSERVER.lojasProximas()
    cb({ lojas = lojas or {} })
end)

RegisterNUICallback('lojaDados', function(data, cb)
    local dados = vSERVER.lojaDados(data.loja_id)
    cb(dados or {})
end)

RegisterNUICallback('comprarLoja', function(data, cb)
    vSERVER.comprarLoja(data.loja_id, data.item, data.amount or 1)
    if cb then cb('ok') end
end)

RegisterNUICallback('venderLoja', function(data, cb)
    vSERVER.venderLoja(data.loja_id, data.item, data.amount or 1)
    if cb then cb('ok') end
end)

RegisterNUICallback('saveBind', function(data, cb)
    local slot = tostring(data.slot)
    if slot and data.item then
        VOIDC.state.binds[slot] = { item = data.item, type = data.type or 'usar' }
    end
    if cb then cb('ok') end
end)

return VOIDC