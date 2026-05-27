local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')
local Tools = module('vrp', 'lib/Tools')
local groupsCfg = module('vrp', 'cfg/groups')

vRP = Proxy.getInterface('vRP')
vRPclient = Tunnel.getInterface('vRP')

local Config = module(GetCurrentResourceName(), 'config')
local Itens = module(GetCurrentResourceName(), 'shared/items')
local Const = module(GetCurrentResourceName(), 'shared/constants')
local Utils = module(GetCurrentResourceName(), 'shared/utils')

math.randomseed(os.time())

VOID = VOID or {}
VOID.cfg = Config
VOID.itens = Itens
VOID.const = Const
VOID.utils = Utils
VOID.groups = groupsCfg and groupsCfg.groups or {}

local vRPPrime = {}
Tunnel.bindInterface('void_mochila_prime', vRPPrime)
Proxy.addInterface('void_mochila_prime', vRPPrime)
VOID.interface = vRPPrime

vRP.prepare('inventario/foto_perfil', 'SELECT foto FROM vrp_user_identities WHERE user_id = @user_id')
vRP.prepare('inventario/coluna_foto_existe', "SHOW COLUMNS FROM vrp_user_identities LIKE 'foto'")

local fotoColunaExiste = nil
local function temColunaFoto()
    if fotoColunaExiste ~= nil then
        return fotoColunaExiste
    end
    local rows = vRP.query('inventario/coluna_foto_existe', {})
    fotoColunaExiste = rows and rows[1] ~= nil
    return fotoColunaExiste
end

function vRPPrime.fotoPerfil()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil, false end

    if temColunaFoto() then
        local rows = vRP.query('inventario/foto_perfil', { user_id = user_id })
        if rows and rows[1] and rows[1].foto and rows[1].foto ~= '' then
            return rows[1].foto, true
        end
    end

    return 'https://i.pinimg.com/736x/5c/95/31/5c9531d05f919414e9dff0c974388f67.jpg', false
end

function vRPPrime.getUserGroupByType(user_id, gtype)
    local user_groups = vRP.getUserGroups(user_id)
    for groupName, _ in pairs(user_groups or {}) do
        local group = VOID.groups[groupName]
        if group and group._config and group._config.gtype == gtype then
            return group._config.title or groupName
        end
    end
    return ''
end

local function obterIdentidade(user_id)
    if not user_id then return nil end

    local identity = vRP.getUserIdentity(user_id) or {}
    local cash = vRP.getMoney(user_id) or 0
    local bank = vRP.getBankMoney(user_id) or 0
    local coin = vRP.getCoin and vRP.getCoin(user_id) or (vRP.getCoins and vRP.getCoins(user_id) or 0)
    local multas = vRP.getUData and vRP.getUData(user_id, 'vRP:multas') or 0
    local multasValor = Utils.jsonDecode(multas) or 0
    local job = vRPPrime.getUserGroupByType(user_id, 'job')
    local corp = vRPPrime.getUserGroupByType(user_id, 'corp')
    local cargo = vRPPrime.getUserGroupByType(user_id, 'cargo')
    local vip = vRPPrime.getUserGroupByType(user_id, 'vip')
    local vipDays = vRP.getVipDaysRemaining and vRP.getVipDaysRemaining(user_id) or 0
    local paypal = vRP.getUData and vRP.getUData(user_id, 'vRP:paypal') or 0
    local paypalValor = Utils.jsonDecode(paypal) or 0
    if cargo ~= '' then
        job = cargo
    end

    return {
        user_id = user_id,
        foto = temColunaFoto() and identity.foto or nil,
        name = identity.name or 'N/A',
        firstname = identity.firstname or '',
        age = identity.age or 0,
        registration = identity.registration or '',
        phone = identity.phone or '',
        cash = cash,
        bank = bank,
        coin = coin,
        job = job,
        corp = corp,
        cargo = cargo,
        vip = vip,
        vipDays = vipDays,
        multas = multasValor,
        paypal = paypalValor
    }
end

VOID.obterIdentidade = obterIdentidade

function vRPPrime.Identidade()
    local source = source
    local user_id = vRP.getUserId(source)
    return obterIdentidade(user_id)
end

function vRPPrime.Mochila()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return nil end
    return VOID.listarMochila(user_id)
end

local function bootstrapLojas()
    if not Config or not Config.lojas or not Config.lojas.lojas_padrao then return end

    for _, loja in ipairs(Config.lojas.lojas_padrao) do
        local existente = vRP.query('lojas/obter_loja', { loja_id = loja.loja_id })
        if not existente[1] then
            vRP.execute('lojas/criar_loja', {
                loja_id = loja.loja_id,
                nome = loja.nome,
                descricao = loja.descricao or '',
                proprietario = loja.proprietario or 'SERVER',
                localizacao_x = loja.x,
                localizacao_y = loja.y,
                localizacao_z = loja.z,
                tipo_loja = loja.tipo_loja or 'general',
                raio_atuacao = Config.lojas.raio_atuacao_padrao or 3
            })
        end

        for _, item in ipairs(loja.itens or {}) do
            local existenteItem = vRP.query('lojas/obter_item_loja', {
                loja_id = loja.loja_id,
                item_name = item.item
            })
            if existenteItem and existenteItem[1] then
                vRP.execute('lojas/atualizar_item_loja', {
                    loja_id = loja.loja_id,
                    item_name = item.item,
                    preco_compra = item.preco,
                    preco_venda = item.preco_venda or 0,
                    estoque_maximo = item.estoque or 999
                })
            else
                vRP.execute('lojas/adicionar_item_loja', {
                    loja_id = loja.loja_id,
                    item_name = item.item,
                    preco_compra = item.preco,
                    preco_venda = item.preco_venda or 0,
                    estoque_maximo = item.estoque or 999,
                    estoque_atual = item.estoque or 0
                })
            end
            vRP.execute('lojas/atualizar_estoque', {
                loja_id = loja.loja_id,
                item_name = item.item,
                estoque_novo = item.estoque or 0
            })
        end
    end
end

CreateThread(function()
    Wait(1000)
    bootstrapLojas()
end)

return VOID

