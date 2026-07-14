-- shared/config.lua — configuração estática do vhub_coinshop (PT-BR, server+client)

VHubCoin = VHubCoin or {}
VHubCoin.cfg = {


    -- ============================================================
    -- GERAL
    -- ============================================================

    -- habilita logs de depuração no console do servidor (produção: false)
    debug = false,

    -- comando ADMIN para abrir a NUI fullscreen (server-side; jogador usa o app do iPad).
    -- keybind F5 REMOVIDO (decisão #58): a loja do jogador vive no iPad.
    command = 'coinshop',


    -- ============================================================
    -- CDN DE IMAGENS — URLs base por categoria (derivadas em runtime; não duplicar nos seeds)
    -- ============================================================

    cdn = {
        -- veículos: modelo (spawn_name) vira o nome do arquivo
        vehicles = 'https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/%s.png',
        -- itens consumíveis (item_name)
        items    = 'https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/items/%s.png',
        -- armas (weapon_name, lowercase)
        weapons  = 'https://raw.githubusercontent.com/aifazi/items-images/main/weapons/%s.png',
    },


    -- ============================================================
    -- REDE -- RATE LIMIT (orçamento L-18, throttle O(1) por src+chave)
    -- ============================================================

    -- intervalos mínimos (ms) entre ações do mesmo jogador — evento novo nasce com rate (§4.6)
    rates = {
        openShop      = 1000,   -- abrir a loja
        purchaseItem  = 500,    -- comprar item
        purchaseDeal  = 500,    -- comprar oferta
        redeemCode    = 2000,   -- resgatar código (anti-brute-force)
        adminAction   = 300,    -- qualquer ação admin (CRUD, give/set)
        getOnlineList = 5000,   -- refresh da lista de players online
        getCoins      = 1000,   -- leitura de saldo (folgado; anti-spam de dispatch)
        importPreview = 750,    -- leitura administrativa de fontes externas
        importRun     = 1500,   -- escrita em lote do catálogo
        adminCatalog  = 3000,   -- fetch de catálogo externo para pickers admin
    },


    -- ============================================================
    -- IMPORTAÇÃO ADMIN — snapshots externos viram rascunhos locais
    -- ============================================================

    import = {
        maxItems  = 500, -- teto por preview/execução; evita lote hostil
        batchSize = 100, -- INSERT IGNORE agrupado; evita N queries por item
    },


    -- ============================================================
    -- ADMIN -- permissão ACE canônica (owner uid=1 > ACE > grupos)
    -- ============================================================

    -- permissão exigida para o painel admin (registrada no vhub_groups)
    adminPermission = 'coinshop.admin',


    -- ============================================================
    -- INTEGRAÇÕES OPCIONAIS (todas seguras por pcall + flag off por padrão)
    -- ============================================================

    -- avatar Discord do jogador no cabeçalho da NUI (requer bot token; vazio = desligado)
    discordBotToken = '',

    -- webhooks Discord para auditoria (vazio = desligado)
    webhooks = {
        purchases = '',
        redeems   = '',
        admin     = '',
    },

    webhookName   = 'vHub Coinshop',
    webhookAvatar = 'https://raw.githubusercontent.com/Void-Cla/vhub-assets/main/logo.png',

    -- cores dos embeds (Decimal) por categoria de webhook
    webhookColors = {
        purchases = 11206152,  -- areia/dourado escuro
        redeems   = 3066993,   -- verde sutil
        admin     = 15548997,  -- âmbar
    },


    -- ============================================================
    -- PIX — compra de moedas (decisão #59 + #60; gateway central via vhub_df)
    -- ============================================================
    --
    -- provider = 'vhub_df': a cobrança nasce no gateway central (exports.vhub_df),
    -- que re-verifica status E valor na API do MP antes de creditar (server/pix_df.lua).
    -- Credenciais: convar df_mp_key em config/local.cfg (do vhub_df — NUNCA versionar).
    -- 'mercadopago' mantém o caminho legado do pix_mp.lua (webhook /webhook/mp-pix).
    --
    -- O gate real de disponibilidade vive no vhub_df (enabled + token); com o gateway
    -- desligado o jogador vê mensagem amigável no lugar do QR.
    pix = {
        enabled  = true,            -- aba visível no app; indisponibilidade vem do gateway
        provider = 'vhub_df',       -- 'vhub_df' (central) | 'mercadopago' (legado) | nil (stub)

        -- expiração da cobrança Pix em minutos (MP aceita até 1440 = 24h)
        expiresInMinutes = 30,

        -- Regra comercial imutável: R$ 1,00 = 1 coin; sem bônus.
        -- Tier para destaque visual (1=bronze, 2=prata, 3=ouro).
        packages = {
            { id = 'pix_1',   tier = 1, name = 'Pacote Start',  coins = 1,   bonus = 0, priceBRL = 1.00,   popular = false },
            { id = 'pix_10',  tier = 2, name = 'Pacote Prata',  coins = 10,  bonus = 0, priceBRL = 10.00,  popular = true  },
            { id = 'pix_100', tier = 3, name = 'Pacote Ouro',   coins = 100, bonus = 0, priceBRL = 100.00, popular = false },
        },
    },


    -- ============================================================
    -- IDENTIDADE VISUAL DA NUI (passada ao app no `open`)
    -- ============================================================

    -- logo exibido no cabeçalho (URL raw GitHub do asset vHub)
    logo = 'https://raw.githubusercontent.com/Void-Cla/vhub-assets/main/logo.png',

    -- hora UTC (0-23) em que ofertas diárias são consideradas "resetadas" para exibição
    dealResetHour = 0,
}
