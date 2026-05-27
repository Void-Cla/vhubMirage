local Proxy = module('vrp', 'lib/Proxy')
local vRP = Proxy.getInterface('vRP')

-- Transacoes
vRP.prepare('inventario/iniciar_transacao_db', 'START TRANSACTION')
vRP.prepare('inventario/commit_transacao_db', 'COMMIT')
vRP.prepare('inventario/rollback_transacao_db', 'ROLLBACK')

vRP.prepare('inventario/criar_item', [[
    INSERT INTO vrp_inventario_itens
    (serialkey, user_id, item_name, quantidade, tipo_armazenamento, container_id, checksum)
    VALUES (@serialkey, @user_id, @item_name, @quantidade, @tipo_armazenamento, @container_id, @checksum)
]])

vRP.prepare('inventario/remover_item', [[
    UPDATE vrp_inventario_itens
    SET deleted_at = @deleted_at
    WHERE serialkey = @serialkey AND deleted_at IS NULL
]])

vRP.prepare('inventario/transferir_serialkey', [[
    UPDATE vrp_inventario_itens
    SET user_id = @novo_user_id,
        tipo_armazenamento = @tipo_armazenamento,
        container_id = @container_id
    WHERE serialkey = @serialkey AND deleted_at IS NULL
]])

vRP.prepare('inventario/obter_item_serialkey', [[
    SELECT * FROM vrp_inventario_itens
    WHERE serialkey = @serialkey AND deleted_at IS NULL
    LIMIT 1
]])

vRP.prepare('inventario/obter_itens_usuario', [[
    SELECT * FROM vrp_inventario_itens
    WHERE user_id = @user_id AND item_name = @item_name
      AND tipo_armazenamento = @tipo_armazenamento
      AND deleted_at IS NULL
    ORDER BY id ASC
    LIMIT @limite
]])

vRP.prepare('inventario/obter_todos_itens', [[
    SELECT * FROM vrp_inventario_itens
    WHERE user_id = @user_id AND deleted_at IS NULL
    ORDER BY id ASC
]])

vRP.prepare('inventario/obter_itens_container', [[
    SELECT * FROM vrp_inventario_itens
    WHERE tipo_armazenamento = @tipo_armazenamento
      AND container_id = @container_id
      AND deleted_at IS NULL
    ORDER BY id ASC
]])

vRP.prepare('inventario/obter_itens_mochila_agregado', [[
    SELECT item_name, COUNT(*) AS quantidade
    FROM vrp_inventario_itens
    WHERE user_id = @user_id AND tipo_armazenamento = 'mochila' AND deleted_at IS NULL
    GROUP BY item_name
    ORDER BY item_name ASC
]])

vRP.prepare('inventario/obter_itens_container_agregado', [[
    SELECT item_name, COUNT(*) AS quantidade
    FROM vrp_inventario_itens
    WHERE tipo_armazenamento = @tipo_armazenamento
      AND container_id = @container_id
      AND deleted_at IS NULL
    GROUP BY item_name
    ORDER BY item_name ASC
]])

vRP.prepare('inventario/contar_itens_usuario', [[
    SELECT COUNT(*) AS total
    FROM vrp_inventario_itens
    WHERE user_id = @user_id AND item_name = @item_name
      AND tipo_armazenamento = @tipo_armazenamento
      AND deleted_at IS NULL
]])

vRP.prepare('inventario/obter_anuncio_lock', [[
    SELECT * FROM vrp_inventario_marketplace
    WHERE marketplace_id = @marketplace_id AND status = 'ativo'
    FOR UPDATE
]])

vRP.prepare('inventario/obter_anuncio', [[
    SELECT * FROM vrp_inventario_marketplace
    WHERE marketplace_id = @marketplace_id
    LIMIT 1
]])

vRP.prepare('inventario/listar_anuncios_ativos', [[
    SELECT * FROM vrp_inventario_marketplace
    WHERE status = 'ativo'
    ORDER BY created_at DESC
    LIMIT @limite
]])

vRP.prepare('inventario/listar_anuncios_recentes', [[
    SELECT * FROM vrp_inventario_marketplace
    WHERE status = 'vendido'
    ORDER BY data_venda DESC
    LIMIT @limite
]])

vRP.prepare('inventario/contar_anuncios_usuario', [[
    SELECT COUNT(*) AS total
    FROM vrp_inventario_marketplace
    WHERE seller_id = @seller_id AND status = 'ativo'
]])

vRP.prepare('inventario/criar_anuncio', [[
    INSERT INTO vrp_inventario_marketplace
    (marketplace_id, seller_id, seller_name, item_name, quantidade, preco, descricao, serialkeys_anunciadas)
    VALUES (@marketplace_id, @seller_id, @seller_name, @item_name, @quantidade, @preco, @descricao, @serialkeys_anunciadas)
]])

vRP.prepare('inventario/cancelar_anuncio', [[
    UPDATE vrp_inventario_marketplace
    SET status = 'cancelado'
    WHERE marketplace_id = @marketplace_id AND status = 'ativo'
]])

vRP.prepare('inventario/marcar_anuncio_vendido', [[
    UPDATE vrp_inventario_marketplace
    SET status = 'vendido', comprador_id = @comprador_id, data_venda = @data_venda
    WHERE marketplace_id = @marketplace_id
]])

vRP.prepare('inventario/criar_transacao', [[
    INSERT INTO vrp_inventario_transacoes
    (transaction_id, user_id, tipo_operacao, item_name, quantidade,
     serialkeys_envolvidas, dados_transacao, status)
    VALUES (@transaction_id, @user_id, @tipo_operacao, @item_name,
            @quantidade, @serialkeys_envolvidas, @dados_transacao, @status)
]])

vRP.prepare('inventario/conclusao_transacao', [[
    UPDATE vrp_inventario_transacoes
    SET status = @status, data_conclusao = NOW(), serialkeys_envolvidas = @serialkeys_envolvidas
    WHERE transaction_id = @transaction_id
]])

vRP.prepare('inventario/falha_transacao', [[
    UPDATE vrp_inventario_transacoes
    SET status = 'falhada', erro_descricao = @erro_descricao, data_conclusao = NOW()
    WHERE transaction_id = @transaction_id
]])

vRP.prepare('inventario/registrar_auditoria', [[
    INSERT INTO vrp_inventario_auditoria
    (transaction_id, user_id, acao, detalhes, ip_origem)
    VALUES (@transaction_id, @user_id, @acao, @detalhes, @ip_origem)
]])

vRP.prepare('inventario/obter_auditoria_usuario', [[
    SELECT * FROM vrp_inventario_auditoria
    WHERE user_id = @user_id
    ORDER BY data_criacao DESC
    LIMIT @limite
]])

vRP.prepare('inventario/obter_auditoria_recente', [[
    SELECT * FROM vrp_inventario_auditoria
    ORDER BY data_criacao DESC
    LIMIT @limite
]])

vRP.prepare('inventario/remover_serialkeys_duplicadas', [[
    DELETE FROM vrp_inventario_itens
    WHERE serialkey = @serialkey
    LIMIT (SELECT COUNT(*) - 1 FROM (
        SELECT id FROM vrp_inventario_itens
        WHERE serialkey = @serialkey
    ) t)
]])

vRP.prepare('inventario/obter_transacoes_pendentes', [[
    SELECT * FROM vrp_inventario_transacoes
    WHERE user_id = @user_id
      AND status = 'pendente'
      AND TIMESTAMPDIFF(SECOND, data_criacao, NOW()) > @tempo_limite
]])

vRP.prepare('inventario/marcar_transacao_revertida', [[
    UPDATE vrp_inventario_transacoes
    SET status = 'revertida'
    WHERE transaction_id = @transaction_id
]])

-- Lojas NPC
vRP.prepare('lojas/criar_loja', [[
    INSERT INTO vrp_lojas
    (loja_id, nome, descricao, proprietario, localizacao_x, localizacao_y,
     localizacao_z, tipo_loja, ativa, raio_atuacao)
    VALUES (@loja_id, @nome, @descricao, @proprietario, @localizacao_x,
            @localizacao_y, @localizacao_z, @tipo_loja, 1, @raio_atuacao)
]])

vRP.prepare('lojas/obter_loja', [[
    SELECT * FROM vrp_lojas WHERE loja_id = @loja_id AND ativa = 1
]])

vRP.prepare('lojas/obter_loja_por_id', [[
    SELECT * FROM vrp_lojas WHERE id = @id AND ativa = 1
]])

vRP.prepare('lojas/obter_lojas_proximas', [[
    SELECT * FROM vrp_lojas
    WHERE ativa = 1
      AND SQRT(POW(localizacao_x - @x, 2) + POW(localizacao_y - @y, 2)) <= @raio
    ORDER BY SQRT(POW(localizacao_x - @x, 2) + POW(localizacao_y - @y, 2)) ASC
]])

vRP.prepare('lojas/obter_itens_loja', [[
    SELECT * FROM vrp_lojas_itens
    WHERE loja_id = @loja_id AND ativo = 1 AND estoque_atual > 0
    ORDER BY item_name ASC
]])

vRP.prepare('lojas/obter_item_loja', [[
    SELECT * FROM vrp_lojas_itens
    WHERE loja_id = @loja_id AND item_name = @item_name AND ativo = 1
    LIMIT 1
]])

vRP.prepare('lojas/adicionar_item_loja', [[
    INSERT INTO vrp_lojas_itens
    (loja_id, item_name, preco_compra, preco_venda, estoque_maximo, estoque_atual)
    VALUES (@loja_id, @item_name, @preco_compra, @preco_venda, @estoque_maximo, @estoque_atual)
    ON DUPLICATE KEY UPDATE
    preco_compra = @preco_compra, preco_venda = @preco_venda
]])

vRP.prepare('lojas/atualizar_item_loja', [[
    UPDATE vrp_lojas_itens
    SET preco_compra = @preco_compra,
        preco_venda = @preco_venda,
        estoque_maximo = @estoque_maximo,
        ativo = 1
    WHERE loja_id = @loja_id AND item_name = @item_name
]])

vRP.prepare('lojas/atualizar_estoque', [[
    UPDATE vrp_lojas_itens
    SET estoque_atual = @estoque_novo
    WHERE loja_id = @loja_id AND item_name = @item_name
]])

vRP.prepare('lojas/deduzir_estoque', [[
    UPDATE vrp_lojas_itens
    SET estoque_atual = estoque_atual - @quantidade
    WHERE loja_id = @loja_id AND item_name = @item_name
      AND estoque_atual >= @quantidade
]])

vRP.prepare('lojas/aumentar_estoque', [[
    UPDATE vrp_lojas_itens
    SET estoque_atual = LEAST(estoque_atual + @quantidade, estoque_maximo)
    WHERE loja_id = @loja_id AND item_name = @item_name
]])

vRP.prepare('lojas/atualizar_saldo_caixa', [[
    UPDATE vrp_lojas
    SET saldo_caixa = saldo_caixa + @valor
    WHERE loja_id = @loja_id
]])

vRP.prepare('lojas/obter_saldo_caixa', [[
    SELECT saldo_caixa FROM vrp_lojas WHERE loja_id = @loja_id
]])

vRP.prepare('lojas/registrar_venda_loja', [[
    INSERT INTO vrp_lojas_vendas
    (venda_id, loja_id, user_id, item_name, quantidade, preco_unitario, preco_total, tipo_transacao)
    VALUES (@venda_id, @loja_id, @user_id, @item_name, @quantidade,
            @preco_unitario, @preco_total, @tipo_transacao)
]])

vRP.prepare('lojas/obter_historico_vendas', [[
    SELECT * FROM vrp_lojas_vendas
    WHERE loja_id = @loja_id
    ORDER BY data_venda DESC
    LIMIT @limite
]])

vRP.prepare('lojas/obter_vendas_jogador', [[
    SELECT * FROM vrp_lojas_vendas
    WHERE user_id = @user_id
    ORDER BY data_venda DESC
    LIMIT @limite
]])
