-- server/manager.lua — lifecycle de instancia de corrida.
-- Cria lobby → join/leave → start (warmup) → racing → finished.

VHubRachaManager = {}
local M = VHubRachaManager
local Cfg = VHubRachaCfg
local U   = VHubRachaUtils
local AC  = VHubRachaAC
local ST  = VHubRachaState
local HIS = VHubRachaHistory
local E   = VHubRachaE

local _vHub = nil
function M.set_vhub(vh) _vHub = vh end
function M.get_vhub()   return _vHub end

local function ms() return GetGameTimer() end

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function user_of(src)
  if not _vHub or not _vHub.Auth then
    print(('vhub_racha: user_of(%s) -> nil (no _vHub/Auth)'):format(tostring(src)))
    return nil
  end

  local attempts = 20
  local lookup_key = tonumber(src) or src
  for i = 1, attempts do
    local ok, user = pcall(function() return _vHub.Auth:getUser(lookup_key) end)
    if ok and user then
      if i > 1 then
        print(('vhub_racha: user_of(%s) -> acquired after %d tries'):format(tostring(src), i))
      end
      return user
    end
    -- pequena espera para tolerar race de autenticação (100ms * attempts = 2000ms)
    Citizen.Wait(100)
  end

  -- Fallbacks: tente lookup direto na tabela _sessions usando chaves string/number
  local sessions = (_vHub and _vHub.Auth and _vHub.Auth._sessions) or {}
  local direct = sessions[lookup_key] or sessions[tostring(lookup_key)] or sessions[tostring(src)]
  if direct then
    print(('vhub_racha: user_of(%s) -> found via _sessions direct key'):format(tostring(src)))
    return direct
  end

  -- Itera para encontrar uma sessão cujo campo 'source' coincida com src
  for k, v in pairs(sessions) do
    if type(v) == 'table' then
      if v.source == src or tostring(v.source) == tostring(src) or tostring(k) == tostring(src) then
        print(('vhub_racha: user_of(%s) -> found in _sessions by value key=%s'):format(tostring(src), tostring(k)))
        return v
      end
    end
  end

  print(('vhub_racha: user_of(%s) -> nil after %d attempts and fallbacks'):format(tostring(src), attempts))
  -- Debug: listar chaves ativas em vHub.Auth._sessions (só para triagem)
  if _vHub and _vHub.Auth then
    pcall(function()
      local cnt = 0
      for k,_ in pairs(_vHub.Auth._sessions or {}) do cnt = cnt + 1 end
      print(('vhub_racha: vHub.Auth._sessions count=%d'):format(cnt))
      local i = 0
      for k,_ in pairs(_vHub.Auth._sessions or {}) do
        i = i + 1
        if i <= 16 then
          print(('vhub_racha: session_key[%d]=%s'):format(i, tostring(k)))
        end
      end
    end)
  end
  return nil
end

local function notify(src, msg, kind)
  if src and src > 0 then
    TriggerClientEvent(E.NOTIFY, src, msg, kind or 'info')
  end
end

local function sync_state_bag(inst)
  -- State Bag por player com info da corrida atual (HUD le)
  for src, p in pairs(inst.players or {}) do
    Player(src).state:set('vhub_racha', {
      inst_id     = inst.id,
      track_id    = inst.track_id,
      kind        = inst.kind,
      state       = inst.state,
      cp_done     = p.cp_done or 0,
      cp_total    = inst.cp_total or 0,
      lap         = p.lap or 0,
      laps        = inst.laps or 1,
      placement   = p.placement or 0,
      drift_score = p.drift_score or 0,
      starts_at   = inst.starts_at or 0,
      started_ms  = p.started_ms or 0,
    }, true)
  end
end

local function broadcast(inst, ev, payload)
  for src, _ in pairs(inst.players or {}) do
    TriggerClientEvent(ev, src, payload)
  end
end

-- ── Money ─────────────────────────────────────────────────────────────────

local function charge_fee(src, fee)
  if (fee or 0) <= 0 then return true end
  local ok = false
  pcall(function()
    ok = exports.vhub_money:tryFullPayment(src, fee, false) == true
  end)
  return ok
end

local function reward(src, amount, reason)
  if (amount or 0) <= 0 then return end
  pcall(function()
    exports.vhub_money:giveBank(src, math.floor(amount), reason or 'race_reward')
  end)
end

-- ── Lobby ──────────────────────────────────────────────────────────────────

-- Cria nova instancia (lobby aberto)
function M.create_lobby(src, payload)
  local user = user_of(src); if not user then return false, 'sem_sessao' end
  local track_id = U.sanitize_id((payload and payload.track_id) or '')
  local track = ST.track(track_id)
  if not track then return false, 'pista_inexistente' end

  -- Solo modes (timeattack) → cria e ja starta direto
  -- Free run → simplificado (sem warmup, sem pot, sem ranking)

  local entry_fee = U.clamp_int((payload and payload.entry_fee) or track.default_fee or 0,
                                0, Cfg.MAX_ENTRY_FEE)
  local laps      = U.clamp_int((payload and payload.laps) or track.laps or 1, 1, 10)
  if track.kind == 'freerun' or track.kind == 'timeattack' then entry_fee = 0 end

  local cp_total = (#(track.checkpoints or {})) * laps

  local inst = {
    id            = U.short_id(),
    track_id      = track.id,
    label         = track.label,
    district      = track.district,
    kind          = track.kind,
    illegal       = track.illegal == true,
    alerts_police = track.alerts_police == true,
    laps          = laps,
    cp_total      = cp_total,
    min_players   = track.min_players or 1,
    max_players   = track.max_players or 8,
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
    finish_grace_started_at = 0,
  }

  -- Auto-join criador
  ST.put_instance(inst)
  ST.metrics.instances_created = ST.metrics.instances_created + 1
  local ok, err = M.join(src, inst.id)
  if not ok then
    ST.remove_instance(inst.id)
    return false, err
  end

  -- TimeAttack: solo → ja inicia
  if track.kind == 'timeattack' then
    return M.start(inst.id, true)
  end

  return true, { inst_id = inst.id }
end

-- Entra em lobby
function M.join(src, inst_id)
  local user = user_of(src); if not user then return false, 'sem_sessao' end
  local inst = ST.instance(inst_id); if not inst then return false, 'instancia_inexistente' end
  if inst.state ~= 'lobby' then return false, 'lobby_fechado' end
  if inst.players[src] then return false, 'ja_no_lobby' end

  -- Verifica se ja esta em outra
  if ST.instance_by_src(src) then return false, 'ja_em_outra_corrida' end

  -- Capacidade
  if ST.count_players(inst) >= (inst.max_players or 8) then
    return false, 'lobby_cheio'
  end

  -- Cobra fee
  if (inst.entry_fee or 0) > 0 and not charge_fee(src, inst.entry_fee) then
    return false, 'saldo_insuficiente'
  end

  -- Alloca grid slot (proximo livre)
  local grid_slot = nil
  for i = 1, (inst.max_players or 8) do
    if not inst.grid_used[i] then grid_slot = i; break end
  end
  if not grid_slot then return false, 'sem_grid' end
  inst.grid_used[grid_slot] = src

  -- Nick: tenta exports.vhub_identity, fallback "char_<id>"
  local nick = 'char_' .. user.char_id
  pcall(function()
    if exports.vhub_identity then
      local full = exports.vhub_identity:getFullName(src)
      if type(full) == 'string' and full ~= '' then nick = full end
    end
  end)

  inst.players[src] = {
    src         = src,
    char_id     = user.char_id,
    nick        = nick,
    grid_slot   = grid_slot,
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

  -- Sincroniza estado
  sync_state_bag(inst)
  notify(src, ('Voce entrou na corrida (%s).'):format(inst.label or inst.track_id), 'success')
  return true, { inst_id = inst.id, grid_slot = grid_slot }
end

-- Sai do lobby (sem corrida iniciada)
function M.leave(src, inst_id)
  local inst = ST.instance(inst_id); if not inst then return false end
  local player = inst.players[src]; if not player then return false end

  -- Devolve fee se ainda em lobby
  if inst.state == 'lobby' and (inst.entry_fee or 0) > 0 then
    reward(src, inst.entry_fee, 'lobby_refund')
    inst.pot_total = math.max(0, (inst.pot_total or 0) - inst.entry_fee)
  end

  inst.players[src] = nil
  inst.grid_used[player.grid_slot or 0] = nil
  ST.unbind_src(src)

  -- Reseta state bag desse player
  Player(src).state:set('vhub_racha', nil, true)

  -- Se criador saiu E ainda em lobby → cancela
  if inst.state == 'lobby' and player.char_id == inst.creator_char then
    return M.cancel(inst_id, 'criador_saiu')
  end

  -- Se ficou vazia
  if ST.count_players(inst) == 0 then
    ST.remove_instance(inst.id)
  end

  return true
end

-- Cancela lobby (devolve fees)
function M.cancel(inst_id, reason)
  local inst = ST.instance(inst_id); if not inst then return false end
  if inst.state ~= 'lobby' then return false, 'nao_e_lobby' end
  for src, p in pairs(inst.players) do
    if (inst.entry_fee or 0) > 0 then
      reward(src, inst.entry_fee, 'lobby_cancel')
    end
    notify(src, ('Lobby cancelado (%s).'):format(reason or 'cancelado'), 'error')
    Player(src).state:set('vhub_racha', nil, true)
    ST.unbind_src(src)
  end
  ST.remove_instance(inst.id)
  return true
end

-- ── Start: warmup + race ───────────────────────────────────────────────────

-- Inicia warmup (countdown). solo=true pula min_players.
function M.start(inst_id, solo)
  local inst = ST.instance(inst_id); if not inst then return false, 'inst_inexistente' end
  if inst.state ~= 'lobby' then return false, 'estado_invalido' end

  local n = ST.count_players(inst)
  if not solo and n < (inst.min_players or 1) then
    return false, 'jogadores_insuficientes'
  end

  inst.state = 'warmup'
  inst.starts_at = ms() + (Cfg.COUNTDOWN_MS or 7000)
  inst.started_at = os.time()

  -- Envia prepare ao cliente (teleporta para grid, congela)
  local track = ST.track(inst.track_id)
  for src, p in pairs(inst.players) do
    local grid_slot = (track.grid and track.grid[p.grid_slot]) or track.start
    TriggerClientEvent(E.RACE_PREPARE, src, {
      inst_id    = inst.id,
      track      = track,
      laps       = inst.laps,
      grid_pos   = grid_slot,
      starts_at  = inst.starts_at,
      countdown  = Cfg.COUNTDOWN_MS or 7000,
    })
  end

  -- Agenda start
  SetTimeout(Cfg.COUNTDOWN_MS or 7000, function()
    local i = ST.instance(inst_id)
    if not i or i.state ~= 'warmup' then return end
    M._begin_racing(i)
  end)

  -- Alerta polícia se illegal
  if inst.alerts_police and Cfg.POLICE then
    M._dispatch_police_alert(inst)
  end

  ST.metrics.instances_started = ST.metrics.instances_started + 1
  return true
end

function M._begin_racing(inst)
  inst.state = 'racing'
  local now_ms = ms()
  for src, p in pairs(inst.players) do
    p.state = 'racing'
    p.started_ms = now_ms
    p.last_cp_ms = now_ms
    Player(src).state:set('vhub_racha', {
      inst_id     = inst.id,
      track_id    = inst.track_id,
      kind        = inst.kind,
      state       = 'racing',
      cp_done     = 0,
      cp_total    = inst.cp_total,
      lap         = 0,
      laps        = inst.laps,
      drift_score = 0,
      started_ms  = now_ms,
    }, true)
    TriggerClientEvent(E.RACE_START, src, { inst_id = inst.id, started_ms = now_ms })
  end

  -- Agenda timeout duro
  local track = ST.track(inst.track_id)
  local limit = (track and track.limit_seconds or 300) * 1000
  if limit > 0 then
    SetTimeout(limit, function()
      local i = ST.instance(inst.id)
      if not i or i.state ~= 'racing' then return end
      M.finish(inst.id, 'timeout')
    end)
  end
end

function M._dispatch_police_alert(inst)
  if not _vHub or not _vHub.Auth or not _vHub.Auth._sessions then return end
  local track = ST.track(inst.track_id)
  if not track or not track.start then return end

  -- Encontra players com permissao policia
  for psrc, puser in pairs(_vHub.Auth._sessions) do
    local has_perm = false
    pcall(function()
      has_perm = exports.vhub_groups:hasPermission(psrc, Cfg.POLICE.PERMISSION)
    end)
    if has_perm then
      TriggerClientEvent(VHubRachaE.RACE_POLICE, psrc, {
        track_id = inst.track_id,
        label = track.label,
        start = track.start,
        ttl_ms = Cfg.POLICE.BLIP_TTL_MS or 90000,
        kind = inst.kind,
      })
    end
  end
end

-- ── Checkpoint / tick / finish ─────────────────────────────────────────────

-- Cliente reportou que cruzou um CP
function M.on_checkpoint(src, payload)
  local inst = ST.instance_by_src(src); if not inst then return end
  if inst.state ~= 'racing' then return end

  local ok, err = AC.validate_checkpoint(inst, src, payload)
  if not ok then
    notify(src, 'CP invalidado pelo servidor: ' .. tostring(err), 'error')
    return
  end

  local player = inst.players[src]
  player.cp_done = (player.cp_done or 0) + 1
  player.last_cp_ms = ms()
  local cp_total = inst.cp_total or 0
  player.lap = math.floor(player.cp_done / math.max(1, (cp_total / math.max(1, inst.laps)))) + 1

  -- Atualiza state bag (HUD reflete)
  Player(src).state:set('vhub_racha', {
    inst_id     = inst.id,
    track_id    = inst.track_id,
    kind        = inst.kind,
    state       = 'racing',
    cp_done     = player.cp_done,
    cp_total    = cp_total,
    lap         = player.lap,
    laps        = inst.laps,
    drift_score = player.drift_score,
    started_ms  = player.started_ms,
  }, true)

  -- Terminou todos os CPs?
  if cp_total > 0 and player.cp_done >= cp_total then
    M._player_finish(inst, src)
  end
end

-- Cliente reporta tick (drift_score acumulado, top_speed) — adaptive ~1Hz
function M.on_tick(src, payload)
  local inst = ST.instance_by_src(src); if not inst then return end
  if inst.state ~= 'racing' then return end
  local player = inst.players[src]; if not player then return end
  if type(payload) ~= 'table' then return end
  -- Anti-cheat / smoothing: limit how much drift can be granted per second
  local now_ms = ms()
  local last_ms = player.last_tick_ms or now_ms
  local dt_sec = math.max(0.001, (now_ms - last_ms) / 1000.0)
  local cap_per_sec = (Cfg.DRIFT and Cfg.DRIFT.CAP_PER_SEC) or 150
  local max_gain = math.floor(cap_per_sec * dt_sec + 0.5)

  if payload.drift_score then
    local reported = math.max(0, math.floor(tonumber(payload.drift_score) or 0))
    if reported > (player.drift_score or 0) then
      local gain = math.min(reported - (player.drift_score or 0), max_gain)
      player.drift_score = (player.drift_score or 0) + gain
    end
  end

  if payload.top_speed then
    local reported_s = math.max(0, math.floor(tonumber(payload.top_speed) or 0))
    if reported_s > (player.top_speed or 0) then
      player.top_speed = math.min(reported_s, (Cfg.MAX_SPEED_KMH or 400))
    end
  end

  if payload.best_lap_ms and payload.best_lap_ms > 0 then
    if not player.best_lap_ms or payload.best_lap_ms < player.best_lap_ms then
      player.best_lap_ms = tonumber(payload.best_lap_ms)
    end
  end

  player.last_tick_ms = now_ms

  -- Update player's State Bag so HUD / other systems reflect the drift in near-real-time
  Player(src).state:set('vhub_racha', {
    inst_id     = inst.id,
    track_id    = inst.track_id,
    kind        = inst.kind,
    state       = inst.state,
    cp_done     = player.cp_done or 0,
    cp_total    = inst.cp_total or 0,
    lap         = player.lap or 0,
    laps        = inst.laps or 1,
    placement   = player.placement or 0,
    drift_score = player.drift_score or 0,
    started_ms  = player.started_ms or 0,
  }, true)
end

function M._player_finish(inst, src)
  local player = inst.players[src]
  if not player or player.finished then return end

  player.finished = true
  player.finished_ms = ms()
  player.state = 'finished'

  notify(src, 'Voce cruzou a linha de chegada!', 'success')

  -- Se primeiro a terminar, comeca grace para os outros
  if inst.finish_grace_started_at == 0 then
    inst.finish_grace_started_at = ms()
    SetTimeout(Cfg.FINISH_GRACE_MS or 60000, function()
      local i = ST.instance(inst.id)
      if not i or i.state ~= 'racing' then return end
      M.finish(inst.id, 'grace_expirou')
    end)
  end

  -- Todos terminaram?
  local pending = 0
  for _, p in pairs(inst.players) do if not p.finished then pending = pending + 1 end end
  if pending == 0 then
    M.finish(inst.id, 'todos_terminaram')
  end
end

-- Cliente abortou (saiu do veiculo, perdeu/dnf)
function M.on_abort(src, reason)
  local inst = ST.instance_by_src(src); if not inst then return end
  if inst.state ~= 'racing' then return end
  local player = inst.players[src]; if not player then return end
  player.state = 'dnf'
  player.finished = false
  player.finished_ms = ms()
  notify(src, ('Voce desistiu (%s).'):format(reason or 'dnf'), 'error')

  local pending = 0
  for _, p in pairs(inst.players) do
    if not p.finished and p.state ~= 'dnf' then pending = pending + 1 end
  end
  if pending == 0 then M.finish(inst.id, 'todos_terminaram_ou_dnf') end
end

-- Finaliza instancia: persiste history + paga premios + libera
function M.finish(inst_id, reason)
  local inst = ST.instance(inst_id); if not inst then return false end
  if inst.state == 'finished' or inst.state == 'closed' then return false end

  inst.state = 'finished'
  ST.metrics.instances_finished = ST.metrics.instances_finished + 1

  local result = HIS.finalize(inst)
  if not result then
    -- Devolve fee em caso de falha grave
    for src, _ in pairs(inst.players) do
      reward(src, inst.entry_fee or 0, 'race_failed')
      Player(src).state:set('vhub_racha', nil, true)
      ST.unbind_src(src)
    end
    ST.remove_instance(inst.id)
    return false, 'finalize_failed'
  end

  -- Paga premios
  for _, p in ipairs(result.players) do
    if (p.payout or 0) > 0 and p.src then
      reward(p.src, p.payout, 'race_payout')
    end
    if p.src then
      TriggerClientEvent(VHubRachaE.RACE_FINISH, p.src, {
        inst_id   = inst.id,
        placement = p.placement,
        time_ms   = p.total_time_ms,
        drift     = p.drift_score,
        payout    = p.payout,
        history_id = result.history_id,
        winner_char = result.winner_char,
        reason = reason or 'finished',
      })
      Player(p.src).state:set('vhub_racha', nil, true)
      ST.unbind_src(p.src)
    end
  end

  inst.state = 'closed'
  ST.remove_instance(inst.id)
  return true, result
end

-- ── Player drop / cleanup ──────────────────────────────────────────────────

function M.on_player_dropped(src)
  local inst = ST.instance_by_src(src); if not inst then return end
  if inst.state == 'lobby' then
    M.leave(src, inst.id)
    return
  end
  -- Racing: marca como DNF
  if inst.state == 'racing' then
    M.on_abort(src, 'dropped')
  end
end

-- GC de lobbies estagnados (TTL_MS sem start)
function M.gc_idle_lobbies()
  local now = ms()
  local ttl = Cfg.LOBBY_TTL_MS or 180000
  for inst_id, inst in pairs(ST._instances) do
    if inst.state == 'lobby' and (now - (inst.created_ms or now)) > ttl then
      M.cancel(inst_id, 'lobby_expirado')
    end
  end
  ST.gc_drafts(Cfg.EDITOR_DRAFT_TTL_MS or 1800000)
end
