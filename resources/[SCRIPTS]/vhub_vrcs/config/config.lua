-- config/config.lua — tunables do vhub_vrcs (SEM regra de negocio; so parametros).

VRCS = VRCS or {}


-- ============================================================
-- CONFIG
-- ============================================================

VRCS.Cfg = {

    -- ── Identidade do formato ────────────────────────────────────────────────
    SCHEMA_VERSION = 'vhub_racha.vhr.v2',

    -- ── Gate de gravacao (TESTE) ─────────────────────────────────────────────
    -- Por padrao grava SOMENTE corridas ranqueadas (mode=='rankeada' E
    -- category=='ranqueada'), como pedido. Abra outras categorias mudando aqui.
    RECORD = {
        ranked_only      = true,
        require_mode     = 'rankeada',
        require_category = 'ranqueada',
    },

    -- ── Gravacao (CLIENT-DRIVEN, BUFFER LOCAL) ───────────────────────────────
    -- Cada client grava o proprio carro em RAM a 20Hz durante toda a corrida
    -- (zero rede nesse periodo — sem lag de upload na prova). Ao fim (recStop)
    -- o buffer e enviado de uma vez, fatiado e com ACK (ver bloco UPLOAD).
    -- O servidor NAO amostra — so recebe, valida e monta o .vhr no fechamento.
    SAMPLE_MS         = 50,                   -- 20 amostras/segundo (client) — max fluidez
    MAX_FRAMES        = 24000,                -- teto por jogador (~20 min a 20Hz) anti disco-flood
    MAX_REPLAY_BYTES  = 64 * 1024 * 1024,     -- teto do .vhr serializado (64 MB — frame v2 mais pesado)
    LIBRARY_LIMIT     = 50,                   -- replays listados no /replays

    -- ── Upload pos-corrida (sequencial, com ACK) ─────────────────────────────
    -- Disparado somente apos recStop. Sem flush periodico durante a corrida.
    SEND_CHUNK_FRAMES     = 400,              -- frames por bloco enviado ao servidor
    SEND_TIMEOUT_MS       = 5000,             -- timeout por bloco antes de retry
    SEND_MAX_RETRY        = 5,                -- tentativas por bloco antes de desistir
    SEND_TIMEOUT_TOTAL_MS = 60000,            -- teto do servidor esperando TODOS os participantes

    -- ── Persistencia ─────────────────────────────────────────────────────────
    REPLAY_DIR     = 'replays',               -- relativo ao resource (SaveResourceFile)

    -- ── Fronteira (N0-2 default-DENY) ────────────────────────────────────────
    -- Somente estes resources podem empurrar telemetria via os exports sensiveis.
    TRUSTED_RESOURCES = { ['vhub_racha'] = true },

    -- ── Player in-game (viewer client-side) ──────────────────────────────────
    -- Ao fim da corrida o servidor empurra o replay aos participantes; o cliente
    -- guarda em cache (KVP) e assiste in-game com painel minimalista.
    VIEWER = {
        COMMAND       = 'replays',   -- comando que abre o painel de replays
        CACHE_MAX     = 5,           -- replays guardados no cache do cliente (evict FIFO)
        DEFAULT_SPEED = 1.0,         -- velocidade inicial de reproducao
        CAM_DISTANCE  = 6.5,         -- distancia da camera de perseguicao (m)
        CAM_HEIGHT    = 2.8,         -- altura da camera (m)
        GHOST_ALPHA   = 255,         -- 255 = solido; <255 = carro fantasma translucido
        DRIVER        = true,        -- coloca o motorista (ped) no volante
        STEER_GAIN    = 0.6,         -- ganho do esterco derivado da rotacao (fallback)
        RPM_MAX_KMH   = 200,         -- velocidade de referencia p/ o RPM do audio do motor
        -- Rodas GIRANDO p/ frente/tras: o ghost ANDA de verdade sobre o solo
        -- (update_transform move por velocidade, colisao com o mundo ligada) e o
        -- MOTOR gira as rodas sozinho — nao ha native confiavel que role a roda
        -- num carro parado. CAM_SMOOTH/GHOST_ALPHA seguem abaixo.
        CAM_SMOOTH    = 0.18,        -- suavizacao da camera (0=trava no alvo, 1=sem suavizar)
    },

    -- ── Publicacao Discord (TESTE — Fase 1) ──────────────────────────────────
    -- ATENCAO: o design (vrcs.md, secao 9.4) define PerformHttpRequest no RENDERER
    -- isolado (F5), NUNCA no servidor principal. Este publisher e uma CONCESSAO DE
    -- TESTE: envia um embed de RESULTADO (texto, sem video) ao finalizar a corrida.
    -- Em producao migra para o renderer. Segredo SEMPRE via convar (nunca versionado):
    --   set vrcs_discord_webhook "https://discord.com/api/webhooks/...."
    DISCORD = {
        enabled        = true,                -- liga o publisher de teste
        webhook_convar = 'vrcs_discord_webhook',
        username       = 'VHUB Race Cinema',
        max_nick_len   = 24,
        embed_color    = 15255170,            -- areia dourada (232,198,130)
        -- Anexa o arquivo .vhr (replay em dados) ao post — contem o raceId e os
        -- char_ids de TODOS os participantes (identificacao). O .mp4 so e possivel
        -- no renderer (F2-F5, maquina com GPU + FFmpeg); ate la, vai o .vhr.
        attach_vhr       = true,
        max_attach_bytes = 8 * 1024 * 1024,   -- teto p/ anexo no webhook (Discord ~8 MB)
    },
}
