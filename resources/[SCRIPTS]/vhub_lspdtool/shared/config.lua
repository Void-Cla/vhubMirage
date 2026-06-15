-- config.lua — configuração estática do LSPD Tool (radar + BOLO + dispatch nativos vHub)
-- Edite ESTE arquivo para adaptar o sistema ao seu servidor sem tocar na lógica.

VHubLspd = VHubLspd or {}


-- ============================================================
-- CONFIG
-- ============================================================

VHubLspd.cfg = {

    -- Liga logs de depuração no console (mantenha false em produção).
    debug = false,


    -- ----- Autorização (server-authoritative, baseada em vhub_groups) -----
    police = {
        ownerBypass    = true,                -- uid == 1 (dono) sempre passa
        acePermission  = 'vhub.lspdtool',     -- ACE opcional (server.cfg: add_ace ...)
        permScan       = 'policia.consulta',  -- ler placa / receber alerta / radar automático
        permManageBolo = 'policia.investigar',-- criar/remover BOLO
        dutyExport     = nil,                 -- opcional { resource=, fn= } p/ confirmar "em serviço"
        cacheTtlMs     = 60000,               -- TTL do cache de permissão (fail-safe anti-stale)
    },


    -- ----- Validação da placa (dado vindo do cliente = hostil) -----
    plate = {
        charset = 'A-Z0-9 ',  -- classe de caracteres aceitos (Lua pattern char-class)
        minLen  = 1,
        maxLen  = 8,
    },


    -- ----- Anti-flood do scan -----
    rate = {
        minIntervalMs = 800,  -- intervalo mínimo entre scans aceitos por policial
        maxPerMinute  = 40,   -- teto de scans aceitos por policial/minuto
    },

    -- Dedup global por placa: evita que vários policiais alertem o mesmo BOLO ao mesmo tempo.
    dedupTtlMs = 15000,


    -- ----- Radar NATIVO (sem escrow) -----
    -- Overlay próprio: detecta veículos à frente/atrás por raycast (capsule), lê velocidade
    -- e placa LOCALMENTE (UI), e encaminha a placa ao servidor (pipeline seguro = BOLO/auditoria).
    -- A NUI é passiva (sem NuiFocus). O servidor é a ÚNICA autoridade de "quem é policial".
    radar = {
        autoOpen    = true,              -- abre ao entrar como MOTORISTA (pede autorização ao servidor)
        reopenAfterLeave = true,         -- re-arma o auto-open ao sair e reentrar num veículo
        anyVehicle  = true,              -- TESTE: abre em QUALQUER veículo/heli (não só classe 18).
                                         -- false = produção (só viatura). Servidor valida policial.
        toggleKey   = 'X',               -- liga/desliga o radar
        lockKey     = 'K',               -- trava/destrava as leituras (congela frente+trás)
        policeClass = 18,                -- classe de veículo policial (GTA: 18) quando anyVehicle=false

        -- detecção por raycast LOS síncrono (unidades de jogo ~ metros)
        frontRange = 70.0,               -- alcance do feixe frontal
        rearRange  = 70.0,               -- alcance do feixe traseiro
        skipAhead  = 3.0,                -- ignora os primeiros N (não pega o próprio capô)

        -- cadência (thread adaptativa — só custa quando o radar está ON e o player dirige)
        updateMs = 200,                  -- atualização do alvo com radar ON
        idleMs   = 700,                  -- checagem de entrada em veículo com radar OFF

        unit         = 'KMH',            -- rótulo de unidade exibido
        autoBoloScan = true,             -- encaminha placa nova lida ao pipeline (checa BOLO)
    },


    -- ----- Heli-câmera NATIVA (FASE B) -----
    -- Câmera scriptada presa ao heli; lock por raycast lê placa → pipeline (kind='air').
    -- Compartilha a tecla X com o radar por contexto (radar = solo; helicam = dentro de heli).
    helicam = {
        toggleKey      = 'X',                        -- liga/desliga (em heli)
        visionKey      = 'TAB',                      -- cicla visão (normal/nightvision/thermal)
        spotKey        = 'G',                        -- holofote
        lockKey        = 'SPACE',                    -- trava/destrava o alvo
        passengerOnly  = false,                      -- false = qualquer ocupante opera; true = só passageiro
        defaultOffset  = vector3(0.0, 2.5, -1.0),    -- offset FLIR padrão (frente/baixo do heli)
        fov            = { min = 5.0, max = 70.0, default = 55.0, step = 4.0 },  -- zoom (FOV menor = mais perto)
        lookSpeed      = 4.0,                         -- sensibilidade da rotação da câmera
        pitchLimit     = { up = 20.0, down = -89.0 },-- limites verticais da câmera
        targetMaxReach = 800.0,                       -- alcance máximo do lock (unidades)
        updateHudMs    = 150,                         -- cadência máxima do HUD
        autoAirScan    = true,                        -- ao travar veículo, encaminha placa (kind='air')
        spotlight      = {
            color = { 255, 255, 255 },
            distance = 600.0, brightness = 8.0, radius = 12.0, falloff = 200.0,
        },
    },


    -- ----- BOLO nativo vHub (fonte de verdade própria) -----
    bolo = {
        reasonMaxLen  = 120,    -- tamanho máximo do motivo
        maxActive     = 50,     -- teto de BOLOs ativos simultâneos
        cmdCooldownMs = 10000,  -- intervalo mínimo entre comandos /bolo por policial
        defaultLevel  = 1,
        levels = {              -- rótulos de severidade (PT-BR)
            [1] = 'Atencao',
            [2] = 'Perigoso',
            [3] = 'Alto risco',
        },
    },


    -- ----- Alerta de BOLO (entregue ao policial em serviço) -----
    alert = {
        blipSprite     = 161,    -- sprite do blip (alvo)
        blipColour     = 1,      -- vermelho
        blipScale      = 1.2,
        blipDurationMs = 30000,  -- tempo que o blip permanece no mapa
        maxBlips       = 8,      -- teto de blips simultâneos no cliente
        sound          = { name = 'TIMER_STOP', set = 'HUD_MINI_GAME_SOUNDSET' },

        -- Monta o texto da notificação exibida ao policial. ctx = { plate, reason, level, kind }
        buildMessage = function(ctx)
            local aerea = ctx.kind == 'air'
            return ('~r~BOLO~s~ — Placa ~y~%s~s~ (%s)%s'):format(
                tostring(ctx.plate),
                tostring(ctx.reason or 'sinalizada'),
                aerea and ' ~b~[aereo]' or '')
        end,
    },


    -- ----- MDT / Central de Despacho (FASE C) -----
    mdt = {
        -- F7 colide com painéis de outros resources (groups/racha) e F6 com o admin; F10 é livre.
        -- Rebindável pelo jogador em Configurações > Teclas. O servidor valida policial ao abrir.
        toggleKey = 'F10',
        scanLimit = 25,     -- nº de scans recentes exibidos no painel
    },


    -- ----- App "Central LSPD" no iPad (vhub_ipad) -----
    -- O painel policial roda DENTRO da tela do iPad (App SDK relay, modelo remote).
    -- Login por char_id + senha; a autoridade de "quem é policial" continua server-side.
    ipad = {
        appId        = 'lspd',           -- id do app no catálogo do iPad (== módulo NUI)
        label        = 'Central LSPD',   -- nome exibido na home/Loja
        icon         = 'lspd.png',       -- nome do ícone no CDN de assets do iPad
        category     = 'trabalho',
        defaultPass  = '123',            -- senha inicial (must_change=1 força a troca)
        scanLimit    = 20,               -- scans recentes mostrados no painel
        actionCdMs   = 1500,             -- cooldown por ação mutadora (prender/apreender)
    },


    -- ----- Procurados (pessoas) — mandado por char_id (distinto do BOLO de placa) -----
    wanted = {
        reasonMaxLen = 120,
        nameMaxLen   = 64,
        maxActive    = 100,    -- teto de procurados ativos
        defaultLevel = 1,
        levels = {             -- rótulos de severidade (PT-BR)
            [1] = 'Procurado',
            [2] = 'Armado/perigoso',
            [3] = 'Prioridade máxima',
        },
    },


    -- ----- Prisão / detenção (RP arrest) — server-authoritative -----
    -- "Prender mais próximo": o SERVER acha o jogador mais próximo do policial,
    -- valida e aplica estado de detido (algema + controles travados) no cliente.
    arrest = {
        rangeM       = 3.0,    -- alcance máximo para prender/soltar (metros)
        dict         = 'mp_arresting',  -- animação de algemado
        anim         = 'idle',
    },


    -- ----- Apreensão de veículo (reusa o pátio do vhub_garage) -----
    seize = {
        garageResource = 'vhub_garage',  -- dono do pátio/impound
        feeExtra       = 0,              -- taxa extra somada à apreensão
        defaultReason  = 'Apreensão policial',
    },


    -- ----- Log próprio de scans (auditoria + export getRecentScans) -----
    log = {
        enabled     = true,   -- grava em vhub_lspd_scans
        onlyFlagged = false,  -- true = registra apenas placas com BOLO
    },


    -- Resources autorizados a chamar exports mutadores deste resource.
    trusted = {
        ['vhub']       = true,
        ['vhub_admin'] = true,
    },
}


return VHubLspd.cfg
