local VOID = VOID or {}
local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')
vRP = Proxy.getInterface('vRP')

local vRPMochila = {}
Tunnel.bindInterface('void_mochila', vRPMochila)
Proxy.addInterface('void_mochila', vRPMochila)

local function formatarValor(valor)
    local numero = tonumber(valor) or 0
    if vRP.format then
        local ok, resultado = pcall(vRP.format, numero)
        if ok and resultado then
            return resultado
        end
    end
    return tostring(numero)
end

local function montarInventarioLegacy(lista)
    local out = {}
    for _, item in ipairs(lista or {}) do
        out[#out + 1] = {
            amount = item.amount or 0,
            name = item.name or item.key or '',
            index = item.index or item.icon or item.key or '',
            key = item.key or item.name or '',
            type = item.type or 'usar',
            peso = item.peso or 0
        }
    end
    return out
end

function vRPMochila.fotoPerfil()
    if VOID.interface and VOID.interface.fotoPerfil then
        return VOID.interface.fotoPerfil()
    end
    return nil, false
end

function vRPMochila.Identidade()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end

    local dados = VOID.obterIdentidade and VOID.obterIdentidade(user_id) or nil
    if not dados then return nil end

    return tonumber(dados.cash or 0),
        formatarValor(dados.bank or 0),
        formatarValor(dados.coin or 0),
        dados.name or '',
        dados.firstname or '',
        dados.age or 0,
        dados.user_id or user_id,
        dados.registration or '',
        dados.phone or '',
        dados.job or '',
        dados.vip or '',
        tonumber(dados.vipDays or 0),
        tonumber(dados.multas or 0)
end

function vRPMochila.Mochila()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end

    local inventario, peso, max = VOID.listarMochila(user_id)
    return montarInventarioLegacy(inventario), peso or 0, max or 0
end

function vRPMochila.sendItem(itemName, amount)
    if VOID.interface and VOID.interface.sendItem then
        return VOID.interface.sendItem(itemName, amount or 1) == true
    end
    return false
end

function vRPMochila.dropItem(itemName, amount)
    if VOID.interface and VOID.interface.dropItem then
        return VOID.interface.dropItem(itemName, amount or 1) == true
    end
    return false
end

function vRPMochila.useItem(itemName, tipo, amount)
    if VOID.interface and VOID.interface.useItem then
        return VOID.interface.useItem(itemName, tipo or 'usar', amount or 1) == true
    end
    return false
end

function vRPMochila.storeItem(itemName, amount)
    if VOID.interface and VOID.interface.storeItem then
        return VOID.interface.storeItem(itemName, amount or 1) == true
    end
    return false
end

function vRPMochila.takeItem(itemName, amount)
    if VOID.interface and VOID.interface.takeItem then
        return VOID.interface.takeItem(itemName, amount or 1) == true
    end
    return false
end

function vRPMochila.portaMalas()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return {}, 0, 0, nil end

    local bau = VOID.bausAbertos and VOID.bausAbertos[user_id]
    local tipoVeiculo = VOID.const and VOID.const.TIPO_ARMAZENAMENTO and VOID.const.TIPO_ARMAZENAMENTO.BAU_VEICULO
    if bau and tipoVeiculo and bau.tipo == tipoVeiculo then
        local inventarioBau, pesoBau = VOID.listarContainer(bau.tipo, bau.container_id)
        return montarInventarioLegacy(inventarioBau), pesoBau or 0, bau.peso_max or 0, bau.nome
    end

    return {}, 0, 0, nil
end

return VOID
