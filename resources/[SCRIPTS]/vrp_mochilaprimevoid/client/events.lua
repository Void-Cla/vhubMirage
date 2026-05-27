local function atualizarUI()
    if not VOIDC.state.aberto then return end

    if VOIDC.state.contexto == 'mochila' then
        local inventario, peso, maxpeso = vSERVER.requestMochila()
        SendNUIMessage({
            action = 'updateMochila',
            mochila = inventario,
            peso = peso,
            maxpeso = maxpeso
        })
    elseif VOIDC.state.contexto == 'bau' then
        local dados = vSERVER.requestBau()
        SendNUIMessage({
            action = 'updateBau',
            dados = dados
        })
    elseif VOIDC.state.contexto == 'market' then
        local dados = vSERVER.marketGetData()
        SendNUIMessage({
            action = 'updateMarket',
            dados = dados
        })
    elseif VOIDC.state.contexto == 'loja' then
        local lojas = vSERVER.lojasProximas()
        SendNUIMessage({
            action = 'updateLoja',
            dados = { lojas = lojas or {} }
        })
    end
end

RegisterNetEvent('Inventory:Update')
AddEventHandler('Inventory:Update', function()
    atualizarUI()
end)

RegisterNetEvent('Creative:UpdateChest')
AddEventHandler('Creative:UpdateChest', function()
    atualizarUI()
end)

RegisterNetEvent('Creative:UpdateTrunk')
AddEventHandler('Creative:UpdateTrunk', function()
    atualizarUI()
end)

RegisterNetEvent('trunkchest:Open')
AddEventHandler('trunkchest:Open', function()
    if VOIDC.state.aberto then return end
    VOIDC.abrirBau()
end)

RegisterNetEvent('void_mochila_prime:openMarket')
AddEventHandler('void_mochila_prime:openMarket', function()
    VOIDC.abrirMarket()
end)

RegisterNetEvent('void_mochila_prime:Close')
AddEventHandler('void_mochila_prime:Close', function()
    VOIDC.fechar()
end)

return VOIDC
