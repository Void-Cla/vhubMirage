-- config.lua — configuração central e MASTER do vhub_npcai
-- =============================================================================
-- Este é o ARQUIVO ÚNICO DE CONTROLE do sistema de NPCs conversacionais por voz.
-- Tudo o que o dono do servidor precisa ajustar mora aqui: mundo, NPCs, e QUAL
-- inteligência artificial responde (texto) e QUAL fala (voz).
--
--   • Provedor de RESPOSTA (LLM)  →  Gemini (padrão, barato/rápido) | OpenAI (futuro)
--   • Provedor de VOZ    (TTS)    →  SAPI local (padrão)            | OpenAI (futuro)
--   • Provedor de FALA   (STT)    →  Whisper local (sempre — não vai para nuvem)
--
-- Regra de ouro: cada NPC herda os PADRÕES globais de `cfg.ai` e pode
-- sobrescrever qualquer campo no seu próprio bloco `ai = { ... }`.
-- Segredos (chaves de API) NUNCA ficam aqui — vão em variável de ambiente
-- (GEMINI_API_KEY / OPENAI_API_KEY), lidas pelo sidecar Python (§15 do plano).
-- =============================================================================

VHubNpcAI          = VHubNpcAI or {}
VHubNpcAI.cfg      = {}
local cfg          = VHubNpcAI.cfg


-- ============================================================
-- GLOBAL
-- ============================================================

cfg.enabled = true   -- desliga o sistema inteiro (peds, proximidade, mundo) sem remover o resource
cfg.debug   = false  -- logs verbosos (intenção, stage, latência) — desligar em produção


-- ============================================================
-- SIDECAR PYTHON (motor de IA — loopback 127.0.0.1, nunca exposto)
-- ============================================================

cfg.sidecar = {
    host    = '127.0.0.1',
    port    = 7513,
    timeout = 45000,  -- ms: STT 15s + LLM 10s + TTS 10s + margem
}


-- ============================================================
-- INTELIGÊNCIA ARTIFICIAL — PROVEDORES (o coração do controle)
-- ------------------------------------------------------------
-- Troque `provider` para mudar de IA sem tocar em código. O sidecar carrega
-- a classe de provedor correspondente. Modelos abaixo são o DEFAULT global;
-- cada NPC pode sobrescrever no seu bloco `ai`.
-- ============================================================

cfg.ai = {

    -- ── RESPOSTA (LLM) — usado só quando o cache/intenção dá MISS ────────────
    llm = {
        provider = 'gemini',              -- 'gemini' | 'openai' | 'none' (none = só respostas de cache/config)

        -- Gemini: modelo mais básico e rápido (economia de token/latência)
        gemini = {
            model       = 'gemini-2.0-flash-lite',
            max_tokens  = 120,            -- resposta de NPC é curta (2 frases) — teto duplo: token + TTS curto
            temperature = 0.7,
        },

        -- OpenAI: pronto para o futuro (GPT). Ativar trocando provider='openai'
        openai = {
            model       = 'gpt-4o-mini',  -- mais barato/rápido da família; trocar quando quiser
            max_tokens  = 120,
            temperature = 0.7,
        },

        -- anti-abuso de custo (§15 do plano) — teto por personagem
        daily_cap_per_char   = 200,       -- máx. chamadas LLM por char por dia (0 = sem teto)
        per_min_cap_per_char = 6,         -- máx. chamadas LLM por char por minuto
    },

    -- ── VOZ (TTS) — sintetiza a resposta do NPC em áudio ────────────────────
    voice = {
        provider = 'sapi',                -- 'sapi' (local Windows) | 'openai' | 'none' (só legenda, sem áudio)

        -- SAPI local (subprocess isolado — já validado, 0 erros, sem custo de nuvem)
        sapi = {
            rate  = 160,                  -- palavras/min
            voice = '',                   -- nome da voz SAPI (vazio = padrão do Windows)
        },

        -- OpenAI TTS: pronto para o futuro (voz de alta qualidade)
        openai = {
            model  = 'gpt-4o-mini-tts',   -- modelo de voz OpenAI
            voice  = 'onyx',              -- onyx|alloy|echo|fable|nova|shimmer
            format = 'wav',               -- wav para stitch/concatenação sem re-encode
        },

        max_live_tts = 2,                 -- teto de gerações TTS ao vivo simultâneas (cache faz o volume)
    },

    -- ── FALA (STT) — transcreve o microfone do jogador (SEMPRE local) ───────
    stt = {
        provider    = 'faster-whisper',   -- 'faster-whisper' (int8, 3-5x) | 'whisper' (fallback)
        model       = 'base',             -- 'tiny' (rápido/impreciso) | 'base' (equilíbrio) | 'small' (preciso/lento)
        language    = 'pt',
        max_seconds = 5,                  -- teto de duração por fala (VAD corta silêncio) — mantém STT curto
    },
}


-- ============================================================
-- CONTROLE DE MUNDO (densidade de NPCs e veículos do GTA)
-- ------------------------------------------------------------
-- Cenário atual pedido pelo dono: MUNDO VAZIO, sem pedestres, sem carros
-- parados, apenas ALGUNS poucos veículos dirigindo, e somente os NPCs de IA
-- deste resource + carros de players.
--
-- Valores 0.0..1.0 (multiplicador da densidade nativa do GTA).
-- Presets de referência:
--   Vazio total ......... peds 0.0 · traffic 0.0 · parked 0.0
--   Vazio c/ trânsito ... peds 0.0 · traffic 0.10 · parked 0.0   ← ATUAL
--   Cidade viva ......... peds 1.0 · traffic 1.0  · parked 1.0
-- ============================================================

cfg.world = {
    enabled            = true,   -- ativa o controle de densidade (loop por frame)

    -- ── pedestres ──
    peds               = 0.0,    -- pedestres a pé (0.0 = nenhum do mundo)
    scenario_peds      = 0.0,    -- pedestres de cenário (vendedores, bancos, etc.)

    -- ── veículos ──
    traffic            = 0.10,   -- veículos DIRIGINDO (poucos = ~0.10; 0.0 = nenhum)
    random_traffic     = 0.10,   -- veículos aleatórios dirigindo
    parked             = 0.0,    -- veículos ESTACIONADOS aleatórios (0.0 = ruas limpas)

    -- ── elementos ambientais ──
    boats              = false,  -- barcos aleatórios
    trains             = false,  -- trens aleatórios
    garbage_trucks     = false,  -- caminhões de lixo

    -- ── IA de despacho (rádio policial, ambulância, guincho) ──
    emergency_dispatch = false,  -- false = sem viaturas/ambulâncias de IA aparecendo
    max_wanted         = 0,      -- teto de procurado (0 = sem estrelas/polícia de IA)

    -- ── orçamento do loop (estes nativos SÓ funcionam chamados por frame) ──
    loop_wait          = 0,      -- 0 = todo frame (necessário); só rodam quando enabled=true
}


-- ============================================================
-- MICROFONE (captura de voz — fala livre via opção de alvo)
-- ============================================================

cfg.talk_max_ms       = 5000  -- gravação máxima (ms) — alinhar com cfg.ai.stt.max_seconds
cfg.talk_audio_format = 'audio/webm'
cfg.talk_samplerate   = 16000 -- Hz (ideal para Whisper)


-- ============================================================
-- PROXIMIDADE E DISPLAY
-- ============================================================

cfg.hint_draw_dist = 12.0   -- metros — a partir daqui inicia head-tracking do NPC
cfg.los_required   = true   -- exige linha de visão para poder falar


-- ============================================================
-- INTEGRAÇÃO COM vhub_voicePMA (ducking da voz de proximidade/rádio)
-- ------------------------------------------------------------
-- Enquanto o jogador conversa com um NPC, abaixa a voz de outros players e
-- rádio para não competir com o áudio do NPC. Soft-dependência: se o voicePMA
-- não estiver rodando, o npcai continua funcionando sem ducking.
-- ============================================================

cfg.voice_integration = {
    enabled   = true,   -- liga a integração com o vhub_voicePMA
    duck_mode = 2,      -- modo de voz sugerido durante a conversa (1=sussurro,2=normal,3=grito)
}


-- ============================================================
-- ORÇAMENTOS DE THREAD (L-18)
-- ============================================================

cfg.budgets = {
    cold_wait = 1000,  -- thread fria de proximidade: 1 Hz (ms)
    warm_wait = 100,   -- thread quente (perto de NPC): 10 Hz (ms)
    ped_wait  = 500,   -- head-tracking / olhar do ped ativo: 2 Hz
}


-- ============================================================
-- RATES (ms entre ações por src — anti-spam, L-18/§4.6 do manual)
-- ============================================================

cfg.rates = {
    falar    = 3000,  -- cooldown entre falas ao NPC (ms)
    reservar = 1000,  -- cooldown de reserva de NPC (warm handoff) — throttla exports HSS
    push     = 500,   -- debounce da tecla push-to-talk
    memoria  = 5000,  -- escrita de memória nova
    audit    = 2000,  -- log de auditoria por interação
}


-- ============================================================
-- TETO DE FALANTES SIMULTÂNEOS (degradação graciosa acima disso)
-- ============================================================

cfg.max_talkers = 20  -- teto realista hoje ~5; alvo 20 via faster-whisper (§17 do plano)


-- ============================================================
-- MURMÚRIOS (tapa-buraco instantâneo enquanto o STT processa — ≤250 ms)
-- ------------------------------------------------------------
-- WAVs curtos ("hmm, deixa eu ver...") tocados LOCALMENTE no client no gatilho,
-- antes de qualquer geração. Para ATIVAR: coloque os .wav em `nui/audio/`,
-- liste-os em `files{}` do fxmanifest.lua (A-10) e referencie aqui. Ex.:
--   cfg.murmurs = { 'murmur_generic_1.wav', 'murmur_generic_2.wav' }
-- Vazio = sem murmúrio (o sistema funciona; só perde o "preenchimento" do silêncio).
-- ============================================================

-- murmúrios gerados pelo sidecar via SAPI no boot (nui/audio/); vazio até primeiro restart
cfg.murmurs = {
    'murmur_generic_1.wav',
    'murmur_generic_2.wav',
    'murmur_generic_3.wav',
    'murmur_generic_4.wav',
    'murmur_generic_5.wav',
}


-- ============================================================
-- NPCS — fichas de config
-- ------------------------------------------------------------
-- QUANTIDADE = quantos NPCs têm `enabled = true`. Desligue um NPC pondo
-- `enabled = false` (não spawna, some do minimapa, ignora proximidade).
--
-- Coordenadas em PRIMITIVOS `{x,y,z}` (L-19: config não usa vec3; o cliente
-- reconstrói o vetor no ponto de uso). `heading` é o giro do ped.
--
-- Cada NPC pode sobrescrever a IA global no bloco `ai`:
--   ai = { llm='openai', llm_model='gpt-4o-mini', voice='openai', voice_id='nova' }
-- Campos ausentes herdam de `cfg.ai`.
-- ============================================================

cfg.npcs = {

    -- ── JORJÃO — mecânico (oficina de corrida) ──────────────────────────────
    jorjao = {
        enabled   = true,
        id        = 'jorjao',
        nome      = 'Jorjão',
        profissao = 'mecanico',
        idioma    = 'pt',
        model     = 's_m_m_autoshop_01',
        coords    = { x = -350.5, y = -133.5, z = 38.0 },
        heading   = 0.0,
        raio      = 10.0,
        patrol    = true,   -- anda pelo perímetro entre tarefas
        scenario  = 'WORLD_HUMAN_CLIPBOARD',
        blip_sprite = 446,  -- chave de boca (mecânico)
        blip_color  = 47,   -- laranja
        blip_scale  = 0.8,
        talk_anim = { dict = 'mp_facial', name = 'mic_chatter' },
        idle_face = 'mood_happy_1',
        murmurs   = nil,  -- herda cfg.murmurs (global). Override por-NPC opcional.
        ai        ={},  -- herda cfg.ai (Gemini + SAPI). Ex. futuro: { voice='openai', voice_id='onyx' }
        target_options = {
            { name = 'ver_carro',       label = 'Pedir para ver o carro',       direct_text = 'pode dar uma olhada no meu carro' },
            { name = 'tuning_corrida',  label = 'Solicitar tuning para corrida', direct_text = 'quero fazer tuning para corrida' },
            { name = 'kit_nitro',       label = 'Perguntar sobre nitro',         direct_text = 'quero saber sobre kit de nitro' },
            { name = 'conversar',       label = 'Conversar livremente',          direct_text = nil },
        },
    },

    -- ── REBECA — médica (hospital) ──────────────────────────────────────────
    rebeca = {
        enabled   = true,
        id        = 'rebeca',
        nome      = 'Rebeca',
        profissao = 'medica',
        idioma    = 'pt',
        model     = 's_f_y_scrubs_01',
        coords    = { x = 295.2, y = -584.5, z = 43.26 },
        heading   = 90.0,
        raio      = 8.0,
        patrol    = true,
        scenario  = 'WORLD_HUMAN_STAND_MOBILE',
        blip_sprite = 61,   -- cruz de hospital
        blip_color  = 1,    -- vermelho
        blip_scale  = 0.8,
        talk_anim = { dict = 'mp_facial', name = 'mic_chatter' },
        idle_face = 'mood_normal_1',
        murmurs   = nil,  -- herda cfg.murmurs (global). Override por-NPC opcional.
        ai        ={},
        target_options = {
            { name = 'pedir_tratamento',  label = 'Pedir um tratamento',           direct_text = 'preciso de tratamento' },
            { name = 'relatar_ferimento', label = 'Relatar um ferimento',          direct_text = 'estou ferido' },
            { name = 'sobre_hospital',    label = 'Perguntar sobre o hospital',    direct_text = 'me fala sobre o hospital' },
            { name = 'conversar',         label = 'Conversar livremente',          direct_text = nil },
        },
    },

    -- ── CARVALHO — policial (delegacia) ─────────────────────────────────────
    carvalho = {
        enabled   = true,
        id        = 'carvalho',
        nome      = 'Carvalho',
        profissao = 'policial',
        idioma    = 'pt',
        model     = 's_m_y_cop_01',
        coords    = { x = 441.5, y = -982.0, z = 30.69 },
        heading   = 270.0,
        raio      = 10.0,
        patrol    = true,
        scenario  = 'WORLD_HUMAN_COP_IDLES',
        blip_sprite = 60,   -- distintivo
        blip_color  = 29,   -- azul policial
        blip_scale  = 0.8,
        talk_anim = { dict = 'mp_facial', name = 'mic_chatter' },
        idle_face = 'mood_angry_1',
        murmurs   = nil,  -- herda cfg.murmurs (global). Override por-NPC opcional.
        ai        ={},
        target_options = {
            { name = 'reportar_crime',  label = 'Reportar um crime',          direct_text = 'quero reportar um crime' },
            { name = 'falar_rachas',    label = 'Falar sobre rachas ilegais', direct_text = 'quero falar sobre rachas ilegais' },
            { name = 'verificar_ficha', label = 'Verificar minha ficha',      direct_text = 'tenho ficha criminal?' },
            { name = 'conversar',       label = 'Conversar livremente',       direct_text = nil },
        },
    },

    -- ── MARCUS — vendedor (mercado cinza / concessionária) ──────────────────
    -- Desligado por padrão (dono pediu foco em mecânico/médico/policial agora).
    marcus = {
        enabled   = false,
        id        = 'marcus',
        nome      = 'Marcus',
        profissao = 'vendedor',
        idioma    = 'pt',
        model     = 's_m_m_highsec_01',
        coords    = { x = -56.54, y = -1098.65, z = 26.42 },
        heading   = 180.0,
        raio      = 10.0,
        scenario  = 'WORLD_HUMAN_STAND_IMPATIENT',
        blip_sprite = 280,
        blip_color  = 3,
        blip_scale  = 0.8,
        talk_anim = { dict = 'mp_facial', name = 'mic_chatter' },
        idle_face = 'mood_happy_1',
        murmurs   = nil,  -- herda cfg.murmurs (global). Override por-NPC opcional.
        ai        ={},
        target_options = {
            { name = 'novidades',      label = 'Perguntar sobre novidades',  direct_text = 'tem alguma novidade?' },
            { name = 'fechar_negocio', label = 'Fechar um negócio',          direct_text = 'quero comprar alguma coisa' },
            { name = 'rumores',        label = 'Perguntar sobre corridas',   direct_text = 'tem algum rumor de corrida?' },
            { name = 'conversar',      label = 'Conversar livremente',       direct_text = nil },
        },
    },

}


-- ============================================================
-- RESOLVER DE IA — mescla defaults globais com override por NPC
-- ------------------------------------------------------------
-- Retorna a config de IA EFETIVA de um NPC (para enviar ao sidecar). Nunca
-- inclui segredos (chaves de API vivem no ambiente do sidecar).
-- ============================================================

-- resolve a config de IA efetiva de um npc_id (global + override do NPC)
function VHubNpcAI.resolveAI(npcId)
    local npc = cfg.npcs[npcId]
    local o   = (npc and npc.ai) or {}
    local g   = cfg.ai

    local llmProvider = o.llm or g.llm.provider
    local ttsProvider = o.voice or g.voice.provider
    local llmDefaults = g.llm[llmProvider] or {}
    local ttsDefaults = g.voice[ttsProvider] or {}

    return {
        llm = {
            provider    = llmProvider,
            model       = o.llm_model or llmDefaults.model,
            max_tokens  = o.llm_max_tokens or llmDefaults.max_tokens,
            temperature = o.llm_temperature or llmDefaults.temperature,
            -- tetos anti-custo (globais) — enforçados no sidecar antes de chamar o LLM
            daily_cap_per_char   = g.llm.daily_cap_per_char,
            per_min_cap_per_char = g.llm.per_min_cap_per_char,
        },
        voice = {
            provider = ttsProvider,
            model    = o.voice_model or ttsDefaults.model,
            voice    = o.voice_id or ttsDefaults.voice or ttsDefaults.name,
            rate     = o.voice_rate or ttsDefaults.rate,
            format   = ttsDefaults.format or 'wav',
        },
        stt = {
            provider    = g.stt.provider,
            model       = g.stt.model,
            language    = npc and npc.idioma or g.stt.language,
            max_seconds = g.stt.max_seconds,
        },
    }
end
