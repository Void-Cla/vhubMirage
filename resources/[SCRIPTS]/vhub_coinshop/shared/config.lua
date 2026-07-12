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
    -- PIX — compra de moedas com MercadoPago (decisão #59 + #60)
    -- ============================================================
    --
    -- ATIVAÇÃO (dois passos):
    --   1. No server.cfg (NUNCA versionar a chave):
    --        setr coinshop_mp_key "APP_USR-SEU_ACCESS_TOKEN_AQUI"
    --        setr coinshop_mp_webhook_secret "SUA_CHAVE_SECRETA_WEBHOOK"
    --   2. Altere enabled=true e provider='mercadopago' aqui.
    --
    -- Enquanto enabled=false → resposta stub {ok=false, code='pix_disabled'}.
    -- O frontend já consome o contrato real — a aba aparece mesmo no stub.
    --
    -- Endpoint de webhook para configurar no painel MP:
    --   http://SEU_IP_OU_DOMINIO:SEU_PORT/webhook/mp-pix
    pix = {
        enabled  = false,           -- true quando o MP estiver configurado
        provider = 'mercadopago',   -- 'mercadopago' | nil (stub)

        -- expiração da cobrança Pix em minutos (MP aceita até 1440 = 24h)
        expiresInMinutes = 30,

        -- pacotes de moedas exibidos na aba "Comprar Coins" do iPad.
        -- Personalize valores/bônus à vontade; priceBRL é o que o jogador paga.
        -- Adicione o tier para destaque visual (1=bronze, 2=prata, 3=ouro, 4=diamante).
        packages = {
            { id = 'pix_1k',  tier = 1, name = 'Pacote Bronze',   coins = 1000,  bonus = 0,    priceBRL = 10.00,  popular = false },
            { id = 'pix_3k',  tier = 2, name = 'Pacote Prata',    coins = 3000,  bonus = 300,  priceBRL = 25.00,  popular = true  },
            { id = 'pix_7k',  tier = 3, name = 'Pacote Ouro',     coins = 7000,  bonus = 1000, priceBRL = 50.00,  popular = false },
            { id = 'pix_15k', tier = 4, name = 'Pacote Diamante', coins = 15000, bonus = 3000, priceBRL = 100.00, popular = false },
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
