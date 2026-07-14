-- shared/config.lua — configuração estática do vhub_df (gateway de pagamento Pix)
--
-- CREDENCIAIS: NUNCA hardcode aqui. Use config/local.cfg (gitignored):
--   set df_mp_key            "APP_USR-xxxx"   ← Access Token
--   set df_mp_webhook_secret "xxxxxxxx"       ← assinatura secreta do webhook
--
-- ATIVAÇÃO: exige df_mp_key no config/local.cfg. Sem o Access Token configurado,
-- criar cobrança retorna erro imediato mesmo com enabled=true.

VHubDF = VHubDF or {}
VHubDF.cfg = {

    -- habilita o gateway (ligado 2026-07-13 — credenciais presentes no local.cfg)
    enabled = true,

    -- modo de depuração — false em produção (R10)
    debug = false,


    -- ============================================================
    -- MERCADOPAGO
    -- ============================================================

    mp = {
        -- base da API (nunca alterar sem ADR)
        baseUrl = 'https://api.mercadopago.com',

        -- timeout da requisição HTTP (ms) — MP responde Pix em < 3s; 15s dá margem
        timeoutMs = 15000,

        -- expiração da cobrança Pix em minutos (MP aceita 1..1440)
        expiresInMinutes = 30,

        -- e-mail fictício obrigatório pela API do MP (nunca usar e-mail real do jogador).
        -- example.com é TLD reservado (RFC 2606): formato válido, nunca entregável.
        payerEmailDomain = 'example.com',
    },


    -- ============================================================
    -- POLLING — verificação periódica de pagamentos pendentes
    -- ============================================================

    polling = {
        -- intervalo do loop de verificação (ms) — 5s é seguro p/ rate limit do MP
        intervalMs = 5000,

        -- número máximo de consultas antes de cancelar uma transação por timeout
        -- (maxChecks * intervalMs) deve ser > expiresInMinutes * 60 * 1000
        maxChecks = 400,

        -- yield a cada N pedidos num ciclo para não bloquear o tick (L-18)
        batchYield = 5,
    },


    -- ============================================================
    -- SEGURANÇA / RATE LIMIT (L-18 — O(1) por src)
    -- ============================================================

    rates = {
        createPayment = 10000,  -- 10s entre criações de cobrança pelo mesmo jogador
        checkStatus   =  3000,  -- 3s entre consultas de status (client NUI)
        cancelPayment =  5000,  -- 5s entre cancelamentos
    },

    -- valor mínimo e máximo aceito por cobrança (BRL, centavos inteiros)
    minAmountBRL = 1.00,
    maxAmountBRL = 10000.00,

    -- tamanho máximo do campo metadata enviado pelo consumidor (bytes, após json.encode)
    maxMetadataBytes = 512,

    -- limite de cobranças pendentes simultâneas por jogador (anti-spam)
    maxPendingPerPlayer = 3,


    -- ============================================================
    -- WEBHOOK
    -- ============================================================

    webhook = {
        -- path registrado no SetHttpHandler (também configurado no painel do MP)
        path = '/df/webhook/pix',
    },


    -- ============================================================
    -- NOTIFICAÇÕES Discord (auditoria) — vazio = desligado
    -- ============================================================

    discord = {
        webhookUrl  = '',        -- lido de convar df_discord_webhook (nunca versionar URL)
        username    = 'vHub Pagamentos',
        avatarUrl   = 'https://raw.githubusercontent.com/Void-Cla/vhub-assets/main/logo.png',
        colorOk     = 3066993,   -- verde
        colorFail   = 15158332,  -- vermelho
    },
}
