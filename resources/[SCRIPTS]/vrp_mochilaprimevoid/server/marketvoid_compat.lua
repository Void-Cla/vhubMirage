local VOID = VOID or {}
local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')
vRP = Proxy.getInterface('vRP')
local Config = VOID.cfg or {}
local Itens = VOID.itens or {}

local vRPMarket = {}
Tunnel.bindInterface('vrp_marketvoid', vRPMarket)
Proxy.addInterface('vrp_marketvoid', vRPMarket)

local function normalizarIcone(icon)
    if not icon or icon == '' then return nil end
    local valor = tostring(icon)
    if valor:find('^https?://') or valor:find('^nui://') then
        return valor
    end
    if valor:find('%.png$') or valor:find('%.jpg$') or valor:find('%.jpeg$') or valor:find('%.webp$') then
        return 'images/' .. valor
    end
    return 'images/' .. valor .. '.png'
end

local function podeListarItem(nomeItem)
    if not nomeItem or nomeItem == '' then return false end
    local info = Itens[nomeItem]
    if info and (info.bloqueado_mercado or info.permitido_marketplace == false) then
        return false
    end
    for _, bloqueado in ipairs(Config.itens_bloqueados_marketplace or {}) do
        if bloqueado == nomeItem then
            return false
        end
    end
    return true
end

local function mapItemAnuncio(item)
    local nomeItem = item.item_name or item.item or item.name or ''
    local icone = normalizarIcone(item.icon or item.index or nomeItem)
    return {
        id = item.marketplace_id or item.id,
        item = nomeItem,
        label = item.label or nomeItem,
        amount = item.quantidade or item.amount or 0,
        price = item.preco or item.price or 0,
        description = item.descricao or item.description or '',
        seller_name = item.seller_name or '',
        seller_id = item.seller_id or 0,
        icon = icone
    }
end

local function mapItemInventario(item)
    local nomeItem = item.key or item.name or item.item or item.item_name or ''
    if not podeListarItem(nomeItem) then
        return nil
    end
    return {
        name = nomeItem,
        label = item.label or item.name or nomeItem,
        amount = item.amount or item.quantidade or 0,
        icon = normalizarIcone(item.icon or item.index or nomeItem)
    }
end

function vRPMarket.getMarketData()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end

    if not (VOID.interface and VOID.interface.marketGetData) then
        return { items = {}, recent = {}, myItems = {}, me = user_id }
    end

    local dados = VOID.interface.marketGetData()
    if not dados then
        return { items = {}, recent = {}, myItems = {}, me = user_id }
    end

    local itens = {}
    for _, item in ipairs(dados.items or {}) do
        itens[#itens + 1] = mapItemAnuncio(item)
    end

    local recentes = {}
    for _, item in ipairs(dados.recent or {}) do
        recentes[#recentes + 1] = mapItemAnuncio(item)
    end

    local meusItens = {}
    for _, item in ipairs(dados.myItems or {}) do
        local mapped = mapItemInventario(item)
        if mapped then
            meusItens[#meusItens + 1] = mapped
        end
    end

    return {
        items = itens,
        recent = recentes,
        myItems = meusItens,
        me = dados.me or user_id
    }
end

function vRPMarket.listItem(item, amount, price, description)
    if VOID.interface and VOID.interface.marketListItem then
        return VOID.interface.marketListItem(item, amount, price, description) == true
    end
    return false
end

function vRPMarket.buyItem(itemId)
    if VOID.interface and VOID.interface.marketBuyItem then
        return VOID.interface.marketBuyItem(itemId) == true
    end
    return false
end

return VOID




