-- server/sql.lua — wrapper oxmysql + queries.

VHubRachaSQL = { ready = false }
local S = VHubRachaSQL

-- Categoria valida (fail-safe): qualquer valor fora do enum cai em 'normal'.
local _CATS = { ranqueada = true, normal = true, personalizada = true }
local function valid_category(c)
  c = tostring(c or '')
  return _CATS[c] and c or 'normal'
end
S.valid_category = valid_category

function S.query(sql, params)
  local p = promise.new()
  exports.oxmysql:query(sql, params or {}, function(r) p:resolve(r or {}) end)
  return Citizen.Await(p)
end

function S.execute(sql, params)
  local p = promise.new()
  exports.oxmysql:execute(sql, params or {}, function(r) p:resolve(r or 0) end)
  return Citizen.Await(p)
end

function S.execute_raw(sql)
  local p = promise.new()
  exports.oxmysql:execute(sql, {}, function() p:resolve(true) end)
  return Citizen.Await(p)
end

-- ── Tracks ──────────────────────────────────────────────────────────────────

function S.upsert_track(t)
  return S.execute([[
    INSERT INTO vh_race_tracks
      (id, label, district, kind, creator_char, illegal, alerts_police, laps,
       min_players, max_players, vehicle_class, default_fee, limit_seconds,
       start_x, start_y, start_z, start_h, source, category, enabled)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      label = VALUES(label), district = VALUES(district), kind = VALUES(kind),
      illegal = VALUES(illegal), alerts_police = VALUES(alerts_police),
      laps = VALUES(laps), min_players = VALUES(min_players),
      max_players = VALUES(max_players), vehicle_class = VALUES(vehicle_class),
      default_fee = VALUES(default_fee), limit_seconds = VALUES(limit_seconds),
      start_x = VALUES(start_x), start_y = VALUES(start_y),
      start_z = VALUES(start_z), start_h = VALUES(start_h),
      category = VALUES(category),
      enabled = VALUES(enabled)
  ]], {
    t.id, t.label or t.id, t.district or '', t.kind or 'sprint',
    tonumber(t.creator_char) or 0,
    t.illegal and 1 or 0, t.alerts_police and 1 or 0,
    tonumber(t.laps) or 1, tonumber(t.min_players) or 1, tonumber(t.max_players) or 8,
    tostring(t.vehicle_class or 'car'), tonumber(t.default_fee) or 0,
    tonumber(t.limit_seconds) or 300,
    (t.start and t.start.x) or 0, (t.start and t.start.y) or 0,
    (t.start and t.start.z) or 0, (t.start and t.start.h) or 0,
    tostring(t.source or 'config'), valid_category(t.category), 1,
  })
end

function S.set_checkpoints(track_id, cps)
  S.execute("DELETE FROM vh_race_checkpoints WHERE track_id = ?", { track_id })
  if type(cps) ~= 'table' or #cps == 0 then return end
  local ph, params = {}, {}
  for i, cp in ipairs(cps) do
    ph[#ph + 1] = '(?, ?, ?, ?, ?, ?, ?)'
    params[#params + 1] = track_id
    params[#params + 1] = i
    params[#params + 1] = cp.x
    params[#params + 1] = cp.y
    params[#params + 1] = cp.z
    params[#params + 1] = tonumber(cp.radius) or 11.0
    params[#params + 1] = tostring(cp.kind or 'normal')
  end
  S.execute(
    "INSERT INTO vh_race_checkpoints (track_id, idx, x, y, z, radius, kind) VALUES " ..
    table.concat(ph, ','), params)
end

function S.set_grid(track_id, grid)
  S.execute("DELETE FROM vh_race_grid WHERE track_id = ?", { track_id })
  if type(grid) ~= 'table' or #grid == 0 then return end
  local ph, params = {}, {}
  for i, g in ipairs(grid) do
    ph[#ph + 1] = '(?, ?, ?, ?, ?, ?)'
    params[#params + 1] = track_id
    params[#params + 1] = i
    params[#params + 1] = g.x
    params[#params + 1] = g.y
    params[#params + 1] = g.z
    params[#params + 1] = tonumber(g.h) or 0
  end
  S.execute(
    "INSERT INTO vh_race_grid (track_id, slot, x, y, z, h) VALUES " ..
    table.concat(ph, ','), params)
end

function S.load_catalog()
  local tracks = S.query("SELECT * FROM vh_race_tracks WHERE enabled = 1")
  local out = {}
  for _, row in ipairs(tracks) do
    out[row.id] = {
      id = row.id, label = row.label, district = row.district, kind = row.kind,
      creator_char  = tonumber(row.creator_char) or 0,
      illegal       = tonumber(row.illegal) == 1,
      alerts_police = tonumber(row.alerts_police) == 1,
      laps          = tonumber(row.laps) or 1,
      min_players   = tonumber(row.min_players) or 1,
      max_players   = tonumber(row.max_players) or 8,
      vehicle_class = row.vehicle_class,
      default_fee   = tonumber(row.default_fee) or 0,
      limit_seconds = tonumber(row.limit_seconds) or 300,
      start         = { x = tonumber(row.start_x), y = tonumber(row.start_y),
                        z = tonumber(row.start_z), h = tonumber(row.start_h) },
      source        = row.source or 'config',
      category      = valid_category(row.category),
      checkpoints   = {},
      grid          = {},
    }
  end

  local cps = S.query("SELECT track_id, idx, x, y, z, radius, kind FROM vh_race_checkpoints ORDER BY track_id, idx")
  for _, cp in ipairs(cps) do
    local t = out[cp.track_id]
    if t then
      t.checkpoints[#t.checkpoints + 1] = {
        x = tonumber(cp.x), y = tonumber(cp.y), z = tonumber(cp.z),
        radius = tonumber(cp.radius), kind = cp.kind,
      }
    end
  end

  local grid = S.query("SELECT track_id, slot, x, y, z, h FROM vh_race_grid ORDER BY track_id, slot")
  for _, g in ipairs(grid) do
    local t = out[g.track_id]
    if t then
      t.grid[#t.grid + 1] = {
        x = tonumber(g.x), y = tonumber(g.y), z = tonumber(g.z), h = tonumber(g.h),
      }
    end
  end
  return out
end

function S.delete_track(track_id, only_custom)
  if only_custom then
    return S.execute("DELETE FROM vh_race_tracks WHERE id = ? AND source = 'custom'", { track_id })
  end
  return S.execute("DELETE FROM vh_race_tracks WHERE id = ?", { track_id })
end

-- ── History / Results / Records / Stats ────────────────────────────────────

function S.insert_history(row)
  local p = promise.new()
  exports.oxmysql:execute([[
    INSERT INTO vh_race_history
      (track_id, kind, mode, category, creator_char, players_total,
       winner_char, winner_time_ms, pot_total, started_at, finished_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?))
  ]], {
    row.track_id, row.kind, row.mode or 'rankeada', valid_category(row.category),
    tonumber(row.creator_char) or 0,
    tonumber(row.players_total) or 0, tonumber(row.winner_char) or 0,
    tonumber(row.winner_time_ms) or 0, tonumber(row.pot_total) or 0,
    tonumber(row.started_at) or os.time(),
    tonumber(row.finished_at) or os.time(),
  }, function(r) p:resolve(r) end)
  local r = Citizen.Await(p)
  if type(r) == 'table' then return tonumber(r.insertId) or 0 end
  return tonumber(r) or 0
end

function S.insert_results(history_id, results)
  if type(results) ~= 'table' or #results == 0 then return end
  local ph, params = {}, {}
  for _, r in ipairs(results) do
    ph[#ph + 1] = '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    params[#params + 1] = history_id
    params[#params + 1] = tonumber(r.char_id) or 0
    params[#params + 1] = tostring(r.nick or '')
    params[#params + 1] = tonumber(r.placement) or 0
    params[#params + 1] = tonumber(r.total_time_ms) or 0
    params[#params + 1] = tonumber(r.best_lap_ms) or 0
    params[#params + 1] = tonumber(r.drift_score) or 0
    params[#params + 1] = tonumber(r.top_speed) or 0
    params[#params + 1] = (r.finished and 1) or 0
    params[#params + 1] = tonumber(r.payout) or 0
  end
  S.execute([[
    INSERT INTO vh_race_results
      (history_id, char_id, nick, placement, total_time_ms, best_lap_ms,
       drift_score, top_speed, finished, payout)
    VALUES ]] .. table.concat(ph, ','), params)
end

function S.update_records(track_id, char_id, time_ms, drift, top_speed, was_win)
  S.execute([[
    INSERT INTO vh_race_records
      (track_id, char_id, best_time_ms, best_drift, top_speed, runs, wins)
    VALUES (?, ?, ?, ?, ?, 1, ?)
    ON DUPLICATE KEY UPDATE
      best_time_ms = IF(? > 0 AND (best_time_ms = 0 OR ? < best_time_ms), ?, best_time_ms),
      best_drift   = GREATEST(best_drift, ?),
      top_speed    = GREATEST(top_speed, ?),
      runs         = runs + 1,
      wins         = wins + ?
  ]], {
    track_id, char_id, time_ms or 0, drift or 0, top_speed or 0, was_win and 1 or 0,
    time_ms or 0, time_ms or 0, time_ms or 0,
    drift or 0, top_speed or 0, was_win and 1 or 0,
  })
end

function S.update_stats(char_id, kind, was_win, was_podium, dnf, payout, drift, top_speed, time_ms)
  S.execute([[
    INSERT INTO vh_race_stats
      (char_id, kind, runs, wins, podiums, dnf, total_payout, total_drift, top_speed, best_time_ms)
    VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      runs          = runs + 1,
      wins          = wins + ?,
      podiums       = podiums + ?,
      dnf           = dnf + ?,
      total_payout  = total_payout + ?,
      total_drift   = total_drift + ?,
      top_speed     = GREATEST(top_speed, ?),
      best_time_ms  = IF(? > 0 AND (best_time_ms = 0 OR ? < best_time_ms), ?, best_time_ms)
  ]], {
    char_id, kind, was_win and 1 or 0, was_podium and 1 or 0, dnf and 1 or 0,
    payout or 0, drift or 0, top_speed or 0, time_ms or 0,
    was_win and 1 or 0, was_podium and 1 or 0, dnf and 1 or 0,
    payout or 0, drift or 0, top_speed or 0,
    time_ms or 0, time_ms or 0, time_ms or 0,
  })
end

-- ── Queries (NUI) ───────────────────────────────────────────────────────────

function S.history_recent(filters, limit)
  filters = type(filters) == 'table' and filters or {}
  local where, params = {}, {}
  if tonumber(filters.char_id) then
    where[#where + 1] = "id IN (SELECT history_id FROM vh_race_results WHERE char_id = ?)"
    params[#params + 1] = tonumber(filters.char_id)
  end
  if type(filters.track_id) == 'string' and filters.track_id ~= '' then
    where[#where + 1] = 'track_id = ?'; params[#params + 1] = filters.track_id
  end
  if type(filters.kind) == 'string' and filters.kind ~= '' then
    where[#where + 1] = 'kind = ?'; params[#params + 1] = filters.kind
  end
  if type(filters.mode) == 'string' and filters.mode ~= '' then
    where[#where + 1] = 'mode = ?'; params[#params + 1] = filters.mode
  end
  if type(filters.category) == 'string' and filters.category ~= '' then
    where[#where + 1] = 'category = ?'; params[#params + 1] = filters.category
  end
  local lim = math.min(math.max(tonumber(limit) or 30, 1), 100)
  params[#params + 1] = lim
  local where_sql = #where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or ''
  return S.query([[
    SELECT id, track_id, kind, mode, category, creator_char, players_total,
           winner_char, winner_time_ms, pot_total,
           UNIX_TIMESTAMP(started_at)  AS started_unix,
           UNIX_TIMESTAMP(finished_at) AS finished_unix
    FROM vh_race_history ]] .. where_sql .. [[
    ORDER BY id DESC LIMIT ?
  ]], params)
end

function S.results_of(history_id)
  return S.query([[
    SELECT char_id, nick, placement, total_time_ms, best_lap_ms,
           drift_score, top_speed, finished, payout
    FROM vh_race_results WHERE history_id = ?
    ORDER BY placement ASC
  ]], { tonumber(history_id) or 0 })
end

function S.ranking_kind(kind, mode, limit)
  local lim = math.min(math.max(tonumber(limit) or 50, 1), 100)
  local order = 'wins DESC, podiums DESC, runs DESC'
  if mode == 'time' then order = 'best_time_ms ASC, wins DESC' end
  if mode == 'drift' then order = 'total_drift DESC, wins DESC' end
  return S.query([[
    SELECT char_id, kind, runs, wins, podiums, dnf,
           total_payout, total_drift, top_speed, best_time_ms
    FROM vh_race_stats
    WHERE kind = ? AND runs > 0
    ORDER BY ]] .. order .. [[
    LIMIT ?
  ]], { kind, lim })
end

function S.stats_of_char(char_id)
  return S.query([[
    SELECT kind, runs, wins, podiums, dnf,
           total_payout, total_drift, top_speed, best_time_ms
    FROM vh_race_stats WHERE char_id = ? ORDER BY kind
  ]], { tonumber(char_id) or 0 })
end

function S.records_of_char(char_id, limit)
  local lim = math.min(math.max(tonumber(limit) or 30, 1), 100)
  return S.query([[
    SELECT track_id, best_time_ms, best_drift, top_speed, runs, wins
    FROM vh_race_records WHERE char_id = ?
    ORDER BY runs DESC LIMIT ?
  ]], { tonumber(char_id) or 0, lim })
end

-- ── Ranqueado (PDL) — escritas/leituras de vh_race_ranked ───────────────────
-- Escritor logico unico = server/ranked.lua. Aqui mora apenas o SQL.

-- Linha PDL de UM personagem (nil se nunca correu ranqueada).
function S.ranked_one(char_id)
  local rows = S.query(
    "SELECT char_id, pdl, peak_pdl, matches, wins, last_match_at FROM vh_race_ranked WHERE char_id = ?",
    { tonumber(char_id) or 0 })
  return rows and rows[1] or nil
end

-- Snapshot de varios personagens (IN ...) — usado no finalize ANTES de computar deltas.
function S.ranked_many(char_ids)
  if type(char_ids) ~= 'table' or #char_ids == 0 then return {} end
  local ph = {}
  for _ = 1, #char_ids do ph[#ph + 1] = '?' end
  return S.query(
    "SELECT char_id, pdl, peak_pdl, matches, wins FROM vh_race_ranked WHERE char_id IN (" ..
    table.concat(ph, ',') .. ")", char_ids) or {}
end

-- Persiste os novos ratings em LOTE — UM unico statement (atomico no MySQL).
-- `rows[i]` = { char_id, pdl, peak_pdl, matches, wins, last_match_at } (valores ABSOLUTOS).
function S.upsert_ranked_batch(rows)
  if type(rows) ~= 'table' or #rows == 0 then return end
  local ph, params = {}, {}
  for _, r in ipairs(rows) do
    ph[#ph + 1] = '(?, ?, ?, ?, ?, ?)'
    params[#params + 1] = tonumber(r.char_id) or 0
    params[#params + 1] = math.floor(tonumber(r.pdl) or 0)
    params[#params + 1] = math.floor(tonumber(r.peak_pdl) or 0)
    params[#params + 1] = math.floor(tonumber(r.matches) or 0)
    params[#params + 1] = math.floor(tonumber(r.wins) or 0)
    params[#params + 1] = math.floor(tonumber(r.last_match_at) or 0)
  end
  S.execute([[
    INSERT INTO vh_race_ranked (char_id, pdl, peak_pdl, matches, wins, last_match_at)
    VALUES ]] .. table.concat(ph, ',') .. [[
    ON DUPLICATE KEY UPDATE
      pdl           = VALUES(pdl),
      peak_pdl      = GREATEST(peak_pdl, VALUES(peak_pdl)),
      matches       = VALUES(matches),
      wins          = VALUES(wins),
      last_match_at = VALUES(last_match_at)
  ]], params)
end

-- Leaderboard PDL (cross-kind). So personagens que ja jogaram ranqueada (matches > 0).
function S.ranked_top(limit)
  local lim = math.min(math.max(tonumber(limit) or 50, 1), 100)
  return S.query([[
    SELECT char_id, pdl, peak_pdl, matches, wins
    FROM vh_race_ranked
    WHERE matches > 0
    ORDER BY pdl DESC, peak_pdl DESC
    LIMIT ?
  ]], { lim }) or {}
end

-- Decaimento por inatividade — 1 UPDATE set-based (sweep diario do ranked.lua).
function S.ranked_decay(floor, amount, threshold, cutoff_unix)
  return S.execute([[
    UPDATE vh_race_ranked
    SET pdl = GREATEST(?, pdl - ?)
    WHERE pdl > ? AND last_match_at > 0 AND last_match_at < ?
  ]], {
    math.floor(tonumber(floor) or 0), math.floor(tonumber(amount) or 0),
    math.floor(tonumber(threshold) or 0), math.floor(tonumber(cutoff_unix) or 0),
  })
end

-- Garante uma coluna (ALTER idempotente): so adiciona se SHOW COLUMNS nao achar.
local function ensure_column(tbl, col, alter_sql)
  local ok, cols = pcall(function()
    return S.query(("SHOW COLUMNS FROM %s LIKE '%s'"):format(tbl, col))
  end)
  if ok and cols and #cols > 0 then return false end
  VHubRachaLog.info('schema: adicionando coluna `%s` em %s', col, tbl)
  pcall(function() S.execute_raw(alter_sql) end)
  return true
end

function S.apply_schema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if type(schema) ~= 'string' or schema == '' then return false, 'schema_missing' end
  S.execute_raw(schema)

  -- Compat (upgrades de schema sem migracao destrutiva)
  ensure_column('vh_race_history', 'mode', [[
    ALTER TABLE vh_race_history
    ADD COLUMN `mode` ENUM('rankeada','treino','privada') NOT NULL DEFAULT 'rankeada',
    ADD KEY `idx_hist_mode` (`mode`)
  ]])
  ensure_column('vh_race_history', 'category', [[
    ALTER TABLE vh_race_history
    ADD COLUMN `category` ENUM('ranqueada','normal','personalizada') NOT NULL DEFAULT 'normal',
    ADD KEY `idx_hist_category` (`category`)
  ]])
  ensure_column('vh_race_tracks', 'category', [[
    ALTER TABLE vh_race_tracks
    ADD COLUMN `category` ENUM('ranqueada','normal','personalizada') NOT NULL DEFAULT 'normal'
  ]])

  S.ready = true
  return true
end
