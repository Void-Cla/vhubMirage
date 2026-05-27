local Config = VOIDC.cfg

local function podeAbrir()
    local ped = PlayerPedId()
    if GetEntityHealth(ped) < 102 then return false end
    if IsPedBeingStunned(ped) then return false end
    if IsPlayerFreeAiming(PlayerId()) then return false end
    local ok, handcuff = pcall(function() return vRP.isHandcuff() end)
    if ok and handcuff then return false end
    return true
end

local function jogadorProximo(raio)
    if not raio or raio <= 0 then return false end
    local ok, player = pcall(function()
        return vRP.getNearestPlayer(raio)
    end)
    if not ok then return false end
    if player and player ~= 0 then
        return true
    end
    return false
end

local function notificarNegado(msg)
    TriggerEvent('Notify', 'negado', msg or '')
end

local function tentarAbrirBauFaccao(chest)
    if not chest or not chest.nome then return false end
    local limite = (Config.baus_faccao and Config.baus_faccao.limite_proximidade) or 3
    if jogadorProximo(limite) then
        notificarNegado('Voce esta muito proximo de alguem! Afaste-se para abrir o bau.')
        return false
    end
    local ok = vSERVER.abrirBauFaccao(chest.nome)
    if ok then
        VOIDC.abrirBau()
        return true
    end
    return false
end

function VOIDC.tentarAbrirMochila()
    if VOIDC.state.aberto then return end
    if not podeAbrir() then return end
    VOIDC.abrirMochila()
end

function VOIDC.toggleMochila()
    if VOIDC.state.aberto then
        VOIDC.fechar()
        vSERVER.fecharBau()
        return
    end
    VOIDC.tentarAbrirMochila()
end

local function drawText3d(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

RegisterCommand((Config.baus_faccao and Config.baus_faccao.comando) or 'chest', function()
    if VOIDC.state.aberto then return end
    if not podeAbrir() then return end
    if not (Config.baus_faccao and Config.baus_faccao.locais) then return end

    local ped = PlayerPedId()
    local x, y, z = table.unpack(GetEntityCoords(ped))
    local distInteracao = Config.baus_faccao.distancia_interacao or 1.5
    local alvo = nil
    local menor = distInteracao

    for _, chest in ipairs(Config.baus_faccao.locais) do
        local dist = #(vector3(x, y, z) - vector3(chest.x, chest.y, chest.z))
        if dist <= distInteracao and (not alvo or dist < menor) then
            alvo = chest
            menor = dist
        end
    end

    if alvo then
        tentarAbrirBauFaccao(alvo)
    end
end, false)

CreateThread(function()
    while true do
        local time = 500
        if not VOIDC.state.aberto then
            if IsControlJustPressed(0, Config.mochila.tecla_abertura) and podeAbrir() then
                VOIDC.tentarAbrirMochila()
            end

            if IsControlJustPressed(0, Config.bau_veiculo.tecla_abertura) and podeAbrir() then
                local limite = (Config.bau_veiculo and Config.bau_veiculo.limite_proximidade) or 3
                if jogadorProximo(limite) then
                    notificarNegado('Voce esta muito proximo de alguem! Afaste-se para abrir o bau.')
                else
                    local ok = vSERVER.abrirBauVeiculo()
                    if ok then
                        VOIDC.abrirBau()
                    end
                end
            end
        end

        Wait(time)
    end
end)

CreateThread(function()
    while true do
        local time = 500
        if not VOIDC.state.aberto and Config.baus_faccao and Config.baus_faccao.locais then
            local ped = PlayerPedId()
            local x, y, z = table.unpack(GetEntityCoords(ped))
            local distMarker = Config.baus_faccao.distancia_marker or 5.0
            local distInteracao = Config.baus_faccao.distancia_interacao or 1.5
            local markerCfg = Config.baus_faccao.marker or {}
            local markerTipo = markerCfg.tipo or 23
            local escala = markerCfg.escala or {}
            local cor = markerCfg.cor or {}
            local offsetZ = Config.baus_faccao.marker_offset_z or -0.98
            local textoOffset = Config.baus_faccao.texto_offset_z or 0.3
            for _, chest in ipairs(Config.baus_faccao.locais) do
                local dist = #(vector3(x, y, z) - vector3(chest.x, chest.y, chest.z))
                if dist <= distMarker then
                    time = 4
                    DrawMarker(
                        markerTipo,
                        chest.x, chest.y, chest.z + offsetZ,
                        0, 0, 0, 0, 0, 0,
                        escala.x or 1.1, escala.y or 1.1, escala.z or 0.5,
                        cor.r or 120, cor.g or 80, cor.b or 255, cor.a or 100,
                        0, 0, 0, 0
                    )
                    if dist <= distInteracao then
                        drawText3d(chest.x, chest.y, chest.z + textoOffset, 'E - Abrir bau')
                        local tecla = (Config.baus_faccao and Config.baus_faccao.tecla_interacao) or (Config.lojas and Config.lojas.tecla_interacao) or 38
                        if IsControlJustPressed(0, tecla) and podeAbrir() then
                            if tentarAbrirBauFaccao(chest) then
                                break
                            end
                        end
                    end
                end
            end
        end
        Wait(time)
    end
end)

CreateThread(function()
    while true do
        local time = 500
        if not VOIDC.state.aberto and Config.lojas then
            if IsControlJustPressed(0, Config.lojas.tecla_interacao) and podeAbrir() then
                local lojas = vSERVER.lojasProximas()
                if lojas and #lojas > 0 then
                    VOIDC.abrirLoja(lojas)
                end
            end
        end
        Wait(time)
    end
end)

CreateThread(function()
    while true do
        local time = 500
        if VOIDC.state.aberto then
            time = 1
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 263, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 200, true)
        end
        Wait(time)
    end
end)

return VOIDC
