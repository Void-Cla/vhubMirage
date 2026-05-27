local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')

vRP = Proxy.getInterface('vRP')

local Config = module(GetCurrentResourceName(), 'config')
local Const = module(GetCurrentResourceName(), 'shared/constants')

cRP = {}
Tunnel.bindInterface('void_mochila_prime', cRP)

vSERVER = Tunnel.getInterface('void_mochila_prime')

VOIDC = {
    cfg = Config,
    const = Const,
    state = {
        aberto = false,
        contexto = 'mochila',
        binds = {}
    }
}

local function usarBind(slot)
    local info = VOIDC.state.binds[tostring(slot)]
    if info and info.item then
        vSERVER.useItem(info.item, info.type or 'usar', 1)
    end
end

RegisterCommand('voidbind1', function() usarBind(1) end, false)
RegisterCommand('voidbind2', function() usarBind(2) end, false)
RegisterCommand('voidbind3', function() usarBind(3) end, false)
RegisterCommand('voidbind4', function() usarBind(4) end, false)
RegisterCommand('voidbind5', function() usarBind(5) end, false)

if Config.mochila and Config.mochila.binds_numpad then
    RegisterKeyMapping('voidbind1', 'Usar bind 1', 'keyboard', 'numpad1')
    RegisterKeyMapping('voidbind2', 'Usar bind 2', 'keyboard', 'numpad2')
    RegisterKeyMapping('voidbind3', 'Usar bind 3', 'keyboard', 'numpad3')
    RegisterKeyMapping('voidbind4', 'Usar bind 4', 'keyboard', 'numpad4')
    RegisterKeyMapping('voidbind5', 'Usar bind 5', 'keyboard', 'numpad5')
end

RegisterCommand('voidmochila', function()
    if VOIDC and VOIDC.toggleMochila then
        VOIDC.toggleMochila()
    elseif VOIDC then
        VOIDC.abrirMochila()
    end
end, false)

RegisterKeyMapping('voidmochila', 'Abrir Mochila Prime', 'keyboard', 'i')

return VOIDC
