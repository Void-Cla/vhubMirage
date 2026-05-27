local VOID = VOID or {}
local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')
vRP = Proxy.getInterface('vRP')

local vRPIdentidade = {}
Tunnel.bindInterface('vrp_identidade', vRPIdentidade)
Proxy.addInterface('vrp_identidade', vRPIdentidade)

local function formatarValor(valor)
    local numero = tonumber(valor) or 0
    if vRP.format then
        local ok, result = pcall(vRP.format, numero)
        if ok and result then
            return result
        end
    end
    return tostring(numero)
end

local function obterDados(user_id)
    if VOID and VOID.obterIdentidade then
        return VOID.obterIdentidade(user_id)
    end
    return nil
end

function vRPIdentidade.Identidade()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end

    local dados = obterDados(user_id)
    if not dados then return nil end

    return dados.foto or '',
        dados.name or '',
        dados.firstname or '',
        dados.user_id or user_id,
        dados.registration or '',
        dados.age or 0,
        dados.phone or '',
        formatarValor(dados.cash or 0),
        dados.vip or '',
        formatarValor(dados.bank or 0),
        formatarValor(dados.multas or 0),
        formatarValor(dados.paypal or 0),
        dados.job or '',
        dados.corp or ''
end

function vRPIdentidade.getUserGroupByType(user_id, gtype)
    if VOID and VOID.interface and VOID.interface.getUserGroupByType then
        return VOID.interface.getUserGroupByType(user_id, gtype)
    end
    return ''
end

return VOID
