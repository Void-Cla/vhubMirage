-- server/runtime.lua — corrida ativa (racing → finished).

VHubRachaRuntime = {}
local RT  = VHubRachaRuntime
local Cfg = VHubRachaCfg
local AC  = VHubRachaAC
local ST  = VHubRachaState
local HIS = VHubRachaHistory
local RW  = VHubRachaRewards
local E   = VHubRachaE

local function ms() return GetGameTimer() end

local function notify(src, msg, kind)
  if src and src > 0 then TriggerClientEvent(E.NOTIFY, src, msg, kind or 'info') end
end

local function sync_state_bag(inst)
  for src, p in pairs(inst.players or {}) do
    Player(src).state:set('vhub_racha', {
      inst_id     = inst.id,
      track_id    = inst.track_id,
      kind        = inst.kind,
      mode        = inst.mode,
      state       = inst.state,
      cp_done     = p.cp_done or 0,
      cp_total    = inst.cp_total or 0,
      lap         = p.lap or 0,
      laps        = inst.laps or 1,
      placement   = p.placement or 0,
      players_total = ST.count_players(inst),
      drift_score = p.drift_score or 0,
      starts_at   = inst.starts_at or 0,
      started_ms  = p.started_ms or 0,
    }, true)
  end
end

-- ── Begin racing (chamado pelo lobby apos countdown) ───────────────────────

function RT.begin_racing(inst)
  inst.state = 'racing'
  local now_ms = ms()
  for src, p in pairs(inst.players) do
    p.state = 'racing'
    p.started_ms = now_ms
    p.last_cp_ms = now_ms
    TriggerClientEvent(E.RACE_START, src, { inst_id = inst.id, started_ms = now_ms })
  end
  sync_state_bag(inst)

  -- Timeout duro
  local track = ST.track(inst.track_id)
  local limit = (track and track.limit_seconds or 300) * 1000
  if limit > 0 then
    SetTimeout(limit, function()
      local i = ST.instance(inst.id)
      if not i or i.state ~= 'racing' then return end
      RT.finish(inst.id, 'timeout')
    end)
  end
end

-- ── Checkpoint / tick ──────────────────────────────────────────────────────

function RT.on_checkpoint(src, payload)
  local inst = ST.instance_by_src(src); if not inst then return end
  if inst.state ~= 'racing' then return end

  local ok, err = AC.validate_checkpoint(inst, src, payload)
  if not ok then
    notify(src, ('CP invalidado: %s'):format(tostring(err)), 'error')
    return
  end

  local player = inst.players[src]
  player.cp_done = (player.cp_done or 0) + 1
  player.last_cp_ms = ms()
  local cp_total = inst.cp_total or 0
  local cps_per_lap = math.max(1, math.floor(cp_total / math.max(1, inst.laps)))
  player.lap = math.floor((player.cp_done - 1) / cps_per_lap) + 1

  -- Update state bag (HUD reflete)
  Player(src).state:set('vhub_racha', {
    inst_id     = inst.id,
    track_id    = inst.track_id,
    kind        = inst.kind,
    mode        = inst.mode,
    state       = 'racing',
    cp_done     = player.cp_done,
    cp_total    = cp_total,
    lap         = player.lap,
    laps        = inst.laps,
    players_total = ST.count_players(inst),
    drift_score = player.drift_score,
    started_ms  = player.started_ms,
  }, true)

  if cp_total > 0 and player.cp_done >= cp_total then
    RT._player_finish(inst, src)
  end
end

function RT.on_tick(src, payload)
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

  -- Update state bag for HUD
  Player(src).state:set('vhub_racha', {
    inst_id     = inst.id,
    track_id    = inst.track_id,
    kind        = inst.kind,
    mode        = inst.mode,
    state       = inst.state,
    cp_done     = player.cp_done or 0,
    cp_total    = inst.cp_total or 0,
    lap         = player.lap or 0,
    laps        = inst.laps or 1,
    players_total = ST.count_players(inst),
    drift_score = player.drift_score,
    started_ms  = player.started_ms or 0,
  }, true)
end

function RT._player_finish(inst, src)
  local player = inst.players[src]
  if not player or player.finished then return end
  player.finished = true
  player.finished_ms = ms()
  player.state = 'finished'
  notify(src, 'Voce cruzou a linha de chegada!', 'success')

  if inst.finish_grace_started_at == 0 then
    inst.finish_grace_started_at = ms()
    SetTimeout(Cfg.FINISH_GRACE_MS or 60000, function()
      local i = ST.instance(inst.id)
      if not i or i.state ~= 'racing' then return end
      RT.finish(inst.id, 'grace_expirou')
    end)
  end

  local pending = 0
  for _, p in pairs(inst.players) do if not p.finished then pending = pending + 1 end end
  if pending == 0 then RT.finish(inst.id, 'todos_terminaram') end
end

function RT.on_abort(src, reason)
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
  if pending == 0 then RT.finish(inst.id, 'todos_dnf') end
end

-- ── Finish ─────────────────────────────────────────────────────────────────

function RT.finish(inst_id, reason)
  local inst = ST.instance(inst_id); if not inst then return false end
  if inst.state == 'finished' or inst.state == 'closed' then return false end
  inst.state = 'finished'
  ST.metrics.instances_finished = ST.metrics.instances_finished + 1

  local result = HIS.finalize(inst)
  if not result then
    for src, _ in pairs(inst.players) do
      RW.refund(src, inst.entry_fee or 0, 'race_failed')
      Player(src).state:set('vhub_racha', nil, true)
      ST.unbind_src(src)
    end
    ST.remove_instance(inst.id)
    return false, 'finalize_failed'
  end

  -- Paga premios
  for _, p in ipairs(result.players) do
    if (p.payout or 0) > 0 and p.src then RW.pay(p.src, p.payout, 'race_payout') end
    if p.src then
      TriggerClientEvent(E.RACE_FINISH, p.src, {
        inst_id     = inst.id,
        placement   = p.placement,
        time_ms     = p.total_time_ms,
        drift       = p.drift_score,
        payout      = p.payout,
        history_id  = result.history_id,
        winner_char = result.winner_char,
        reason      = reason or 'finished',
        mode        = inst.mode,
      })
      Player(p.src).state:set('vhub_racha', nil, true)
      ST.unbind_src(p.src)
    end
  end

  inst.state = 'closed'
  ST.remove_instance(inst.id)
  return true, result
end

-- Player dropped durante corrida = DNF
function RT.on_player_dropped(src)
  local inst = ST.instance_by_src(src); if not inst then return end
  if inst.state == 'racing' then RT.on_abort(src, 'dropped') end
end
