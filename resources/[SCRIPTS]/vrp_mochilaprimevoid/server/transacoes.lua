local VOID = VOID or {}
local Config = VOID.cfg
local Itens = VOID.itens
local Utils = VOID.utils
local Const = VOID.const

local function obterInfoItem(nomeItem)
    return Itens and Itens[nomeItem] or nil
end

local function itemExiste(nomeItem)
    if obterInfoItem(nomeItem) then
        return true
    end
    if vRP.itemNameList then
        local ok, nome = pcall(vRP.itemNameList, nomeItem)
        if ok and nome and nome ~= '' then
            return true
        end
    end
    if vRP.getItemWeight then
        local ok, peso = pcall(vRP.getItemWeight, nomeItem)
        if ok and peso then
            return true
        end
    end
    return false
end

local function resolverLojaId(lojaId)
    if not lojaId then
        return nil, nil
    end

    local loja = vRP.query('lojas/obter_loja', { loja_id = lojaId })
    loja = loja[1]
    if loja then
        return lojaId, loja
    end

    local numericId = tonumber(lojaId)
    if numericId then
        local lojaAlt = vRP.query('lojas/obter_loja_por_id', { id = numericId })
        lojaAlt = lojaAlt[1]
        if lojaAlt then
            return lojaAlt.loja_id, lojaAlt
        end
    end

    return nil, nil
end

VOID.resolverLojaId = resolverLojaId

local function obterPesoItem(nomeItem)
    if vRP.getItemWeight then
        local ok, peso = pcall(vRP.getItemWeight, nomeItem)
        if ok and peso then return peso end
    end
    local info = obterInfoItem(nomeItem)
    return info and info.peso or 0
end

local function obterNomeItem(nomeItem)
    if vRP.itemNameList then
        local ok, nome = pcall(vRP.itemNameList, nomeItem)
        if ok and nome then return nome end
    end
    local info = obterInfoItem(nomeItem)
    return info and info.nome or nomeItem
end

local function obterIndexItem(nomeItem)
    if vRP.itemIndexList then
        local ok, idx = pcall(vRP.itemIndexList, nomeItem)
        if ok and idx then return idx end
    end
    local info = obterInfoItem(nomeItem)
    return info and info.icon or nomeItem
end

local function obterTipoItem(nomeItem)
    if vRP.itemTypeList then
        local ok, tipo = pcall(vRP.itemTypeList, nomeItem)
        if ok and tipo then return tipo end
    end
    local info = obterInfoItem(nomeItem)
    return info and info.tipo or 'generico'
end

local function obterPesoMaximo(userId)
    if vRP.getInventoryMaxWeight then
        local ok, max = pcall(vRP.getInventoryMaxWeight, userId)
        if ok and max then return max end
    end
    return (Config and Config.mochila and Config.mochila.peso_maximo_padrao) or 50
end

local function montarItemUI(nomeItem, quantidade)
    local info = obterInfoItem(nomeItem) or {}
    return {
        key = nomeItem,
        amount = quantidade,
        name = obterNomeItem(nomeItem),
        index = obterIndexItem(nomeItem),
        type = obterTipoItem(nomeItem),
        peso = obterPesoItem(nomeItem),
        categoria = info.categoria or 'NORMAL',
        icon = info.icon or nomeItem,
        bloqueado_drop = info.bloqueado_drop or false,
        bloqueado_mercado = info.bloqueado_mercado or false,
        permitido_bau = info.permitido_bau ~= false,
        permitido_marketplace = info.permitido_marketplace ~= false,
        especial = info.especial or false,
    }
end

function VOID.listarMochila(userId)
    local rows = vRP.query('inventario/obter_itens_mochila_agregado', { user_id = userId })
    local itens = {}
    local pesoAtual = 0
    for _, row in ipairs(rows or {}) do
        local qtd = Utils.safeNumber(row.quantidade, 0)
        local pesoItem = obterPesoItem(row.item_name)
        pesoAtual = pesoAtual + (pesoItem * qtd)
        itens[#itens + 1] = montarItemUI(row.item_name, qtd)
    end
    return itens, pesoAtual, obterPesoMaximo(userId)
end

function VOID.listarContainer(tipoArmazenamento, containerId)
    local rows = vRP.query('inventario/obter_itens_container_agregado', {
        tipo_armazenamento = tipoArmazenamento,
        container_id = containerId
    })
    local itens = {}
    local pesoAtual = 0
    for _, row in ipairs(rows or {}) do
        local qtd = Utils.safeNumber(row.quantidade, 0)
        local pesoItem = obterPesoItem(row.item_name)
        pesoAtual = pesoAtual + (pesoItem * qtd)
        itens[#itens + 1] = montarItemUI(row.item_name, qtd)
    end
    return itens, pesoAtual
end

function VOID.criarTransacao(userId, tipoOperacao, dados)
    local transactionId = Utils.gerarUUID()
    vRP.execute('inventario/criar_transacao', {
        transaction_id = transactionId,
        user_id = userId,
        tipo_operacao = tipoOperacao,
        item_name = dados.item_name or 'n/a',
        quantidade = Utils.safeNumber(dados.quantidade, 0),
        serialkeys_envolvidas = Utils.jsonEncode(dados.serialkeys or {}),
        dados_transacao = Utils.jsonEncode(dados),
        status = 'pendente'
    })
    return transactionId
end

function VOID.registrarFalhaTransacao(transactionId, erro)
    vRP.execute('inventario/falha_transacao', {
        transaction_id = transactionId,
        erro_descricao = erro or 'erro_desconhecido'
    })
end

function VOID.criarItensDB(userId, nomeItem, quantidade, tipoArmazenamento, containerId)
    local serialkeys = {}
    for i = 1, quantidade do
        local serialkey = Utils.gerarSerialKey(userId, nomeItem)
        local checksum = Utils.calcularChecksum(userId, nomeItem, serialkey)
        local ok = vRP.execute('inventario/criar_item', {
            serialkey = serialkey,
            user_id = userId,
            item_name = nomeItem,
            quantidade = 1,
            tipo_armazenamento = tipoArmazenamento,
            container_id = containerId,
            checksum = checksum
        })
        if not ok or ok < 1 then
            return nil, 'erro_criar_item'
        end
        serialkeys[#serialkeys + 1] = serialkey
    end
    return serialkeys
end

function VOID.removerItensDB(serialkeys)
    for _, serialkey in ipairs(serialkeys) do
        local ok = vRP.execute('inventario/remover_item', {
            serialkey = serialkey,
            deleted_at = os.date('%Y-%m-%d %H:%M:%S')
        })
        if not ok or ok < 1 then
            return false
        end
    end
    return true
end

function VOID.transferirSerialkeysDB(serialkeys, novoUserId, tipoArmazenamento, containerId)
    for _, serialkey in ipairs(serialkeys) do
        local ok = vRP.execute('inventario/transferir_serialkey', {
            serialkey = serialkey,
            novo_user_id = novoUserId,
            tipo_armazenamento = tipoArmazenamento,
            container_id = containerId
        })
        if not ok or ok < 1 then
            return false
        end
    end
    return true
end

function VOID.adicionarItemSeguro(userId, nomeItem, quantidade, origem, tipoArmazenamento, containerId, opts)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    if quantidadeNum <= 0 then
        return false, 'quantidade_invalida'
    end

    if not itemExiste(nomeItem) then
        return false, 'item_invalido'
    end

    local tipo = tipoArmazenamento or Const.TIPO_ARMAZENAMENTO.MOCHILA
    local transacaoId = opts and opts.transaction_id or VOID.criarTransacao(userId, 'adicionar', {
        item_name = nomeItem,
        quantidade = quantidadeNum,
        origem = origem,
        tipo_armazenamento = tipo
    })

    if tipo == Const.TIPO_ARMAZENAMENTO.MOCHILA then
        local itensMochila, pesoAtual, pesoMax = VOID.listarMochila(userId)
        local pesoNovo = pesoAtual + (obterPesoItem(nomeItem) * quantidadeNum)
        if pesoNovo > pesoMax then
            VOID.registrarFalhaTransacao(transacaoId, 'peso_excedido')
            return false, 'peso_excedido'
        end
    end

    local usarTransacao = not (opts and opts.transacao_externa)
    if usarTransacao then
        vRP.execute('inventario/iniciar_transacao_db')
    end

    local serialkeys, erro = VOID.criarItensDB(userId, nomeItem, quantidadeNum, tipo, containerId)
    if not serialkeys then
        if usarTransacao then
            vRP.execute('inventario/rollback_transacao_db')
        end
        VOID.registrarFalhaTransacao(transacaoId, erro)
        return false, erro
    end

    if usarTransacao then
        vRP.execute('inventario/commit_transacao_db')
    end

    vRP.execute('inventario/conclusao_transacao', {
        transaction_id = transacaoId,
        status = 'completa',
        serialkeys_envolvidas = Utils.jsonEncode(serialkeys)
    })

    VOID.registrarAuditoria(transacaoId, userId,
        'Adicionado ' .. quantidadeNum .. 'x ' .. nomeItem,
        { serialkeys = serialkeys, origem = origem, tipo = tipo }
    )

    if tipo == Const.TIPO_ARMAZENAMENTO.MOCHILA and VOID.syncVrpGiveInventoryItem then
        VOID.syncVrpGiveInventoryItem(userId, nomeItem, quantidadeNum, true)
    end

    return true, serialkeys
end

function VOID.removerItemSeguro(userId, nomeItem, quantidade, tipoArmazenamento, opts)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    if quantidadeNum <= 0 then
        return false, 'quantidade_invalida'
    end

    local tipo = tipoArmazenamento or Const.TIPO_ARMAZENAMENTO.MOCHILA
    local transacaoId = opts and opts.transaction_id or VOID.criarTransacao(userId, 'remover', {
        item_name = nomeItem,
        quantidade = quantidadeNum,
        tipo_armazenamento = tipo
    })

    local itens = vRP.query('inventario/obter_itens_usuario', {
        user_id = userId,
        item_name = nomeItem,
        tipo_armazenamento = tipo,
        limite = quantidadeNum
    })

    if #itens < quantidadeNum then
        VOID.registrarFalhaTransacao(transacaoId, 'quantidade_insuficiente')
        return false, 'quantidade_insuficiente'
    end

    local serialkeys = {}
    for i = 1, quantidadeNum do
        serialkeys[#serialkeys + 1] = itens[i].serialkey
    end

    local usarTransacao = not (opts and opts.transacao_externa)
    if usarTransacao then
        vRP.execute('inventario/iniciar_transacao_db')
    end

    local ok = VOID.removerItensDB(serialkeys)
    if not ok then
        if usarTransacao then
            vRP.execute('inventario/rollback_transacao_db')
        end
        VOID.registrarFalhaTransacao(transacaoId, 'erro_remover_item')
        return false, 'erro_remover_item'
    end

    if usarTransacao then
        vRP.execute('inventario/commit_transacao_db')
    end

    vRP.execute('inventario/conclusao_transacao', {
        transaction_id = transacaoId,
        status = 'completa',
        serialkeys_envolvidas = Utils.jsonEncode(serialkeys)
    })

    VOID.registrarAuditoria(transacaoId, userId,
        'Removido ' .. quantidadeNum .. 'x ' .. nomeItem,
        { serialkeys = serialkeys, tipo = tipo }
    )

    if tipo == Const.TIPO_ARMAZENAMENTO.MOCHILA and VOID.syncVrpTryGetInventoryItem then
        VOID.syncVrpTryGetInventoryItem(userId, nomeItem, quantidadeNum, true)
    end

    return true, serialkeys
end

function VOID.moverItemMochilaParaContainer(userId, nomeItem, quantidade, tipoDestino, containerId, pesoMaxContainer)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    if quantidadeNum <= 0 then
        return false, 'quantidade_invalida'
    end

    local info = obterInfoItem(nomeItem)
    if info and info.permitido_bau == false then
        return false, 'item_bloqueado'
    end
    if Config and Config.itens_bloqueados_bau then
        for _, bloqueado in ipairs(Config.itens_bloqueados_bau) do
            if bloqueado == nomeItem then
                return false, 'item_bloqueado'
            end
        end
    end
    if tipoDestino == Const.TIPO_ARMAZENAMENTO.BAU_VEICULO and Config and Config.itens_bloqueados_bau_veiculo then
        for _, bloqueado in ipairs(Config.itens_bloqueados_bau_veiculo) do
            if bloqueado == nomeItem then
                return false, 'item_bloqueado'
            end
        end
    end

    local _, pesoAtual = VOID.listarContainer(tipoDestino, containerId)
    local pesoNovo = pesoAtual + (obterPesoItem(nomeItem) * quantidadeNum)
    if pesoMaxContainer and pesoNovo > pesoMaxContainer then
        return false, 'bau_cheio'
    end

    local itens = vRP.query('inventario/obter_itens_usuario', {
        user_id = userId,
        item_name = nomeItem,
        tipo_armazenamento = Const.TIPO_ARMAZENAMENTO.MOCHILA,
        limite = quantidadeNum
    })
    if #itens < quantidadeNum then
        return false, 'quantidade_insuficiente'
    end

    local serialkeys = {}
    for i = 1, quantidadeNum do
        serialkeys[#serialkeys + 1] = itens[i].serialkey
    end

    local transacaoId = VOID.criarTransacao(userId, 'transferir', {
        item_name = nomeItem,
        quantidade = quantidadeNum,
        origem = Const.TIPO_ARMAZENAMENTO.MOCHILA,
        destino = tipoDestino,
        container_id = containerId
    })

    vRP.execute('inventario/iniciar_transacao_db')
    local okTransfer = VOID.transferirSerialkeysDB(serialkeys, userId, tipoDestino, containerId)
    if not okTransfer then
        vRP.execute('inventario/rollback_transacao_db')
        VOID.registrarFalhaTransacao(transacaoId, 'erro_transferir')
        return false, 'erro_transferir'
    end
    vRP.execute('inventario/commit_transacao_db')

    if VOID.syncVrpTryGetInventoryItem then
        VOID.syncVrpTryGetInventoryItem(userId, nomeItem, quantidadeNum, true)
    end

    vRP.execute('inventario/conclusao_transacao', {
        transaction_id = transacaoId,
        status = 'completa',
        serialkeys_envolvidas = Utils.jsonEncode(serialkeys)
    })

    VOID.registrarAuditoria(transacaoId, userId,
        'Moveu ' .. quantidadeNum .. 'x ' .. nomeItem .. ' para ' .. tipoDestino,
        { serialkeys = serialkeys, container = containerId }
    )

    return true
end

function VOID.moverItemContainerParaMochila(userId, nomeItem, quantidade, tipoOrigem, containerId)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    if quantidadeNum <= 0 then
        return false, 'quantidade_invalida'
    end

    local _, pesoAtual, pesoMax = VOID.listarMochila(userId)
    local pesoNovo = pesoAtual + (obterPesoItem(nomeItem) * quantidadeNum)
    if pesoNovo > pesoMax then
        return false, 'peso_excedido'
    end

    local itens = vRP.query('inventario/obter_itens_container', {
        tipo_armazenamento = tipoOrigem,
        container_id = containerId
    })

    local serialkeys = {}
    for _, item in ipairs(itens or {}) do
        if item.item_name == nomeItem then
            serialkeys[#serialkeys + 1] = item.serialkey
            if #serialkeys >= quantidadeNum then
                break
            end
        end
    end

    if #serialkeys < quantidadeNum then
        return false, 'quantidade_insuficiente'
    end

    local transacaoId = VOID.criarTransacao(userId, 'transferir', {
        item_name = nomeItem,
        quantidade = quantidadeNum,
        origem = tipoOrigem,
        destino = Const.TIPO_ARMAZENAMENTO.MOCHILA,
        container_id = containerId
    })

    vRP.execute('inventario/iniciar_transacao_db')
    local ok = VOID.transferirSerialkeysDB(serialkeys, userId, Const.TIPO_ARMAZENAMENTO.MOCHILA, nil)
    if not ok then
        vRP.execute('inventario/rollback_transacao_db')
        VOID.registrarFalhaTransacao(transacaoId, 'erro_transferir')
        return false, 'erro_transferir'
    end
    vRP.execute('inventario/commit_transacao_db')

    if VOID.syncVrpGiveInventoryItem then
        VOID.syncVrpGiveInventoryItem(userId, nomeItem, quantidadeNum, true)
    end

    vRP.execute('inventario/conclusao_transacao', {
        transaction_id = transacaoId,
        status = 'completa',
        serialkeys_envolvidas = Utils.jsonEncode(serialkeys)
    })

    VOID.registrarAuditoria(transacaoId, userId,
        'Retirou ' .. quantidadeNum .. 'x ' .. nomeItem .. ' de ' .. tipoOrigem,
        { serialkeys = serialkeys, container = containerId }
    )

    return true
end

function VOID.droparItemSeguro(userId, nomeItem, quantidade, coords)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    if quantidadeNum <= 0 then
        return false, 'quantidade_invalida'
    end

    local info = obterInfoItem(nomeItem)
    if info and info.bloqueado_drop then
        return false, 'item_bloqueado'
    end
    if Config and Config.itens_bloqueados_drop then
        for _, bloqueado in ipairs(Config.itens_bloqueados_drop) do
            if bloqueado == nomeItem then
                return false, 'item_bloqueado'
            end
        end
    end

    local transacaoId = VOID.criarTransacao(userId, 'dropar', {
        item_name = nomeItem,
        quantidade = quantidadeNum
    })

    local itens = vRP.query('inventario/obter_itens_usuario', {
        user_id = userId,
        item_name = nomeItem,
        tipo_armazenamento = Const.TIPO_ARMAZENAMENTO.MOCHILA,
        limite = quantidadeNum
    })
    if #itens < quantidadeNum then
        VOID.registrarFalhaTransacao(transacaoId, 'quantidade_insuficiente')
        return false, 'quantidade_insuficiente'
    end

    local serialkeys = {}
    for i = 1, quantidadeNum do
        serialkeys[#serialkeys + 1] = itens[i].serialkey
    end

    vRP.execute('inventario/iniciar_transacao_db')
    local ok = VOID.removerItensDB(serialkeys)
    if not ok then
        vRP.execute('inventario/rollback_transacao_db')
        VOID.registrarFalhaTransacao(transacaoId, 'erro_remover_item')
        return false, 'erro_remover_item'
    end
    vRP.execute('inventario/commit_transacao_db')

    vRP.execute('inventario/conclusao_transacao', {
        transaction_id = transacaoId,
        status = 'completa',
        serialkeys_envolvidas = Utils.jsonEncode(serialkeys)
    })

    VOID.registrarAuditoria(transacaoId, userId,
        'Dropou ' .. quantidadeNum .. 'x ' .. nomeItem,
        { serialkeys = serialkeys }
    )

    if VOID.syncVrpTryGetInventoryItem then
        VOID.syncVrpTryGetInventoryItem(userId, nomeItem, quantidadeNum, true)
    end

    if GetResourceState('DropSystem') == 'started' then
        local ttl = (Config and Config.seguranca and Config.seguranca.drop_ttl) or Const.DROP_TTL_PADRAO
        TriggerEvent('DropSystem:create', nomeItem, quantidadeNum, coords.x, coords.y, coords.z, ttl)
    else
        VOID.logDebug('DropSystem nao encontrado. Drop ignorado para item ' .. nomeItem)
    end

    return true
end

function VOID.transferirItemParaJogador(origemId, destinoId, nomeItem, quantidade)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    if quantidadeNum <= 0 then
        return false, 'quantidade_invalida'
    end

    local itens = vRP.query('inventario/obter_itens_usuario', {
        user_id = origemId,
        item_name = nomeItem,
        tipo_armazenamento = Const.TIPO_ARMAZENAMENTO.MOCHILA,
        limite = quantidadeNum
    })
    if #itens < quantidadeNum then
        return false, 'quantidade_insuficiente'
    end

    local serialkeys = {}
    for i = 1, quantidadeNum do
        serialkeys[#serialkeys + 1] = itens[i].serialkey
    end

    vRP.execute('inventario/iniciar_transacao_db')
    local ok = VOID.transferirSerialkeysDB(serialkeys, destinoId, Const.TIPO_ARMAZENAMENTO.MOCHILA, nil)
    if not ok then
        vRP.execute('inventario/rollback_transacao_db')
        return false, 'erro_transferir'
    end
    vRP.execute('inventario/commit_transacao_db')

    if VOID.syncVrpTryGetInventoryItem then
        VOID.syncVrpTryGetInventoryItem(origemId, nomeItem, quantidadeNum, true)
    end
    if VOID.syncVrpGiveInventoryItem then
        VOID.syncVrpGiveInventoryItem(destinoId, nomeItem, quantidadeNum, true)
    end

    VOID.registrarAuditoria(Utils.gerarUUID(), origemId,
        'Enviou ' .. quantidadeNum .. 'x ' .. nomeItem .. ' para ' .. destinoId,
        { serialkeys = serialkeys }
    )

    return true
end

function VOID.criarAnuncioMarketplace(userId, nomeItem, quantidade, preco, descricao)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    local precoNum = Utils.safeNumber(preco, 0)
    if quantidadeNum <= 0 or precoNum <= 0 then
        return false, 'dados_invalidos'
    end

    if not itemExiste(nomeItem) then
        return false, 'item_invalido'
    end
    local info = obterInfoItem(nomeItem) or {}

    if Config and Config.marketplace then
        if quantidadeNum > Config.marketplace.quantidade_maxima then
            return false, 'quantidade_maxima'
        end
        if precoNum > Config.marketplace.preco_maximo then
            return false, 'preco_maximo'
        end
    end

    if info and (info.bloqueado_mercado or info.permitido_marketplace == false) then
        return false, 'item_bloqueado'
    end

    for _, bloqueado in ipairs(Config.itens_bloqueados_marketplace or {}) do
        if bloqueado == nomeItem then
            return false, 'item_bloqueado'
        end
    end

    local totalAnuncios = vRP.query('inventario/contar_anuncios_usuario', { seller_id = userId })
    if totalAnuncios[1] and Config.marketplace and totalAnuncios[1].total >= Config.marketplace.maximo_anuncios_por_jogador then
        return false, 'limite_anuncios'
    end

    local itens = vRP.query('inventario/obter_itens_usuario', {
        user_id = userId,
        item_name = nomeItem,
        tipo_armazenamento = Const.TIPO_ARMAZENAMENTO.MOCHILA,
        limite = quantidadeNum
    })
    if #itens < quantidadeNum then
        return false, 'quantidade_insuficiente'
    end

    local serialkeys = {}
    for i = 1, quantidadeNum do
        serialkeys[#serialkeys + 1] = itens[i].serialkey
    end

    local marketplaceId = Utils.gerarUUID()

    vRP.execute('inventario/iniciar_transacao_db')

    local ok = VOID.transferirSerialkeysDB(serialkeys, userId, Const.TIPO_ARMAZENAMENTO.MARKETPLACE, marketplaceId)
    if not ok then
        vRP.execute('inventario/rollback_transacao_db')
        return false, 'erro_transferir'
    end

    local identidade = vRP.getUserIdentity(userId)
    local sellerName = identidade and (identidade.name .. ' ' .. identidade.firstname) or ('ID ' .. userId)

    local okAnuncio = vRP.execute('inventario/criar_anuncio', {
        marketplace_id = marketplaceId,
        seller_id = userId,
        seller_name = sellerName,
        item_name = nomeItem,
        quantidade = quantidadeNum,
        preco = precoNum,
        descricao = Utils.safeString(descricao, ''):sub(1, Config.marketplace.caracteres_descricao_max or 160),
        serialkeys_anunciadas = Utils.jsonEncode(serialkeys)
    })
    if not okAnuncio or okAnuncio < 1 then
        vRP.execute('inventario/rollback_transacao_db')
        return false, 'erro_anuncio'
    end

    vRP.execute('inventario/commit_transacao_db')

    if VOID.syncVrpTryGetInventoryItem then
        VOID.syncVrpTryGetInventoryItem(userId, nomeItem, quantidadeNum, true)
    end

    VOID.registrarWebhookMarketplace('Novo anuncio: ' .. sellerName .. ' listou ' .. quantidadeNum .. 'x ' .. nomeItem .. ' por $' .. precoNum)

    VOID.registrarAuditoria(Utils.gerarUUID(), userId,
        'Criou anuncio marketplace',
        { marketplace_id = marketplaceId, item = nomeItem, quantidade = quantidadeNum, preco = precoNum }
    )

    return true
end

function VOID.cancelarAnuncio(userId, marketplaceId)
    local anuncio = vRP.query('inventario/obter_anuncio', { marketplace_id = marketplaceId })
    if not anuncio[1] then
        return false, 'anuncio_inexistente'
    end

    if anuncio[1].seller_id ~= userId or anuncio[1].status ~= 'ativo' then
        return false, 'anuncio_invalido'
    end

    local serialkeys = Utils.jsonDecode(anuncio[1].serialkeys_anunciadas) or {}

    vRP.execute('inventario/iniciar_transacao_db')
    local ok = vRP.execute('inventario/cancelar_anuncio', { marketplace_id = marketplaceId })
    if not ok or ok < 1 then
        vRP.execute('inventario/rollback_transacao_db')
        return false, 'erro_cancelar'
    end

    local okTransfer = VOID.transferirSerialkeysDB(serialkeys, userId, Const.TIPO_ARMAZENAMENTO.MOCHILA, nil)
    if not okTransfer then
        vRP.execute('inventario/rollback_transacao_db')
        return false, 'erro_transferir'
    end

    vRP.execute('inventario/commit_transacao_db')

    if VOID.syncVrpGiveInventoryItem then
        VOID.syncVrpGiveInventoryItem(userId, anuncio[1].item_name, anuncio[1].quantidade, true)
    end

    VOID.registrarAuditoria(Utils.gerarUUID(), userId,
        'Cancelou anuncio marketplace',
        { marketplace_id = marketplaceId, serialkeys = serialkeys }
    )

    return true
end

function VOID.comprarItemSeguro(userId, marketplaceId)
    local anuncio = vRP.query('inventario/obter_anuncio_lock', { marketplace_id = marketplaceId })
    anuncio = anuncio and anuncio[1] or nil

    if not anuncio or anuncio.status ~= 'ativo' then
        return false, 'anuncio_indisponivel'
    end

    if anuncio.seller_id == userId then
        return false, 'anuncio_proprio'
    end

    local info = obterInfoItem(anuncio.item_name)
    if info and (info.bloqueado_mercado or info.permitido_marketplace == false) then
        return false, 'item_bloqueado'
    end

    local transacaoId = VOID.criarTransacao(userId, 'comprar', {
        item_name = anuncio.item_name,
        quantidade = anuncio.quantidade,
        preco = anuncio.preco,
        vendedor = anuncio.seller_id,
        marketplace_id = marketplaceId
    })

    vRP.execute('inventario/iniciar_transacao_db')

    if not vRP.tryPayment(userId, anuncio.preco) then
        vRP.execute('inventario/rollback_transacao_db')
        VOID.registrarFalhaTransacao(transacaoId, 'saldo_insuficiente')
        return false, 'saldo_insuficiente'
    end

    local serialkeys = Utils.jsonDecode(anuncio.serialkeys_anunciadas) or {}
    local okTransfer = VOID.transferirSerialkeysDB(serialkeys, userId, Const.TIPO_ARMAZENAMENTO.MOCHILA, nil)
    if not okTransfer then
        vRP.execute('inventario/rollback_transacao_db')
        vRP.giveMoney(userId, anuncio.preco)
        VOID.registrarFalhaTransacao(transacaoId, 'erro_transferir')
        return false, 'erro_transferir'
    end

    local ok = vRP.execute('inventario/marcar_anuncio_vendido', {
        marketplace_id = marketplaceId,
        comprador_id = userId,
        data_venda = os.date('%Y-%m-%d %H:%M:%S')
    })

    if not ok or ok < 1 then
        vRP.execute('inventario/rollback_transacao_db')
        vRP.giveMoney(userId, anuncio.preco)
        VOID.registrarFalhaTransacao(transacaoId, 'erro_marcar_venda')
        return false, 'erro_marcar_venda'
    end

    vRP.execute('inventario/commit_transacao_db')

    vRP.execute('inventario/conclusao_transacao', {
        transaction_id = transacaoId,
        status = 'completa',
        serialkeys_envolvidas = Utils.jsonEncode(serialkeys)
    })

    if VOID.syncVrpGiveInventoryItem then
        VOID.syncVrpGiveInventoryItem(userId, anuncio.item_name, anuncio.quantidade, true)
    end

    if anuncio.seller_id then
        local comissaoPct = (Config.marketplace and Config.marketplace.comissao_percentual) or 0
        if comissaoPct < 0 then comissaoPct = 0 end
        if comissaoPct > 100 then comissaoPct = 100 end
        local comissao = math.floor(anuncio.preco * (comissaoPct / 100))
        local valorVendedor = anuncio.preco - comissao
        vRP.giveMoney(anuncio.seller_id, valorVendedor)
    end

    VOID.registrarWebhookMarketplace('Venda marketplace: item ' .. anuncio.item_name .. ' x' .. anuncio.quantidade .. ' por $' .. anuncio.preco)

    VOID.registrarAuditoria(transacaoId, userId,
        'Comprou item marketplace',
        { marketplace_id = marketplaceId, serialkeys = serialkeys }
    )

    return true
end

function VOID.obterMarketplaceData(userId)
    local limiteItens = (Config.marketplace and Config.marketplace.limite_itens) or 200
    local limiteRecentes = (Config.marketplace and Config.marketplace.limite_recentes) or 15
    local itens = vRP.query('inventario/listar_anuncios_ativos', { limite = limiteItens })
    local recentes = vRP.query('inventario/listar_anuncios_recentes', { limite = limiteRecentes })
    local mochila = VOID.listarMochila(userId)

    local function ajustar(lista)
        for _, item in ipairs(lista or {}) do
            item.label = obterNomeItem(item.item_name)
            item.icon = obterIndexItem(item.item_name)
        end
        return lista
    end

    return {
        items = ajustar(itens),
        recent = ajustar(recentes),
        myItems = mochila,
        me = userId
    }
end

function VOID.calcularDesconto(quantidade)
    local desconto = 0
    local melhor = 0
    if Config and Config.lojas and Config.lojas.desconto_progressivo then
        for qtd, pct in pairs(Config.lojas.desconto_progressivo) do
            if quantidade >= qtd and qtd >= melhor then
                melhor = qtd
                desconto = pct
            end
        end
    end
    return desconto
end

function VOID.comprarDaLoja(userId, lojaId, itemName, quantidade)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    if quantidadeNum <= 0 then
        return false, 'quantidade_invalida'
    end

    local lojaResolvida, loja = resolverLojaId(lojaId)
    if not loja or tonumber(loja.ativa) ~= 1 then
        return false, 'loja_invalida'
    end
    lojaId = lojaResolvida

    local itemLoja = vRP.query('lojas/obter_item_loja', { loja_id = lojaId, item_name = itemName })
    itemLoja = itemLoja[1]
    if not itemLoja or tonumber(itemLoja.estoque_atual) < quantidadeNum then
        return false, 'estoque_insuficiente'
    end

    local _, pesoAtual, pesoMax = VOID.listarMochila(userId)
    local pesoTotal = (obterPesoItem(itemName) * quantidadeNum)
    if pesoAtual + pesoTotal > pesoMax then
        return false, 'peso_excedido'
    end

    local desconto = VOID.calcularDesconto(quantidadeNum)
    local precoUnit = itemLoja.preco_compra
    local precoFinal = math.floor((precoUnit * quantidadeNum) * (1 - (desconto / 100)))

    local transacaoId = VOID.criarTransacao(userId, 'compra_loja', {
        item_name = itemName,
        quantidade = quantidadeNum,
        preco = precoFinal,
        loja_id = lojaId
    })

    vRP.execute('inventario/iniciar_transacao_db')

    if not vRP.tryPayment(userId, precoFinal) then
        vRP.execute('inventario/rollback_transacao_db')
        VOID.registrarFalhaTransacao(transacaoId, 'saldo_insuficiente')
        return false, 'saldo_insuficiente'
    end

    local serialkeys, erro = VOID.criarItensDB(userId, itemName, quantidadeNum, Const.TIPO_ARMAZENAMENTO.MOCHILA, nil)
    if not serialkeys then
        vRP.execute('inventario/rollback_transacao_db')
        vRP.giveMoney(userId, precoFinal)
        VOID.registrarFalhaTransacao(transacaoId, erro)
        return false, erro
    end

    local okEstoque = vRP.execute('lojas/deduzir_estoque', { loja_id = lojaId, item_name = itemName, quantidade = quantidadeNum })
    if not okEstoque or okEstoque < 1 then
        vRP.execute('inventario/rollback_transacao_db')
        vRP.giveMoney(userId, precoFinal)
        VOID.registrarFalhaTransacao(transacaoId, 'erro_estoque')
        return false, 'erro_estoque'
    end

    vRP.execute('lojas/atualizar_saldo_caixa', { loja_id = lojaId, valor = precoFinal })

    vRP.execute('lojas/registrar_venda_loja', {
        venda_id = Utils.gerarUUID(),
        loja_id = lojaId,
        user_id = userId,
        item_name = itemName,
        quantidade = quantidadeNum,
        preco_unitario = precoUnit,
        preco_total = precoFinal,
        tipo_transacao = 'compra'
    })

    vRP.execute('inventario/commit_transacao_db')

    vRP.execute('inventario/conclusao_transacao', {
        transaction_id = transacaoId,
        status = 'completa',
        serialkeys_envolvidas = Utils.jsonEncode(serialkeys)
    })

    if VOID.syncVrpGiveInventoryItem then
        VOID.syncVrpGiveInventoryItem(userId, itemName, quantidadeNum, true)
    end

    VOID.registrarWebhookLoja('Compra em loja: ' .. itemName .. ' x' .. quantidadeNum .. ' por $' .. precoFinal)

    VOID.registrarAuditoria(transacaoId, userId,
        'Comprou item em loja',
        { loja_id = lojaId, item = itemName, quantidade = quantidadeNum, preco = precoFinal }
    )

    return true
end

function VOID.venderParaLoja(userId, lojaId, itemName, quantidade)
    local quantidadeNum = Utils.safeNumber(quantidade, 0)
    if quantidadeNum <= 0 then
        return false, 'quantidade_invalida'
    end

    if not (Config and Config.lojas and Config.lojas.permitir_venda_para_servidor) then
        return false, 'venda_desativada'
    end

    local lojaResolvida, loja = resolverLojaId(lojaId)
    if not loja or tonumber(loja.ativa) ~= 1 then
        return false, 'loja_invalida'
    end
    lojaId = lojaResolvida

    local itemLoja = vRP.query('lojas/obter_item_loja', { loja_id = lojaId, item_name = itemName })
    itemLoja = itemLoja[1]
    if not itemLoja or Utils.safeNumber(itemLoja.preco_venda, 0) <= 0 then
        return false, 'loja_nao_compra'
    end

    local saldo = vRP.query('lojas/obter_saldo_caixa', { loja_id = lojaId })
    local saldoAtual = saldo[1] and Utils.safeNumber(saldo[1].saldo_caixa, 0) or 0
    local total = itemLoja.preco_venda * quantidadeNum
    if saldoAtual < total then
        return false, 'saldo_loja_insuficiente'
    end

    local itens = vRP.query('inventario/obter_itens_usuario', {
        user_id = userId,
        item_name = itemName,
        tipo_armazenamento = Const.TIPO_ARMAZENAMENTO.MOCHILA,
        limite = quantidadeNum
    })
    if #itens < quantidadeNum then
        return false, 'quantidade_insuficiente'
    end

    local serialkeys = {}
    for i = 1, quantidadeNum do
        serialkeys[#serialkeys + 1] = itens[i].serialkey
    end

    local transacaoId = VOID.criarTransacao(userId, 'venda_loja', {
        item_name = itemName,
        quantidade = quantidadeNum,
        preco = total,
        loja_id = lojaId
    })

    vRP.execute('inventario/iniciar_transacao_db')

    local ok = VOID.removerItensDB(serialkeys)
    if not ok then
        vRP.execute('inventario/rollback_transacao_db')
        VOID.registrarFalhaTransacao(transacaoId, 'erro_remover_item')
        return false, 'erro_remover_item'
    end

    vRP.execute('lojas/aumentar_estoque', { loja_id = lojaId, item_name = itemName, quantidade = quantidadeNum })
    vRP.execute('lojas/atualizar_saldo_caixa', { loja_id = lojaId, valor = -total })

    vRP.execute('lojas/registrar_venda_loja', {
        venda_id = Utils.gerarUUID(),
        loja_id = lojaId,
        user_id = userId,
        item_name = itemName,
        quantidade = quantidadeNum,
        preco_unitario = itemLoja.preco_venda,
        preco_total = total,
        tipo_transacao = 'venda'
    })

    vRP.execute('inventario/commit_transacao_db')

    vRP.execute('inventario/conclusao_transacao', {
        transaction_id = transacaoId,
        status = 'completa',
        serialkeys_envolvidas = Utils.jsonEncode(serialkeys)
    })

    if VOID.syncVrpTryGetInventoryItem then
        VOID.syncVrpTryGetInventoryItem(userId, itemName, quantidadeNum, true)
    end
    vRP.giveMoney(userId, total)

    VOID.registrarWebhookLoja('Venda para loja: ' .. itemName .. ' x' .. quantidadeNum .. ' por $' .. total)

    VOID.registrarAuditoria(transacaoId, userId,
        'Vendeu item para loja',
        { loja_id = lojaId, item = itemName, quantidade = quantidadeNum, preco = total }
    )

    return true, total
end

return VOID
