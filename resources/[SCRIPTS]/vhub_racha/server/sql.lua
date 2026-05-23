-- server/sql.lua - wrapper oxmysql e queries do vhub_racha.

VHubRachaSQL = { ready = false }
local S = VHubRachaSQL

-- Executa SELECT; retorna lista de linhas.
function S.query(sql, params)
  local p = promise.new()
  exports.oxmysql:query(sql, params or {}, function(rows) p:resolve(rows or {}) end)
  return Citizen.Await(p)
end

-- Executa INSERT/UPDATE/DELETE; retorna resultado bruto do driver.
function S.execute(sql, params)
  local p = promise.new()
  exports.oxmysql:execute(sql, params or {}, function(result) p:resolve(result or 0) end)
  return Citizen.Await(p)
end

-- Executa INSERT e retorna insertId quando disponivel.
function S.insert(sql, params)
  local p = promise.new()
  exports.oxmysql:insert(sql, params or {}, function(id) p:resolve(tonumber(id) or 0) end)
  return Citizen.Await(p)
end

-- Aplica schema idempotente.
function S.apply_schema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if type(schema) ~= 'string' or schema == '' then return false, 'schema_file_missing' end
  S.execute(schema, {})
  S.ready = true
  return true
end

-- Cria uma corrida e retorna run_id.
function S.create_run(track_id, organizer_char_id, entry_fee, laps, ranked)
  return S.insert([[
    INSERT INTO vh_racha_runs
      (track_id, organizer_char_id, entry_fee, laps, ranked, state)
    VALUES (?, ?, ?, ?, ?, 'open')
  ]], { track_id, organizer_char_id, entry_fee or 0, laps or 1, ranked and 1 or 0 })
end

-- Atualiza estado agregado da corrida.
function S.update_run(run_id, state, participant_count, prize_pool, mark_start, mark_finish)
  local set = { 'state = ?', 'participant_count = ?', 'prize_pool = ?' }
  local params = { state, participant_count or 0, prize_pool or 0 }
  if mark_start then set[#set + 1] = 'started_at = COALESCE(started_at, CURRENT_TIMESTAMP)' end
  if mark_finish then set[#set + 1] = 'finished_at = COALESCE(finished_at, CURRENT_TIMESTAMP)' end
  params[#params + 1] = run_id
  return S.execute('UPDATE vh_racha_runs SET ' .. table.concat(set, ', ') .. ' WHERE id = ?', params)
end

-- Busca perfil de piloto.
function S.get_profile(char_id)
  local rows = S.query('SELECT char_id, nickname FROM vh_racha_profiles WHERE char_id = ? LIMIT 1', { char_id })
  return rows[1]
end

-- Busca dono de um apelido.
function S.find_nickname(nickname)
  local rows = S.query('SELECT char_id FROM vh_racha_profiles WHERE nickname = ? LIMIT 1', { nickname })
  return rows[1] and tonumber(rows[1].char_id) or nil
end

-- Cria ou atualiza perfil de piloto.
function S.upsert_profile(char_id, nickname)
  return S.execute([[
    INSERT INTO vh_racha_profiles (char_id, nickname)
    VALUES (?, ?)
    ON DUPLICATE KEY UPDATE nickname = VALUES(nickname)
  ]], { char_id, nickname })
end

-- Insere resultado de corrida.
function S.insert_result(row)
  return S.execute([[
    INSERT INTO vh_racha_results
      (run_id, track_id, char_id, nickname, vehicle_plate, vehicle_model,
       position, duration_ms, checkpoints, status, payout)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      nickname = VALUES(nickname),
      vehicle_plate = VALUES(vehicle_plate),
      vehicle_model = VALUES(vehicle_model),
      position = VALUES(position),
      duration_ms = VALUES(duration_ms),
      checkpoints = VALUES(checkpoints),
      status = VALUES(status),
      payout = VALUES(payout)
  ]], {
    row.run_id, row.track_id, row.char_id, row.nickname or '',
    row.vehicle_plate or '', row.vehicle_model or '',
    row.position, row.duration_ms, row.checkpoints or 0, row.status, row.payout or 0,
  })
end

-- Atualiza recorde agregado apos chegada valida.
function S.record_finish(track_id, char_id, nickname, duration_ms, run_id, position)
  return S.execute([[
    INSERT INTO vh_racha_records
      (track_id, char_id, nickname, best_ms, best_run_id, wins, podiums, finishes, dnfs, total_ms)
    VALUES (?, ?, ?, ?, ?, ?, ?, 1, 0, ?)
    ON DUPLICATE KEY UPDATE
      nickname = VALUES(nickname),
      best_run_id = IF(best_ms IS NULL OR VALUES(best_ms) < best_ms, VALUES(best_run_id), best_run_id),
      best_ms = IF(best_ms IS NULL OR VALUES(best_ms) < best_ms, VALUES(best_ms), best_ms),
      wins = wins + VALUES(wins),
      podiums = podiums + VALUES(podiums),
      finishes = finishes + 1,
      total_ms = total_ms + VALUES(total_ms)
  ]], {
    track_id, char_id, nickname, duration_ms, run_id,
    position == 1 and 1 or 0, position <= 3 and 1 or 0, duration_ms,
  })
end

-- Atualiza agregado de DNF/cancelamento.
function S.record_dnf(track_id, char_id, nickname)
  return S.execute([[
    INSERT INTO vh_racha_records
      (track_id, char_id, nickname, wins, podiums, finishes, dnfs, total_ms)
    VALUES (?, ?, ?, 0, 0, 0, 1, 0)
    ON DUPLICATE KEY UPDATE nickname = VALUES(nickname), dnfs = dnfs + 1
  ]], { track_id, char_id, nickname })
end

-- Ranking especifico da pista.
function S.track_ranking(track_id, limit)
  local lim = math.min(math.max(tonumber(limit) or 20, 1), 100)
  return S.query([[
    SELECT track_id, char_id, nickname, best_ms, wins, podiums, finishes, dnfs, total_ms,
           CASE WHEN finishes > 0 THEN FLOOR(total_ms / finishes) ELSE NULL END AS avg_ms
    FROM vh_racha_records
    WHERE track_id = ? AND best_ms IS NOT NULL
    ORDER BY best_ms ASC, wins DESC, podiums DESC, finishes DESC
    LIMIT ?
  ]], { track_id, lim })
end

-- Ranking geral da liga.
function S.general_ranking(limit)
  local lim = math.min(math.max(tonumber(limit) or 20, 1), 100)
  return S.query([[
    SELECT char_id,
           SUBSTRING_INDEX(GROUP_CONCAT(nickname ORDER BY updated_at DESC), ',', 1) AS nickname,
           SUM(wins) AS wins, SUM(podiums) AS podiums, SUM(finishes) AS finishes,
           SUM(dnfs) AS dnfs, MIN(best_ms) AS best_ms, COUNT(*) AS tracks,
           (SUM(wins) * 100 + SUM(podiums) * 35 + SUM(finishes) * 5 - SUM(dnfs) * 2) AS score
    FROM vh_racha_records
    GROUP BY char_id
    ORDER BY score DESC, wins DESC, podiums DESC, best_ms ASC
    LIMIT ?
  ]], { lim })
end

-- Historico recente de uma pista.
function S.track_history(track_id, limit)
  local lim = math.min(math.max(tonumber(limit) or 30, 1), 100)
  return S.query([[
    SELECT run_id, track_id, char_id, nickname, vehicle_plate, vehicle_model,
           position, duration_ms, status, payout, UNIX_TIMESTAMP(created_at) AS created_unix
    FROM vh_racha_results
    WHERE track_id = ?
    ORDER BY id DESC
    LIMIT ?
  ]], { track_id, lim })
end

-- Historico do piloto.
function S.char_history(char_id, limit)
  local lim = math.min(math.max(tonumber(limit) or 30, 1), 100)
  return S.query([[
    SELECT run_id, track_id, position, duration_ms, status, payout,
           UNIX_TIMESTAMP(created_at) AS created_unix
    FROM vh_racha_results
    WHERE char_id = ?
    ORDER BY id DESC
    LIMIT ?
  ]], { char_id, lim })
end

-- Resultado completo de uma corrida.
function S.run_results(run_id)
  return S.query([[
    SELECT run_id, track_id, char_id, nickname, vehicle_plate, vehicle_model,
           position, duration_ms, checkpoints, status, payout,
           UNIX_TIMESTAMP(created_at) AS created_unix
    FROM vh_racha_results
    WHERE run_id = ?
    ORDER BY COALESCE(position, 9999), id ASC
  ]], { run_id })
end
