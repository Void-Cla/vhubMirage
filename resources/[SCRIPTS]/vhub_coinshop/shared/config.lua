-- shared/config.lua — configuração estática do vhub_coinshop (PT-BR, server+client)

VHubCoin = VHubCoin or {}
VHubCoin.cfg = {


    -- ============================================================
    -- GERAL
    -- ============================================================

    -- habilita logs de depuração no console do servidor (produção: false)
    debug = false,

    -- comando e tecla para abrir/fechar a loja
    command        = 'coinshop',
    key            = 'F5',
    keyDescription = 'Abrir Loja de Moedas',


    -- ============================================================
    -- TEST-DRIVE
    -- ============================================================

    -- duração do test-drive em segundos
    testDriveDuration = 10,

    -- distância à frente do ped onde o veículo de test-drive spawna
    testDriveSpawnDistance = 5.0,

    -- local de test-drive (vec4: x,y,z,heading) — apenas spawn de veículo usa w (L-19)
    testDriveLocation = vec4(-1639.68, -2647.89, 13.82, 330.0),

    -- prefixo da placa efêmera do test-drive (veículo não-persistente, marcado mission)
    testDrivePlatePrefix = 'CST',


    -- ============================================================
    -- REDE -- RATE LIMIT (orçamento L-18, throttle O(1) por src+chave)
    -- ============================================================

    -- intervalos mínimos (ms) entre ações do mesmo jogador — evento novo nasce com rate (§4.6)
    rates = {
        openShop      = 1000,   -- abrir a loja
        purchaseItem  = 500,    -- comprar item
        purchaseDeal  = 500,    -- comprar oferta
        redeemCode    = 2000,   -- resgatar código (anti-brute-force)
        testDrive     = 5000,   -- iniciar test-drive
        adminAction   = 300,    -- qualquer ação admin (CRUD, give/set)
        getOnlineList = 5000,   -- refresh da lista de players online
        getCoins      = 1000,   -- leitura de saldo (folgado; anti-spam de dispatch)
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
    -- IDENTIDADE VISUAL DA NUI (passada ao app no `open`)
    -- ============================================================

    -- logo exibido no cabeçalho (URL raw GitHub do asset vHub)
    logo = 'https://raw.githubusercontent.com/Void-Cla/vhub-assets/main/logo.png',

    -- hora UTC (0-23) em que ofertas diárias são consideradas "resetadas" para exibição
    dealResetHour = 0,
}

return VHubCoin.cfg
