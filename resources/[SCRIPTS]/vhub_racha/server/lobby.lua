---@diagnostic disable: undefined-global, lowercase-global

-- server/lobby.lua — maquina de estados do lobby (create → pending → warmup).
--
-- FLUXO UNICO (uma fonte de verdade, sem ramificacao por kind):
--
--   1) L.create            → instancia em 'lobby' (visivel no painel)
--   2) L.join              → jogador entra, paga fee, instancia vira 'pending'
--   3) L.confirm_presence  → jogador no totem aperta [E], precisa estar na ready-zone
--   4) Todos confirmados (ou host force_start) → L.start → 'warmup' (countdown)
--   5) Apos countdown → runtime.begin_racing → 'racing'
--
-- Modos:
--   • rankeada  → fee + ranking + min_players configurado
--   • treino    → fee=0, min_players=1, SEM recompensa (fiel ao rank, sem premio)
--   • freerun   → como treino, sem laps
--   • timeattack → fee=0, min_players=1, COM recompensa por tempo
--
-- TODOS os modos passam pelo totem. Nenhum modo teleporta sem confirmacao.
-- Concerns geometricos (slot/ready-zone) moram em server/grid.lua.
-- Cobrancas/recompensas moram em server/rewards.lua.


VHubRachaLobby = {}
local L   = VHubRachaLobby
local Cfg = VHubRachaCfg
local U   = VHubRachaUtils
local ST  = VHubRachaState
local E   = VHubRachaE
local RW  = VHubRachaRewards
local GR  = VHubRachaGrid


-- ============================================================
-- HELPERS
-- ============================================================

local function ms() return GetGameTimer() end


-- Retorna user da sessao ativa. Zero retry, zero Wait.
-- Fonte unica: VHubRachaSessions (cache via vHub:characterLoad).
local function user_of(src)
    return VHubRachaSessions and VHubRachaSessions.get(src) or nil
end


local function notify(src, msg, kind)
    if src and src > 0 then
        TriggerClientEvent(E.NOTIFY, src, msg, kind or 'info')
    end
end


-- Resolve nome de exibicao do player via vhub_identity (com fallback)
local function nick_of(src, char_id)
    local nick = 'char_' .. tostring(char_id or '?')
    pcall(function()
        if exports.vhub_identity then
            local full = exports.vhub_identity:getFullName(src)
            if type(full) == 'string' and full ~= '' then nick = full end
        end
    end)
    return nick
end


-- Sincroniza estado do lobby para todos os players da instancia via State Bag
-- (HUD/NUI le e renderiza contadores em tempo real)
local function broadcast_lobby_state(inst)
    for src, p in pairs(inst.players or {}) do
        Player(src).state:set('vhub_racha', {
            inst_id          = inst.id,
            track_id         = inst.track_id,
            kind             = inst.kind,
            mode             = inst.mode,
            state            = inst.state,
            confirmed        = p.confirmed == true,
            grid_slot        = p.grid_slot,
            players_total    = ST.count_players(inst),
            pending_deadline = inst.pending_deadline or 0,
            ready_zone       = inst.ready_zone,
            starts_at        = inst.starts_at or 0,
        }, true)
    end
end


-- Conta confirmados — usado em start() e em confirm_presence()
local function count_confirmed(inst)
    local n = 0
    for _, p in pairs(inst.players or {}) do
        if p.confirmed == true then n = n + 1 end
    end
    inst.confirmed_count = n
    return n
end


-- Detecta modo a partir do payload e kind da track
-- treino e freerun colapsam para 'treino' (sem premio)
local function resolve_mode(payload, track)
    if track.kind == 'freerun' then return 'treino' end
    return (payload and payload.mode == 'treino') and 'treino' or 'rankeada'
end


-- Calcula entry_fee respeitando modo (treino e timeattack = sem fee)
local function resolve_fee(payload, track, mode)
    if mode == 'treino' or track.kind == 'timeattack' then return 0 end
    return U.clamp_int((payload and payload.entry_fee) or track.default_fee or 0,
                       0, Cfg.MAX_ENTRY_FEE)
end


-- ============================================================
-- CREATE — abre uma instancia de lobby
-- ============================================================

-- Cria nova instancia. Retorna { inst_id } em sucesso.
-- TODOS os modos seguem o mesmo fluxo: lobby → pending → totem → start.
function L.create(src, payload)
    local user = user_of(src)
    if not user then return false, 'sem_sessao' end

    local track_id = U.sanitize_id((payload and payload.track_id) or '')
    local track = ST.track(track_id)
    if not track then return false, 'pista_inexistente' end

    local mode      = resolve_mode(payload, track)
    local entry_fee = resolve_fee(payload, track, mode)
    local laps      = U.clamp_int((payload and payload.laps) or track.laps or 1, 1, 10)
    if track.kind == 'freerun' then laps = 0 end

    local cp_total    = #(track.checkpoints or {}) * math.max(1, laps)
    local min_players = U.clamp_int((payload and payload.min_players) or track.min_players or 1, 1, 12)
    local max_players = U.clamp_int((payload and payload.max_players) or track.max_players or 8, 1, 12)
    if mode == 'treino' or track.kind == 'timeattack' then min_players = 1 end

    local inst = {
        id            = U.short_id(),
        track_id      = track.id,
        label         = track.label,
        district      = track.district,
        kind          = track.kind,
        mode          = mode,
        illegal       = track.illegal == true,
        alerts_police = track.alerts_police == true,
        laps          = laps,
        cp_total      = cp_total,
        min_players   = min_players,
        max_players   = max_players,
        vehicle_class = track.vehicle_class or 'car',
        creator_char  = user.char_id,
        entry_fee     = entry_fee,
        pot_total     = 0,
        state         = 'lobby',
        created_ms    = ms(),
        starts_at     = 0,
        started_at    = 0,
        players       = {},
        grid_used     = {},
        confirmed_count = 0,
        pending_deadline = 0,
        finish_grace_started_at = 0,
        ready_zone    = GR.compute_ready_zone(track),
    }

    ST.put_instance(inst)
    ST.metrics.instances_created = ST.metrics.instances_created + 1

    -- Auto-join do criador (treino, timeattack ou ranqueado — todos passam aqui)
    local ok, data = L.join(src, inst.id)
    if not ok then
        ST.remove_instance(inst.id)
        return false, data
    end

    return true, { inst_id = inst.id }
end


-- ============================================================
-- JOIN — entrar em lobby existente
-- ============================================================

-- Adiciona jogador a instancia. Cobra fee, aloca grid slot, e transiciona
-- 'lobby' → 'pending' na primeira entrada (inicia deadline de confirmacao).
function L.join(src, inst_id)
    local user = user_of(src)
    if not user then return false, 'sem_sessao' end

    local inst = ST.instance(inst_id)
    if not inst then return false, 'instancia_inexistente' end

    if inst.state ~= 'lobby' and inst.state ~= 'pending' then return false, 'lobby_fechado' end
    if inst.players[src] then return false, 'ja_no_lobby' end
    if ST.instance_by_src(src) then return false, 'ja_em_outra_corrida' end
    if ST.count_players(inst) >= (inst.max_players or 8) then return false, 'lobby_cheio' end

    -- Cobranca atomica (Rewards faz o trabalho com vhub_money)
    if (inst.entry_fee or 0) > 0 then
        local paid = RW.charge_entry(src, inst.entry_fee, 'racha_join')
        if not paid then return false, 'saldo_insuficiente' end
    end

    -- Aloca slot de grid (geometria isolada em Grid)
    local grid_slot = GR.alloc_slot(inst)
    if not grid_slot then
        -- Refund se cobrou e nao conseguiu spot (caso raro de race)
        if (inst.entry_fee or 0) > 0 then RW.refund(src, inst.entry_fee, 'racha_no_slot') end
        return false, 'sem_grid'
    end
    inst.grid_used[grid_slot] = src

    inst.players[src] = {
        src         = src,
        char_id     = user.char_id,
        nick        = nick_of(src, user.char_id),
        grid_slot   = grid_slot,
        confirmed   = false,
        state       = 'lobby',
        cp_done     = 0,
        lap         = 0,
        drift_score = 0,
        top_speed   = 0,
        started_ms  = 0,
        last_cp_ms  = 0,
        finished    = false,
        warns       = 0,
    }

    inst.pot_total = (inst.pot_total or 0) + (inst.entry_fee or 0)
    ST.bind_src(src, inst.id)

    -- Transicao lobby → pending na primeira entrada
    if inst.state == 'lobby' then
        inst.state = 'pending'
        inst.pending_deadline = ms() + (Cfg.PENDING_TTL_MS or 300000)
        SetTimeout((Cfg.PENDING_TTL_MS or 300000) + 200, function()
            local i = ST.instance(inst.id)
            if not i or i.state ~= 'pending' then return end
            L._handle_pending_deadline(i)
        end)
    end

    broadcast_lobby_state(inst)

    -- Envia ao cliente o sinal de "va ao totem confirmar"
    TriggerClientEvent(E.LOBBY_PENDING, src, {
        inst_id          = inst.id,
        ready_zone       = inst.ready_zone,
        pending_deadline = inst.pending_deadline,
        mode             = inst.mode,
        track_label      = inst.label,
    })

    return true, { inst_id = inst.id, grid_slot = grid_slot }
end


-- ============================================================
-- LEAVE / CANCEL
-- ============================================================

-- Jogador sai do lobby. Devolve fee se ainda nao começou.
-- Se host saiu, cancela toda a instancia.
function L.leave(src, inst_id)
    local inst = ST.instance(inst_id)
    if not inst then return false end

    local player = inst.players[src]
    if not player then return false end

    -- Refund se ainda em lobby/pending
    local can_refund = (inst.state == 'lobby' or inst.state == 'pending') and (inst.entry_fee or 0) > 0
    if can_refund then
        RW.refund(src, inst.entry_fee, 'racha_leave')
        inst.pot_total = math.max(0, (inst.pot_total or 0) - inst.entry_fee)
    end

    inst.players[src] = nil
    GR.free_slot(inst, player.grid_slot)
    ST.unbind_src(src)
    Player(src).state:set('vhub_racha', nil, true)

    -- Host saiu antes da corrida → cancela tudo
    local host_left_before_start =
        (inst.state == 'lobby' or inst.state == 'pending')
        and player.char_id == inst.creator_char

    if host_left_before_start then
        return L.cancel(inst.id, 'host_left')
    end

    count_confirmed(inst)

    if ST.count_players(inst) == 0 then
        ST.remove_instance(inst.id)
    else
        broadcast_lobby_state(inst)
    end

    return true
end


-- Cancela toda a instancia (lobby ou pending). Refund a todos os players.
function L.cancel(inst_id, reason)
    local inst = ST.instance(inst_id)
    if not inst then return false end
    if inst.state ~= 'lobby' and inst.state ~= 'pending' then return false, 'nao_e_lobby' end

    for src, _ in pairs(inst.players) do
        if (inst.entry_fee or 0) > 0 then
            RW.refund(src, inst.entry_fee, 'racha_cancel')
        end
        notify(src, ('Lobby cancelado (%s).'):format(reason or 'cancelado'), 'error')
        Player(src).state:set('vhub_racha', nil, true)
        ST.unbind_src(src)
    end

    ST.remove_instance(inst.id)
    return true
end


-- ============================================================
-- CONFIRM PRESENCE — totem aperta [E]
-- ============================================================

-- Player confirma que esta na ready-zone (verificado pelo servidor com
-- GetEntityCoords). Quando todos confirmam, dispara L.start automaticamente.
--
-- Parametro `force` e EXCLUSIVO para uso administrativo de emergencia.
-- Producao: sempre `false`. Treino e timeattack tambem passam pela ready-zone.
function L.confirm_presence(src, inst_id, force)
    local inst = ST.instance(inst_id)
    if not inst then return false end
    if inst.state ~= 'pending' then return false, 'estado_invalido' end

    local player = inst.players[src]
    if not player then return false, 'fora_do_lobby' end
    if player.confirmed then return true end

    if not force and not GR.in_ready_zone(src, inst.ready_zone) then
        return false, 'fora_da_ready_zone'
    end

    player.confirmed = true
    count_confirmed(inst)
    broadcast_lobby_state(inst)

    TriggerClientEvent(E.LOBBY_CONFIRMED, src, { inst_id = inst.id })
    notify(src, 'Presenca confirmada.', 'success')

    -- Todos no lobby confirmaram E temos o minimo? → inicia
    local all_confirmed = inst.confirmed_count >= ST.count_players(inst)
    local has_minimum   = inst.confirmed_count >= (inst.min_players or 1)

    if all_confirmed and has_minimum then
        L.start(inst.id, false)
    end

    return true
end


-- Deadline da pendencia expirou. Remove quem nao confirmou (com refund);
-- se restou o minimo confirmado, inicia. Senao, cancela.
function L._handle_pending_deadline(inst)
    if not inst or inst.state ~= 'pending' then return end

    local kicked = {}
    for src, p in pairs(inst.players) do
        if not p.confirmed then kicked[#kicked + 1] = src end
    end

    for _, src in ipairs(kicked) do
        notify(src, 'Voce nao confirmou a tempo — saiu do lobby.', 'error')
        L.leave(src, inst.id)
    end

    if ST.count_players(inst) >= (inst.min_players or 1) then
        L.start(inst.id, false)
    else
        L.cancel(inst.id, 'sem_presenca_minima')
    end
end


-- ============================================================
-- START — transicao pending → warmup (countdown na grid)
-- ============================================================

-- Inicia warmup. Apenas players confirmados sao mantidos; nao-confirmados
-- sao removidos silenciosamente (sem refund — ficou injusto pois passaram
-- do deadline). Treino auto-confirma todos pois eh solo e ja passou pelo
-- totem na entrada — entao o auto-confirm aqui e idempotente.
function L.start(inst_id, solo)
    local inst = ST.instance(inst_id)
    if not inst then return false, 'inst_inexistente' end
    if inst.state ~= 'pending' and inst.state ~= 'lobby' then return false, 'estado_invalido' end

    local n_conf = count_confirmed(inst)
    local needs_min = (not solo) and inst.mode ~= 'treino'
    if needs_min and n_conf < (inst.min_players or 1) then
        return false, 'jogadores_insuficientes'
    end

    -- Remove nao-confirmados (sem refund — passaram do deadline)
    if not solo and inst.mode ~= 'treino' then
        local kicked = {}
        for src, p in pairs(inst.players) do
            if not p.confirmed then kicked[#kicked + 1] = src end
        end
        for _, src in ipairs(kicked) do L.leave(src, inst.id) end
    end

    inst.state      = 'warmup'
    inst.starts_at  = ms() + (Cfg.COUNTDOWN_MS or 7000)
    inst.started_at = os.time()

    -- Envia RACE_PREPARE com spawn position de grid para cada player
    local track = ST.track(inst.track_id)
    for src, p in pairs(inst.players) do
        TriggerClientEvent(E.RACE_PREPARE, src, {
            inst_id       = inst.id,
            track         = track,
            laps          = inst.laps,
            mode          = inst.mode,
            grid_pos      = GR.spawn_for(track, p.grid_slot),
            starts_at     = inst.starts_at,
            countdown     = Cfg.COUNTDOWN_MS or 7000,
            players_total = ST.count_players(inst),
        })
    end

    -- Agenda transicao warmup → racing
    SetTimeout(Cfg.COUNTDOWN_MS or 7000, function()
        local i = ST.instance(inst_id)
        if not i or i.state ~= 'warmup' then return end
        if VHubRachaRuntime and VHubRachaRuntime.begin_racing then
            VHubRachaRuntime.begin_racing(i)
        end
    end)

    -- Alerta policia se corrida ilegal
    if inst.alerts_police and Cfg.POLICE then
        L._police_alert(inst)
    end

    ST.metrics.instances_started = ST.metrics.instances_started + 1
    return true, { inst_id = inst.id }
end


-- ============================================================
-- POLICE ALERT — broadcast de blip para policia
-- ============================================================

-- Dispara blip de alerta para todos players com permissao de policia.
-- Fonte unica de verdade dos players ativos: GetPlayers() (native FiveM).
function L._police_alert(inst)
    local track = ST.track(inst.track_id)
    if not track or not track.start then return end

    for _, psrc in ipairs(GetPlayers()) do
        psrc = tonumber(psrc)
        local has_perm = false
        pcall(function()
            has_perm = exports.vhub_groups:hasPermission(psrc, Cfg.POLICE.PERMISSION)
        end)
        if has_perm then
            TriggerClientEvent(E.RACE_POLICE, psrc, {
                track_id = inst.track_id,
                label    = track.label,
                start    = track.start,
                ttl_ms   = Cfg.POLICE.BLIP_TTL_MS or 90000,
                kind     = inst.kind,
            })
        end
    end
end


-- ============================================================
-- LIFECYCLE — GC + player dropped
-- ============================================================

-- GC de lobbies estagnados (TTL_MS sem confirmacao)
function L.gc_idle()
    local now = ms()
    local ttl = Cfg.LOBBY_TTL_MS or 600000

    for inst_id, inst in pairs(ST._instances) do
        local stagnant = (inst.state == 'lobby' or inst.state == 'pending')
                         and (now - (inst.created_ms or now)) > ttl
        if stagnant then
            L.cancel(inst_id, 'lobby_expirou')
        end
    end

    ST.gc_drafts(Cfg.EDITOR_DRAFT_TTL_MS or 1800000)
end


-- Player dropou no lobby/pending → trata como leave
function L.on_player_dropped(src)
    local inst = ST.instance_by_src(src)
    if not inst then return end

    if inst.state == 'lobby' or inst.state == 'pending' then
        L.leave(src, inst.id)
    end
end
