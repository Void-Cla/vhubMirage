local VOID = VOID or {}
local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')
vRP = Proxy.getInterface('vRP')

local vRPTrunk = {}
Tunnel.bindInterface('vrp_trunkchest', vRPTrunk)
Proxy.addInterface('vrp_trunkchest', vRPTrunk)

local function montarInventarioLegacy(lista)
    local out = {}
    for _, item in ipairs(lista or {}) do
        out[#out + 1] = {
            amount = item.amount or 0,
            name = item.name or item.key or '',
            index = item.index or item.icon or item.key or '',
            key = item.key or '',
            peso = item.peso or 0
        }
    end
    return out
end

function vRPTrunk.chestOpen()
    local source = source
    if VOID.interface and VOID.interface.abrirBauVeiculo then
        local ok = VOID.interface.abrirBauVeiculo()
        if ok then
            TriggerClientEvent('trunkchest:Open', source)
        end
        return ok == true
    end
    return false
end

function vRPTrunk.chestClose()
    if VOID.interface and VOID.interface.fecharBau then
        VOID.interface.fecharBau()
        return true
    end
    return false
end

function vRPTrunk.Mochila()
    if not VOID.interface or not VOID.interface.requestBau then return nil end
    local dados = VOID.interface.requestBau()
    if not dados then return nil end

    return montarInventarioLegacy(dados.inventarioBau), montarInventarioLegacy(dados.inventario), dados.pesoMochila, dados.maxPesoMochila, dados.pesoBau, dados.maxPesoBau
end

function vRPTrunk.storeItem(itemName, amount)
    if VOID.interface and VOID.interface.storeItem then
        return VOID.interface.storeItem(itemName, amount or 1)
    end
    return false
end

function vRPTrunk.takeItem(itemName, amount)
    if VOID.interface and VOID.interface.takeItem then
        return VOID.interface.takeItem(itemName, amount or 1)
    end
    return false
end

return VOID
