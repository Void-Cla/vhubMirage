local VOID = VOID or {}
local Utils = VOID.utils
local Config = VOID.cfg

local function enviarWebhook(webhook, mensagem)
    if webhook and webhook ~= '' then
        PerformHttpRequest(webhook, function() end, 'POST', json.encode({ content = mensagem }), { ['Content-Type'] = 'application/json' })
    end
end

local function normalizarNomeBau(nome)
    if VOID and VOID.normalizarNomeBau then
        return VOID.normalizarNomeBau(nome)
    end
    if not nome then return nil end
    local str = tostring(nome)
    str = str:gsub('^%s+', ''):gsub('%s+$', '')
    return string.lower(str)
end

local function obterWebhookBau(chestName)
    if not (Config and Config.baus_faccao) then return nil end
    local hooks = Config.baus_faccao.webhooks or {}
    local normal = normalizarNomeBau(chestName)
    return hooks[chestName] or (normal and hooks[normal]) or Config.baus_faccao.webhook_auditoria
end

local function obterWebhookBauVeiculo()
    if not (Config and Config.bau_veiculo) then return nil end
    return Config.bau_veiculo.webhook_auditoria
end

local function formatarNomeItem(itemName)
    if not itemName then return 'item' end
    if vRP.itemNameList then
        local ok, nomeItem = pcall(vRP.itemNameList, itemName)
        if ok and nomeItem and nomeItem ~= '' then
            return nomeItem
        end
    end
    return tostring(itemName)
end

function VOID.logDebug(mensagem)
    if Config and Config.modo_debug then
        print('[void_mochila_prime] ' .. tostring(mensagem))
    end
end

function VOID.obterIpUsuario(userId)
    local src = vRP.getUserSource(userId)
    if not src then return nil end
    return GetPlayerEndpoint(src)
end

function VOID.registrarAuditoria(transactionId, userId, acao, detalhes)
    local ip = VOID.obterIpUsuario(userId)
    local payload = {
        transaction_id = transactionId,
        user_id = userId,
        acao = acao,
        detalhes = Utils.jsonEncode(detalhes or {}),
        ip_origem = ip
    }

    vRP.execute('inventario/registrar_auditoria', payload)
end

function VOID.registrarWebhookMarketplace(texto)
    if not Config or not Config.marketplace then return end
    enviarWebhook(Config.marketplace.webhook_vendas, texto)
end

function VOID.registrarWebhookLoja(texto)
    if not Config or not Config.lojas then return end
    enviarWebhook(Config.lojas.webhook_vendas_loja, texto)
end

function VOID.registrarWebhookBau(chestName, acao, userId, itemName, quantidade)
    if not (Config and Config.baus_faccao) then return end
    if Config.baus_faccao.registrar_todas_acoes == false then return end

    local webhook = obterWebhookBau(chestName)
    if not webhook or webhook == '' then return end

    local identity = vRP.getUserIdentity(userId) or {}
    local nome = (identity.name or 'N/A') .. ' ' .. (identity.firstname or '')

    local qtd = Utils.safeNumber(quantidade, 0)
    local msg = string.format('[BAU:%s] %s [%s] %s %sx %s | %s',
        tostring(chestName or 'n/a'),
        nome,
        tostring(userId),
        tostring(acao or 'acao'),
        qtd,
        formatarNomeItem(itemName),
        os.date('%d/%m/%Y %H:%M:%S')
    )

    enviarWebhook(webhook, msg)
end

function VOID.registrarWebhookBauVeiculo(veiculo, userId, acao, itemName, quantidade, containerId)
    if not (Config and Config.bau_veiculo) then return end
    if Config.bau_veiculo.registrar_todas_acoes == false then return end

    local webhook = obterWebhookBauVeiculo()
    if not webhook or webhook == '' then return end

    local identity = vRP.getUserIdentity(userId) or {}
    local nome = (identity.name or 'N/A') .. ' ' .. (identity.firstname or '')

    local qtd = Utils.safeNumber(quantidade, 0)
    local idTexto = containerId and (' | ' .. tostring(containerId)) or ''
    local msg = string.format('[PORTA-MALAS:%s%s] %s [%s] %s %sx %s | %s',
        tostring(veiculo or 'n/a'),
        idTexto,
        nome,
        tostring(userId),
        tostring(acao or 'acao'),
        qtd,
        formatarNomeItem(itemName),
        os.date('%d/%m/%Y %H:%M:%S')
    )

    enviarWebhook(webhook, msg)
end

function VOID.obterRelatorioUsuario(userId, limite)
    return vRP.query('inventario/obter_auditoria_usuario', {
        user_id = userId,
        limite = limite or 50
    })
end

function VOID.obterRelatorioRecente(limite)
    return vRP.query('inventario/obter_auditoria_recente', {
        limite = limite or 50
    })
end

return VOID
