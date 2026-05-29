-- shared/events.lua — registro unico de nomes de eventos do vhub_racha.
--
-- ESTE arquivo e a fonte UNICA de verdade dos nomes de eventos. Toda string
-- de evento em qualquer modulo client/server deve referenciar VHubRachaE.X —
-- jamais hardcoded.
--
-- Mover o nome aqui = mover em todos os modulos. Renomear aqui sem refletir
-- nos consumers QUEBRA o contrato pois o nome de evento e API publica.
--
-- Veredito do guardiao de contrato: ADICIONAR campo OK; RENOMEAR/REMOVER nao.


VHubRachaE = {


    -- ============================================================
    -- BOOT / HANDSHAKE
    -- ============================================================

    REQUEST_INIT_DONE = 'vhub_racha:request_initDone',  -- client → server: pede re-emissao do vHub:initDone


    -- ============================================================
    -- NUI (open / refresh / queries de painel)
    -- ============================================================

    NUI_OPEN          = 'vhub_racha:nui:open',
    NUI_OPENED        = 'vhub_racha:nui:opened',
    NUI_REFRESH       = 'vhub_racha:nui:refresh',
    NUI_RESULT        = 'vhub_racha:nui:result',
    NUI_RANKING       = 'vhub_racha:nui:ranking',
    NUI_RANKING_DATA  = 'vhub_racha:nui:ranking_data',
    NUI_HISTORY       = 'vhub_racha:nui:history',
    NUI_HISTORY_DATA  = 'vhub_racha:nui:history_data',
    NUI_RESULTS       = 'vhub_racha:nui:results',
    NUI_RESULTS_DATA  = 'vhub_racha:nui:results_data',


    -- ============================================================
    -- LOBBY (create / join / leave / confirm / start)
    -- ============================================================

    LOBBY_CREATE      = 'vhub_racha:lobby:create',
    LOBBY_JOIN        = 'vhub_racha:lobby:join',
    LOBBY_LEAVE       = 'vhub_racha:lobby:leave',
    LOBBY_CANCEL      = 'vhub_racha:lobby:cancel',
    LOBBY_PENDING     = 'vhub_racha:lobby:pending',     -- server → client: jogador entrou no lobby, deve confirmar no totem
    LOBBY_CONFIRM     = 'vhub_racha:lobby:confirm',     -- client → server: confirma presenca (precisa estar na ready zone)
    LOBBY_CONFIRMED   = 'vhub_racha:lobby:confirmed',   -- server → client: confirmacao aceita
    LOBBY_FORCE_START = 'vhub_racha:lobby:force_start', -- client → server: host forca start (apenas confirmados correm)


    -- ============================================================
    -- RACE (warmup → racing → finish)
    -- ============================================================

    RACE_PREPARE      = 'vhub_racha:race:prepare',
    RACE_START        = 'vhub_racha:race:start',
    RACE_CHECKPOINT   = 'vhub_racha:race:checkpoint',
    RACE_TICK         = 'vhub_racha:race:tick',
    RACE_FINISH       = 'vhub_racha:race:finish',
    RACE_ABORT        = 'vhub_racha:race:abort',
    RACE_POLICE       = 'vhub_racha:race:police_alert',


    -- ============================================================
    -- EDITOR (criacao visual de pistas custom)
    -- ============================================================

    EDITOR_OPEN       = 'vhub_racha:editor:open',
    EDITOR_OPENED     = 'vhub_racha:editor:opened',
    EDITOR_PHASE      = 'vhub_racha:editor:phase',
    EDITOR_ADD_GRID   = 'vhub_racha:editor:add_grid',
    EDITOR_ADD_CP     = 'vhub_racha:editor:add_cp',
    EDITOR_UNDO       = 'vhub_racha:editor:undo',
    EDITOR_NEXT       = 'vhub_racha:editor:next',
    EDITOR_SAVE       = 'vhub_racha:editor:save',
    EDITOR_DISCARD    = 'vhub_racha:editor:discard',
    EDITOR_DRAFT      = 'vhub_racha:editor:draft',      -- server → client: snapshot do draft


    -- ============================================================
    -- NOTIFICATIONS
    -- ============================================================

    NOTIFY            = 'vhub_racha:notify',


}
