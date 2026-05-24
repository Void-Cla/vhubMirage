-- server/history.lua — finalize: persiste resultado de uma instancia.

VHubRachaHistory = {}
local H = VHubRachaHistory
local Cfg = VHubRachaCfg
local SQL = VHubRachaSQL
local AC  = VHubRachaAC

local function payout_dist(n_finalists)
  if n_finalists >= 3 then return Cfg.PAYOUT_3P end
  if n_finalists == 2 then return Cfg.PAYOUT_2P end
  return Cfg.PAYOUT_SOLO
end

function H.finalize(inst)
  if type(inst) ~= 'table' then return nil end

  local players = {}
  for src, p in pairs(inst.players or {}) do
    players[#players + 1] = {
      src           = src,
      char_id       = tonumber(p.char_id) or 0,
      nick          = tostring(p.nick or ''),
      total_time_ms = (p.finished_ms and p.started_ms) and (p.finished_ms - p.started_ms) or 0,
      best_lap_ms   = tonumber(p.best_lap_ms) or 0,
      -- Ensure drift_score persisted is clamped server-side (prevents client-spike abuse)
      drift_score   = AC.cap_drift_score(p.drift_score or 0, p.started_ms, p.finished_ms),
      top_speed     = AC.cap_top_speed(p.top_speed),
      finished      = p.finished == true,
      cp_done       = tonumber(p.cp_done) or 0,
    }
  end

  local kind = inst.kind or 'sprint'
  table.sort(players, function(a, b)
    if a.finished ~= b.finished then return a.finished end
    if a.finished and b.finished then
      if kind == 'drift' then
        if a.drift_score ~= b.drift_score then return a.drift_score > b.drift_score end
        return a.total_time_ms < b.total_time_ms
      end
      if kind == 'speedtrap' then
        if a.top_speed ~= b.top_speed then return a.top_speed > b.top_speed end
        return a.total_time_ms < b.total_time_ms
      end
      return a.total_time_ms < b.total_time_ms
    end
    return a.cp_done > b.cp_done
  end)

  for i, p in ipairs(players) do p.placement = i end

  -- Payout
  local mode = inst.mode or 'rankeada'
  local pot = tonumber(inst.pot_total) or 0
  local finalists = 0
  for _, p in ipairs(players) do if p.finished then finalists = finalists + 1 end end
  local dist = payout_dist(finalists)

  -- Modo treino e freerun nao pagam
  if mode == 'treino' or inst.kind == 'freerun' then dist = {} end

  for i, p in ipairs(players) do
    local pct = (p.finished and dist[i]) or 0
    p.payout = math.floor(pot * pct)
  end

  local winner = players[1]
  local winner_char    = (winner and winner.finished and winner.char_id) or 0
  local winner_time_ms = (winner and winner.finished and winner.total_time_ms) or 0

  local now = os.time()
  local history_id = SQL.insert_history({
    track_id       = inst.track_id,
    kind           = kind,
    mode           = mode,
    creator_char   = tonumber(inst.creator_char) or 0,
    players_total  = #players,
    winner_char    = winner_char,
    winner_time_ms = winner_time_ms,
    pot_total      = pot,
    started_at     = inst.started_at or now,
    finished_at    = now,
  })

  if history_id and history_id > 0 then
    SQL.insert_results(history_id, players)
  end

  -- Records + stats so para modo rankeado
  if mode == 'rankeada' then
    for i, p in ipairs(players) do
      if p.char_id > 0 then
        local was_win    = (i == 1 and p.finished)
        local was_podium = (i <= 3 and p.finished)
        local dnf        = not p.finished
        SQL.update_records(inst.track_id, p.char_id,
          p.finished and p.total_time_ms or 0,
          p.drift_score, p.top_speed, was_win)
        SQL.update_stats(p.char_id, kind, was_win, was_podium, dnf,
          p.payout, p.drift_score, p.top_speed,
          p.finished and p.total_time_ms or 0)
      end
    end
  end

  return { history_id = history_id, players = players, winner_char = winner_char }
end
