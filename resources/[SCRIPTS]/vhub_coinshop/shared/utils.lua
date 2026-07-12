-- shared/utils.lua — helpers puros do vhub_coinshop (sem estado, sem natives)

VHubCoin = VHubCoin or {}


-- ============================================================
-- LOCALIZAÇÃO (apenas PT-BR — L-08)
-- ============================================================

VHubCoin.locale = {


    -- GERAL
    coin_shop                  = 'Loja de Moedas',
    close                      = 'Fechar',
    cancel                     = 'Cancelar',
    confirm                    = 'Confirmar',
    save                       = 'Salvar',
    delete                     = 'Excluir',
    edit                       = 'Editar',
    create                     = 'Criar',
    refresh                    = 'Atualizar',

    -- CLIENTE — notificações
    vehicle_not_found          = 'Veículo não encontrado',
    failed_load_vehicle        = 'Falha ao carregar modelo do veículo',
    vehicle_purchased          = 'Veículo comprado. Retire-o na garagem. Placa: %s',

    -- SERVIDOR — mensagens
    no_permission              = 'Sem permissão',
    player_not_found           = 'Jogador não encontrado',
    item_not_found             = 'Item não encontrado',
    not_enough_coins           = 'Moedas insuficientes',
    failed_register_vehicle    = 'Falha ao registrar veículo',
    purchase_successful        = 'Compra realizada com sucesso',
    purchase_in_progress       = 'Compra em andamento, aguarde',
    failed_give_item           = 'Falha ao entregar item',
    failed_give_weapon         = 'Falha ao entregar arma',
    invalid_order_number       = 'Número de pedido inválido',
    invalid_order_detailed     = 'Número de pedido inválido. Certifique-se de que comprou um pacote de moedas e inseriu o número de pedido correto (ex: tbx-xxxxxxxxxxxxx-xxxxxx).',
    order_already_redeemed     = 'Este pedido já foi resgatado',
    successfully_redeemed      = '%d moedas resgatadas com sucesso',
    target_not_found           = 'Jogador alvo não encontrado ou offline',
    received_coins_gift        = 'Você recebeu %d moedas de presente!',
    received_coins             = 'Você recebeu %d moedas!',
    coins_set_to               = 'Suas moedas foram definidas para %d',
    invalid_data               = 'Dados inválidos',
    invalid_target_amount      = 'Alvo ou quantidade inválidos',
    coin_persistence_failed    = 'Falha ao persistir moedas. Nenhuma operação foi concluída.',

    -- ADMIN
    item_name_required         = 'Nome do item é obrigatório',
    item_price_required        = 'Item publicado precisa ter preço maior que zero',
    item_id_exists             = 'Já existe um item com este ID',
    item_id_required           = 'ID do item é obrigatório',
    item_created               = 'Item "%s" criado com sucesso',
    item_updated               = 'Item "%s" atualizado com sucesso',
    item_deleted               = 'Item deletado com sucesso',
    category_name_required     = 'Nome da categoria é obrigatório',
    category_exists            = 'Já existe uma categoria com este nome',
    category_id_required       = 'ID da categoria é obrigatório',
    category_not_found         = 'Categoria não encontrada',
    category_created           = 'Categoria "%s" criada com sucesso',
    category_updated           = 'Categoria "%s" atualizada com sucesso',
    category_deleted           = 'Categoria deletada com sucesso',
    deal_name_required         = 'Nome da oferta é obrigatório',
    valid_expiry_required      = 'Tempo de expiração válido é obrigatório',
    deal_items_limit           = 'Selecione 1-10 itens para a oferta',
    deal_created               = 'Oferta "%s" criada com sucesso',
    deal_id_required           = 'ID da oferta é obrigatório',
    deal_updated               = 'Oferta atualizada com sucesso',
    deal_deleted               = 'Oferta deletada com sucesso',
    code_deleted               = 'Código pendente apagado',
    deal_not_found             = 'Oferta não encontrada ou expirada',
    deal_no_items              = 'Oferta não tem itens',
    deal_purchased             = 'Oferta comprada com sucesso!',
    all_cleared                = 'Todos os pacotes, categorias e ofertas foram limpos',
    gave_coins                 = 'Deu %d moedas ao jogador %s',
    set_coins_msg              = 'Moedas do jogador %s definidas para %d',
    settings_saved             = 'Configurações salvas',
    settings_reset             = 'Configurações restauradas para padrão',
    settings_persistence_failed = 'Falha ao persistir configurações',

    -- COMANDOS
    usage_givecoins            = 'Uso: /givecoins [id] [quantidade]',
    usage_setcoins             = 'Uso: /setcoins [id] [quantidade]',

    -- NUI — navegação
    ui_home                    = 'Início',
    ui_tutorial                = 'Tutorial',
    ui_redeem                  = 'Resgatar',
    ui_admin                   = 'Admin',

    -- NUI — home
    ui_browse_items            = 'Explorar Itens',
    ui_explore_items           = 'Explore todos os itens disponíveis.',
    ui_search_placeholder      = 'Pesquisar item aqui ...',
    ui_browse                  = 'Explorar %s',
    ui_explore                 = 'Explore todos os %s disponíveis na loja',
    ui_search                  = 'Pesquisar %s aqui ...',
    ui_coins                   = 'Moedas',

    -- NUI — tutorial
    ui_tutorial_desc           = 'Esta seção mostrará tudo que você precisa saber sobre como usar este sistema',
    ui_step_1                  = 'Passo 1',
    ui_step_2                  = 'Passo 2',
    ui_step_3                  = 'Passo 3',
    ui_step_3_title            = 'Passo 3 - Como Presentear',
    ui_tutorial_step_1         = 'Primeiro obtenha o TBX ID aqui:',
    ui_tutorial_step_2         = 'Quando tiver o TBX ID, vá para resgatar e cole o TBX ID na caixa de resgate',
    ui_tutorial_step_3         = 'Opcionalmente, se quiser presentear alguém, clique em "Presentear Alguém". A pessoa deve estar online. Coloque o ID do servidor dela e cole o TBX ID e ela receberá as moedas.',

    -- NUI — pagamento
    ui_confirm_payment         = 'Confirmar Pagamento',
    ui_confirm_question        = 'Tem certeza que deseja confirmar?',

    -- NUI — resgate
    ui_redeem_settings         = 'Configurações de Resgate',
    ui_redeem_desc             = 'Insira seu número de pedido Tebex para resgatar moedas.',
    ui_redeem_yourself         = 'Resgatar Para Você',
    ui_gift_someone            = 'Presentear Alguém',
    ui_player_id               = 'ID do Jogador',
    ui_enter_player_id         = 'Digite o ID do jogador ...',
    ui_enter_redeem_key        = 'Digite a Chave de Resgate',
    ui_redeem_placeholder      = 'tbx-xxxxxxxxxxxxx-xxxxxx',

    -- NUI — admin
    ui_admin_panel             = 'Painel Admin',
    ui_admin_center            = 'Centro Admin',
    ui_creator_center          = 'Centro do Criador',
    ui_player_management       = 'Gerenciamento de Jogadores',
    ui_customize_ui            = 'Personalizar Interface',
    ui_total_packages          = 'Total de Pacotes',
    ui_total_sales             = 'Total de Vendas',
    ui_coins_spent_24h         = 'Moedas Gastas (24h)',
    ui_active_players          = 'Jogadores Ativos',
    ui_recent_transactions     = 'Transações Recentes',
    ui_top_selling             = 'Mais Vendidos',

    -- NUI — criador
    ui_create_package          = '+ Criar Pacote',
    ui_create_category         = '+ Criar Categoria',
    ui_create_deal             = '+ Criar Oferta Especial',
    ui_clear_all               = 'Limpar Todos os Pacotes, Categorias e Ofertas',
    ui_custom_categories       = 'Categorias Personalizadas',
    ui_active_deals            = 'Ofertas Ativas',
    ui_existing_packages       = 'Pacotes Existentes',

    -- NUI — gerenciamento de players
    ui_search_player           = 'Pesquisar jogador por ID ou nome...',
    ui_give_coins              = 'Dar Moedas',
    ui_set_coins               = 'Definir Moedas',
    ui_online_players          = 'Jogadores Online',
    ui_id                      = 'ID',
    ui_name                    = 'Nome',
    ui_actions                 = 'Ações',
    ui_activity_logs           = 'Logs de Atividade',
    ui_amount                  = 'Quantidade',
    ui_enter_amount            = 'Digite a quantidade...',

    -- NUI — customização
    ui_colors                  = 'Cores',
    ui_accent_color            = 'Cor de Destaque',
    ui_bg_color                = 'Cor de Fundo',
    ui_text_color              = 'Cor do Texto',
    ui_error_color             = 'Cor de Erro',
    ui_card_border_color       = 'Cor da Borda do Cartão',
    ui_background              = 'Fundo',
    ui_image_url               = 'URL da Imagem',
    ui_opacity                 = 'Opacidade',
    ui_blur                    = 'Desfoque',
    ui_cards                   = 'Cartões',
    ui_bg_opacity              = 'Opacidade do Fundo',
    ui_border_radius           = 'Raio da Borda',
    ui_coin_icon               = 'Ícone da Moeda',
    ui_icon_url                = 'URL do Ícone',
    ui_save_settings           = 'Salvar Configurações',
    ui_reset_defaults          = 'Restaurar Padrões',

    -- NUI — modais criar/editar
    ui_create_package_title    = 'Criar Pacote',
    ui_edit_package_title      = 'Editar Pacote',
    ui_description             = 'Descrição',
    ui_price_coins             = 'Preço (Moedas)',
    ui_type                    = 'Tipo',
    ui_vehicle                 = 'Veículo',
    ui_item                    = 'Item',
    ui_weapon                  = 'Arma',
    ui_tool                    = 'Ferramenta',
    ui_category                = 'Categoria',
    ui_category_optional       = '(opcional - atribuir a uma aba de categoria personalizada)',
    ui_none_default            = 'Nenhum (Padrão)',
    ui_spawn_name              = 'Nome de Spawn',
    ui_spawn_hint              = '(nome do modelo GTA, ex: adder)',
    ui_item_name               = 'Nome do Item',
    ui_item_hint               = '(item do inventário)',
    ui_count                   = 'Quantidade',
    ui_weapon_name             = 'Nome da Arma',
    ui_weapon_hint             = '(hash de arma GTA)',
    ui_icon                    = 'Ícone',
    ui_icon_hint               = '(mostrado na aba de navegação)',
    ui_tags                    = 'Tags (separadas por vírgula)',
    ui_mark_trending           = 'Marcar como Tendência',
    ui_live_preview            = 'Pré-visualização',

    -- NUI — oferta
    ui_create_deal_title       = 'Criar Oferta Especial',
    ui_expires_in              = 'Expira Em',
    ui_select_items            = 'Selecionar Itens (Máx 10)',
    ui_search_items            = 'Pesquisar itens...',
    ui_confirm_deal            = 'Confirmar Compra da Oferta',
    ui_items_included          = 'Itens incluídos:',

    -- NUI — exclusão/limpar
    ui_confirm_delete          = 'Confirmar Exclusão',
    ui_delete_msg              = 'Tem certeza que deseja excluir "%s"? Isso não pode ser desfeito.',
    ui_clear_all_title         = 'Limpar Todos os Dados',
    ui_clear_all_msg           = 'Isso excluirá permanentemente todos os pacotes, categorias e ofertas da loja. Esta ação não pode ser desfeita.',
    ui_clear_everything        = 'Limpar Tudo',

    -- NUI — misc
    ui_expired                 = 'EXPIRADO',
    ui_no_image                = 'Sem Imagem',
    ui_trending                = 'Tendência',
    ui_enter_name              = 'Digite o nome...',
    ui_enter_description       = 'Digite a descrição...',
    ui_enter_price             = 'Digite o preço...',
    ui_enter_deal_name         = 'Digite o nome da oferta...',
    ui_enter_image_url         = 'Digite o URL da imagem...',
}


-- retorna string localizada; suporta parâmetros via string.format
function VHubCoin.T(key, ...)
    local str = VHubCoin.locale[key] or key
    if select('#', ...) > 0 then
        local ok, result = pcall(string.format, str, ...)
        if ok then return result end
    end
    return str
end

-- atalho global T (compatível com handlers legados)
function T(key, ...) return VHubCoin.T(key, ...) end


-- ============================================================
-- HELPERS DE SHAPE — validação server-side antes do domínio (zero-trust)
-- ============================================================

-- retorna true se v é string não-vazia
function VHubCoin.isNonEmptyStr(v)
    return type(v) == 'string' and v ~= ''
end

-- retorna true se v é inteiro dentro de [min, max] (max nil = sem teto)
function VHubCoin.isInt(v, min, max)
    local n = tonumber(v)
    if not n or math.floor(n) ~= n then return false end
    if min and n < min then return false end
    if max and n > max then return false end
    return true
end

-- retorna true se v é array de strings (cada item dentro de maxLen)
function VHubCoin.isStrArray(v, maxLen, maxItems)
    if type(v) ~= 'table' then return false end
    local count = 0
    for _, s in ipairs(v) do
        count = count + 1
        if maxItems and count > maxItems then return false end
        if type(s) ~= 'string' or #s > (maxLen or 500) then return false end
    end
    return true
end

-- clamp numérico para faixa segura (evita overflow / NaN)
function VHubCoin.clamp(v, min, max)
    local n = tonumber(v)
    if not n then return min end
    if n < min then return min end
    if max and n > max then return max end
    return n
end
