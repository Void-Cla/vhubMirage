local VOID = VOID or {}
local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')
vRP = Proxy.getInterface('vRP')

local vRPChest = {}
Tunnel.bindInterface('vrp_chest', vRPChest)

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

local function garantirBauAberto(user_id, chestName)
    local bau = VOID.bausAbertos and VOID.bausAbertos[user_id] or nil
    if bau and bau.nome_normalizado and VOID.normalizarNomeBau then
        local normal = VOID.normalizarNomeBau(chestName)
        if normal and normal == bau.nome_normalizado then
            return true
        end
    elseif bau and bau.nome == chestName then
        return true
    end

    if VOID.interface and VOID.interface.abrirBauFaccao then
        return VOID.interface.abrirBauFaccao(chestName)
    end

    return false
end

function vRPChest.checkIntPermissions(chestName)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end
    if VOID and VOID.podeUsarBauFaccao then
        return VOID.podeUsarBauFaccao(user_id, source, chestName) == true
    end
    return true
end

function vRPChest.openChest(chestName)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end

    if VOID and VOID.podeUsarBauFaccao then
        if VOID.podeUsarBauFaccao(user_id, source, chestName) ~= true then
            return nil
        end
    end

    if not garantirBauAberto(user_id, chestName) then
        return nil
    end

    if not VOID.interface or not VOID.interface.requestBau then return nil end
    local dados = VOID.interface.requestBau()
    if not dados then return nil end

    return montarInventarioLegacy(dados.inventarioBau), montarInventarioLegacy(dados.inventario), dados.pesoMochila, dados.maxPesoMochila, dados.pesoBau, dados.maxPesoBau
end

function vRPChest.storeItem(chestName, itemName, amount)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    if not garantirBauAberto(user_id, chestName) then
        return false
    end

    if VOID.interface and VOID.interface.storeItem then
        return VOID.interface.storeItem(itemName, amount or 1)
    end

    return false
end

function vRPChest.takeItem(chestName, itemName, amount)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    if not garantirBauAberto(user_id, chestName) then
        return false
    end

    if VOID.interface and VOID.interface.takeItem then
        return VOID.interface.takeItem(itemName, amount or 1)
    end

    return false
end

return VOID
