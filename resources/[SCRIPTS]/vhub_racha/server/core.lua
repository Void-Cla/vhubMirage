-- server/core.lua - dominio autoritativo de corridas do vhub_racha.

VHubRachaCore = {
  _vHub = nil, _ready = false, _lobbies = {}, _active_by_src = {}, _rate = {},
  metrics = { created = 0, started = 0, finished = 0, cancelled = 0, dnf = 0 },
}

local Core, SQL, Cfg, E, U = VHubRachaCore, VHubRachaSQL, VHubRachaCfg, VHubRachaE, VHubRachaUtils

local function now_ms() return GetGameTimer() end
local function notify(src, msg, kind) TriggerClientEvent(E.NOTIFY, src, { msg = tostring(msg or ''), kind = kind or 'info' }) end

local function rate_ok(src, key, interval_ms)
  local n, k = now_ms(), tostring(src) .. ':' .. tostring(key)
  if n - (Core._rate[k] or 0) < interval_ms then return false end
  Core._rate[k] = n
  return true
end

local function user_of(src)
  if not Core._vHub or not Core._vHub.Auth then return nil end
  return Core._vHub.Auth:getUser(tonumber(src) or 0)
end

local function has_admin(src)
  local user = user_of(src)
  if user and user.char_id == Cfg.OWNER_CHAR_ID then return true end
  if IsPlayerAceAllowed(src, Cfg.ADMIN_ACE) then return true end
  local ok, allowed = pcall(function() return exports.vhub_groups:hasPermission(src, Cfg.ADMIN_PERMISSION) end)
  return ok and allowed == true
end

local function ped_coords(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  return GetEntityCoords(ped)
end

local function distance_to(src, point)
  local c = ped_coords(src)
  if not c or not point then return math.huge end
  local dx, dy, dz = c.x - point.x, c.y - point.y, c.z - point.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function driver_vehicle(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil, 'ped_invalido' end
  if type(GetVehiclePedIsIn) ~= 'function' then return nil, 'native_indisponivel' end
  local veh = GetVehiclePedIsIn(ped, false)
  if not veh or veh == 0 then return nil, 'fora_do_veiculo' end
  if type(GetPedInVehicleSeat) == 'function' and GetPedInVehicleSeat(veh, -1) ~= ped then return nil, 'nao_motorista' end
  return veh, nil
end

local function vehicle_meta(src, client_meta)
  local veh, veh_err = driver_vehicle(src)
  if not veh then return nil, veh_err end
  if type(GetVehicleClass) ~= 'function' then return nil, 'native_indisponivel' end

  local meta = type(client_meta) == 'table' and client_meta or {}
  local out = {
    plate = tostring(meta.plate or ''):gsub('[^%w%s%-]', ''):sub(1, 12),
    model = tostring(meta.model or ''):gsub('[^%w_%-]', ''):sub(1, 32),
    class = -1,
  }
  local ok_class, class = pcall(GetVehicleClass, veh)
  if not ok_class then return nil, 'veiculo_invalido' end
  out.class = tonumber(class) or -1
  if veh and type(GetVehicleNumberPlateText) == 'function' then local ok, v = pcall(GetVehicleNumberPlateText, veh); if ok and v then out.plate = tostring(v):gsub('[^%w%s%-]', ''):sub(1, 12) end end
  if veh and type(GetEntityModel) == 'function' then local ok, v = pcall(GetEntityModel, veh); if ok and v then out.model = tostring(v):sub(1, 32) end end
  return out
end

local function money_export(name, src, amount, reason)
  amount = math.max(0, tonumber(amount) or 0)
  if amount <= 0 then return true end
  local ok, a, b = pcall(function()
    if name == 'tryFullPayment' then return exports.vhub_money:tryFullPayment(src, amount) end
    if name == 'giveBank' then return exports.vhub_money:giveBank(src, amount, reason) end
    return false, 'money_export_unsupported'
  end)
  if not ok then return false, 'money_export_failed' end
  if a == false then return false, b or 'money_denied' end
  return true
end

local function ensure_profile(src, char_id)
  local row = SQL.get_profile(char_id)
  if row and row.nickname and row.nickname ~= '' then return row.nickname end
  local ok, full = pcall(function() return exports.vhub_identity:getFullName(src) end)
  local base = ok and U.sanitize_nick(full) or ''
  if base == '' then base = 'Piloto ' .. tostring(char_id) end
  for i = 0, 20 do
    local nick = i == 0 and base:sub(1, 24) or (base:sub(1, 20) .. tostring(i))
    local owner = SQL.find_nickname(nick)
    if not owner or owner == char_id then SQL.upsert_profile(char_id, nick); return nick end
  end
  local nick = ('Piloto %d'):format(char_id)
  SQL.upsert_profile(char_id, nick)
  return nick
end

local function count_participants(lobby)
  local n = 0
  for _ in pairs(lobby.participants) do n = n + 1 end
  return n
end

local function terminal(status)
  return status == 'finished' or status == 'dnf' or status == 'left' or status == 'timeout' or status == 'cancelled'
end

local function standings(lobby)
  local rows = {}
  for _, p in pairs(lobby.participants) do
    rows[#rows + 1] = {
      src = p.src, char_id = p.char_id, nickname = p.nickname, status = p.status,
      position = p.position, progress = p.progress or 0, lap = p.lap or 1,
      checkpoint = p.next_checkpoint or 1, duration_ms = p.duration_ms,
      last_ms = p.last_checkpoint_ms or 0,
    }
  end
  table.sort(rows, function(a, b)
    if a.status == 'finished' and b.status == 'finished' then return (a.position or 9999) < (b.position or 9999) end
    if a.status == 'finished' then return true end
    if b.status == 'finished' then return false end
    if a.progress == b.progress then return (a.last_ms or 0) < (b.last_ms or 0) end
    return (a.progress or 0) > (b.progress or 0)
  end)
  for i, row in ipairs(rows) do row.live_position = i end
  return rows
end

local function public_lobby(lobby)
  return lobby and {
    run_id = lobby.run_id, track_id = lobby.track_id, state = lobby.state,
    organizer_char_id = lobby.organizer_char_id, organizer_nickname = lobby.organizer_nickname,
    entry_fee = lobby.entry_fee, prize_pool = lobby.prize_pool, laps = lobby.laps, ranked = lobby.ranked,
    participant_count = count_participants(lobby), min_players = lobby.track.min_players or 1,
    max_players = lobby.track.max_players or #(lobby.track.grid or {}), standings = standings(lobby),
  } or nil
end

local function public_lobbies()
  local out = {}
  for _, lobby in pairs(Core._lobbies) do out[#out + 1] = public_lobby(lobby) end
  table.sort(out, function(a, b) return a.run_id < b.run_id end)
  return out
end

local function broadcast_lobby(lobby)
  local payload = public_lobby(lobby)
  for _, p in pairs(lobby.participants) do if p.src and p.src > 0 then TriggerClientEvent(E.NUI_REFRESH, p.src, { lobby = payload }) end end
end

local function broadcast_progress(lobby)
  local payload = { run_id = lobby.run_id, standings = standings(lobby) }
  for _, p in pairs(lobby.participants) do if p.src and p.src > 0 then TriggerClientEvent(E.RACE_PROGRESS, p.src, payload) end end
end

local function payout_for(lobby, position)
  if lobby.entry_fee <= 0 or lobby.prize_pool <= 0 then return 0 end
  if count_participants(lobby) == 1 then return math.floor(lobby.prize_pool * Cfg.SINGLE_PAYOUT) end
  return math.floor(lobby.prize_pool * (Cfg.PAYOUT[position] or 0))
end

local function finish_if_done(lobby)
  for _, p in pairs(lobby.participants) do if not terminal(p.status) then return false end end
  lobby.state = 'finished'
  SQL.update_run(lobby.run_id, 'finished', count_participants(lobby), lobby.prize_pool, false, true)
  Core.metrics.finished = Core.metrics.finished + 1
  Citizen.SetTimeout(15000, function() if Core._lobbies[lobby.track_id] == lobby then Core._lobbies[lobby.track_id] = nil end end)
  return true
end

-- Define a referencia do core vHub.
function Core.set_vhub(vh) Core._vHub = vh end

-- Retorna se o resource esta pronto.
function Core.is_ready() return Core._ready == true end

-- Marca o resource como pronto.
function Core.mark_ready() Core._ready = true end

-- Retorna snapshot operacional.
function Core.status()
  return { ready = Core._ready, sql_ready = SQL.ready, lobbies = public_lobbies(), metrics = Core.metrics }
end

-- Abre painel com catalogo, lobby, ranking e historico.
function Core.open_panel(src, context_track_id)
  if not Core.is_ready() then return end
  local user = user_of(src)
  if not user or not user.char_id then return end
  Citizen.CreateThread(function()
    local track = U.track_by_id(context_track_id or '') or VHubRachaTracks[1]
    local profile = SQL.get_profile(user.char_id)
    TriggerClientEvent(E.NUI_OPENED, src, {
      brand = { name = Cfg.BRAND_NAME, tag = Cfg.BRAND_TAG },
      tracks = U.public_tracks(), lobbies = public_lobbies(),
      selected_track_id = track and track.id or nil,
      selected = track and { ranking = SQL.track_ranking(track.id, 20), history = SQL.track_history(track.id, 30) } or nil,
      general = SQL.general_ranking(20), my_history = SQL.char_history(user.char_id, 30),
      profile = { char_id = user.char_id, nickname = profile and profile.nickname or ensure_profile(src, user.char_id) },
      admin = has_admin(src),
    })
  end)
end

-- Atualiza apelido do piloto.
function Core.set_nickname(src, nickname)
  if not rate_ok(src, 'nick', 2000) then return false, 'rate_limited' end
  local user = user_of(src)
  if not user or not user.char_id then return false, 'sem_personagem' end
  local nick = U.sanitize_nick(nickname)
  if #nick < 3 then return false, 'apelido_invalido' end
  local owner = SQL.find_nickname(nick)
  if owner and owner ~= user.char_id then return false, 'apelido_em_uso' end
  SQL.upsert_profile(user.char_id, nick)
  return true, nick
end

-- Cria lobby de corrida e cobra entrada do organizador.
function Core.create_lobby(src, payload)
  if not rate_ok(src, 'create', 1500) then return false, 'rate_limited' end
  local user = user_of(src)
  if not user or not user.char_id then return false, 'sem_personagem' end
  if Core._active_by_src[src] then return false, 'ja_em_corrida' end
  payload = type(payload) == 'table' and payload or {}
  local track = U.track_by_id(payload.track_id)
  if not track then return false, 'pista_invalida' end
  if Core._lobbies[track.id] then return false, 'pista_ocupada' end
  if distance_to(src, track.start) > Cfg.INTERACT_RADIUS + 8.0 then return false, 'longe_da_largada' end
  local veh, veh_err = vehicle_meta(src, payload.vehicle)
  if not veh then return false, veh_err or 'veiculo_invalido' end
  if not U.vehicle_allowed(track, veh.class) then return false, 'veiculo_invalido' end

  local fee = U.clamp_int(payload.entry_fee or track.default_fee or Cfg.DEFAULT_ENTRY_FEE, 0, Cfg.MAX_ENTRY_FEE)
  local laps = U.clamp_int(payload.laps or track.laps or Cfg.DEFAULT_LAPS, 1, Cfg.MAX_LAPS)
  local paid, err = money_export('tryFullPayment', src, fee, nil)
  if not paid then return false, err or 'sem_saldo' end
  local run_id = SQL.create_run(track.id, user.char_id, fee, laps, payload.ranked ~= false)
  if not run_id or run_id <= 0 then money_export('giveBank', src, fee, 'racha_refund'); return false, 'sql_falhou' end

  local nick = ensure_profile(src, user.char_id)
  local lobby = {
    run_id = run_id, track_id = track.id, track = track, state = 'open',
    organizer_src = src, organizer_char_id = user.char_id, organizer_nickname = nick,
    entry_fee = fee, prize_pool = fee, laps = laps, ranked = payload.ranked ~= false,
    created_ms = now_ms(), participants = {}, order = {}, finish_count = 0,
  }
  lobby.participants[src] = {
    src = src, char_id = user.char_id, nickname = nick,
    token = ('%d:%d:%d'):format(run_id, user.char_id, math.random(100000, 999999)),
    slot = 1, status = 'open', paid_fee = fee, vehicle = veh, lap = 1,
    next_checkpoint = 1, progress = 0, checkpoints = 0,
  }
  lobby.order[1] = src
  Core._lobbies[track.id], Core._active_by_src[src] = lobby, track.id
  Core.metrics.created = Core.metrics.created + 1
  SQL.update_run(run_id, 'open', 1, fee, false, false)
  broadcast_lobby(lobby)
  return true, public_lobby(lobby)
end

-- Entra em lobby aberto.
function Core.join_lobby(src, payload)
  if not rate_ok(src, 'join', 1200) then return false, 'rate_limited' end
  local user = user_of(src)
  if not user or not user.char_id then return false, 'sem_personagem' end
  if Core._active_by_src[src] then return false, 'ja_em_corrida' end
  payload = type(payload) == 'table' and payload or {}
  local track = U.track_by_id(payload.track_id)
  local lobby = track and Core._lobbies[track.id] or nil
  if not lobby or lobby.state ~= 'open' then return false, 'lobby_indisponivel' end
  if count_participants(lobby) >= (track.max_players or #(track.grid or {})) then return false, 'sem_vaga' end
  if distance_to(src, track.start) > Cfg.INTERACT_RADIUS + 10.0 then return false, 'longe_da_largada' end
  local veh, veh_err = vehicle_meta(src, payload.vehicle)
  if not veh then return false, veh_err or 'veiculo_invalido' end
  if not U.vehicle_allowed(track, veh.class) then return false, 'veiculo_invalido' end
  local paid, err = money_export('tryFullPayment', src, lobby.entry_fee, nil)
  if not paid then return false, err or 'sem_saldo' end
  local nick, slot = ensure_profile(src, user.char_id), #lobby.order + 1
  lobby.participants[src] = {
    src = src, char_id = user.char_id, nickname = nick,
    token = ('%d:%d:%d'):format(lobby.run_id, user.char_id, math.random(100000, 999999)),
    slot = slot, status = 'open', paid_fee = lobby.entry_fee, vehicle = veh,
    lap = 1, next_checkpoint = 1, progress = 0, checkpoints = 0,
  }
  lobby.order[slot] = src
  lobby.prize_pool = lobby.prize_pool + lobby.entry_fee
  Core._active_by_src[src] = track.id
  SQL.update_run(lobby.run_id, 'open', count_participants(lobby), lobby.prize_pool, false, false)
  broadcast_lobby(lobby)
  return true, public_lobby(lobby)
end

-- Inicia countdown da corrida.
function Core.start_lobby(src, payload)
  if not rate_ok(src, 'start', 1200) then return false, 'rate_limited' end
  local track_id = U.sanitize_id(type(payload) == 'table' and payload.track_id or Core._active_by_src[src] or '')
  local lobby = Core._lobbies[track_id]
  if not lobby or lobby.state ~= 'open' then return false, 'lobby_indisponivel' end
  local user = user_of(src)
  if not user or (user.char_id ~= lobby.organizer_char_id and not has_admin(src)) then return false, 'sem_autoridade' end
  if count_participants(lobby) < (lobby.track.min_players or 1) then return false, 'corredores_insuficientes' end
  lobby.state = 'countdown'
  SQL.update_run(lobby.run_id, 'countdown', count_participants(lobby), lobby.prize_pool, false, false)
  local track_public = U.public_track(lobby.track)
  for i, psrc in ipairs(lobby.order) do
    local p = lobby.participants[psrc]
    if p then
      p.status, p.slot = 'countdown', i
      TriggerClientEvent(E.RACE_PREPARE, p.src, { run_id = lobby.run_id, token = p.token, slot = i, grid = lobby.track.grid[i] or lobby.track.start, countdown_ms = Cfg.COUNTDOWN_MS, track = track_public, laps = lobby.laps })
    end
  end
  broadcast_lobby(lobby)
  Citizen.SetTimeout(Cfg.COUNTDOWN_MS, function() Core.begin_race(track_id, lobby.run_id) end)
  return true, public_lobby(lobby)
end

-- Comeca a corrida apos countdown.
function Core.begin_race(track_id, run_id)
  local lobby = Core._lobbies[track_id]
  if not lobby or lobby.run_id ~= run_id or lobby.state ~= 'countdown' then return false end
  lobby.state, lobby.start_ms = 'running', now_ms()
  lobby.deadline_ms = lobby.start_ms + ((lobby.track.limit_seconds or 300) * 1000) + Cfg.FINISH_GRACE_MS
  SQL.update_run(lobby.run_id, 'running', count_participants(lobby), lobby.prize_pool, true, false)
  for _, p in pairs(lobby.participants) do
    if not terminal(p.status) then
      p.status, p.start_ms, p.last_checkpoint_ms = 'running', lobby.start_ms, lobby.start_ms
      p.lap, p.next_checkpoint, p.progress, p.checkpoints = 1, 1, 0, 0
      TriggerClientEvent(E.RACE_START, p.src, {
        run_id = lobby.run_id, token = p.token, track = U.public_track(lobby.track),
        laps = lobby.laps, self = { src = p.src, char_id = p.char_id }, standings = standings(lobby),
      })
    end
  end
  Core.metrics.started = Core.metrics.started + 1
  Core.alert_police(lobby.track)
  broadcast_progress(lobby)
  return true
end

-- Processa checkpoint validado pelo servidor.
function Core.checkpoint(src, payload)
  if not rate_ok(src, 'checkpoint', 350) then return end
  local lobby = Core._lobbies[Core._active_by_src[src] or '']
  if not lobby or lobby.state ~= 'running' then return end
  local p = lobby.participants[src]
  if not p or p.status ~= 'running' or tostring((payload or {}).token or '') ~= p.token then return end
  local n = now_ms()
  if n - (p.last_checkpoint_ms or 0) < Cfg.MIN_CHECKPOINT_MS then return end
  local point = lobby.track.checkpoints[p.next_checkpoint]
  if not point or distance_to(src, point) > ((lobby.track.checkpoint_radius or Cfg.CHECKPOINT_RADIUS) + Cfg.SERVER_TOLERANCE) then return end
  p.last_checkpoint_ms, p.checkpoints = n, (p.checkpoints or 0) + 1
  p.progress = p.checkpoints
  if p.next_checkpoint >= #(lobby.track.checkpoints or {}) then
    if p.lap >= lobby.laps then return Core.finish_participant(lobby, p, 'finished') end
    p.lap, p.next_checkpoint = p.lap + 1, 1
  else
    p.next_checkpoint = p.next_checkpoint + 1
  end
  TriggerClientEvent(E.RACE_CHECKPOINT, src, {
    run_id = lobby.run_id, token = p.token, lap = p.lap, next_checkpoint = p.next_checkpoint,
    progress = p.progress, self = { src = p.src, char_id = p.char_id }, standings = standings(lobby),
  })
  broadcast_progress(lobby)
end

-- Finaliza participante e persiste resultado.
function Core.finish_participant(lobby, p, status)
  if not lobby or not p or terminal(p.status) then return end
  local n = now_ms()
  p.status, p.position, p.payout = status or 'finished', nil, 0
  p.duration_ms = p.status == 'finished' and math.max(0, n - (p.start_ms or lobby.start_ms or n)) or nil
  if p.status == 'finished' then
    lobby.finish_count = (lobby.finish_count or 0) + 1
    p.position = lobby.finish_count
    p.payout = payout_for(lobby, p.position)
    money_export('giveBank', p.src, p.payout, 'racha_premio')
    if lobby.ranked then SQL.record_finish(lobby.track_id, p.char_id, p.nickname, p.duration_ms, lobby.run_id, p.position) end
  elseif lobby.ranked then
    SQL.record_dnf(lobby.track_id, p.char_id, p.nickname)
    Core.metrics.dnf = Core.metrics.dnf + 1
  end
  SQL.insert_result({ run_id = lobby.run_id, track_id = lobby.track_id, char_id = p.char_id, nickname = p.nickname, vehicle_plate = p.vehicle and p.vehicle.plate or '', vehicle_model = p.vehicle and p.vehicle.model or '', position = p.position, duration_ms = p.duration_ms, checkpoints = p.checkpoints, status = p.status, payout = p.payout })
  Core._active_by_src[p.src] = nil
  TriggerClientEvent(E.RACE_FINISH, p.src, { run_id = lobby.run_id, status = p.status, position = p.position, duration_ms = p.duration_ms, payout = p.payout, standings = standings(lobby) })
  broadcast_progress(lobby)
  finish_if_done(lobby)
end

-- Sai da corrida ou cancela lobby aberto se for organizador.
function Core.leave(src, reason)
  local lobby = Core._lobbies[Core._active_by_src[src] or '']
  local p = lobby and lobby.participants[src]
  if not lobby or not p then return false, 'nao_participa' end
  if lobby.state == 'open' then
    if p.char_id == lobby.organizer_char_id then return Core.cancel_lobby(src, { track_id = lobby.track_id }) end
    money_export('giveBank', src, p.paid_fee, 'racha_refund')
    lobby.participants[src], Core._active_by_src[src] = nil, nil
    for i = #lobby.order, 1, -1 do if lobby.order[i] == src then table.remove(lobby.order, i) end end
    lobby.prize_pool = math.max(0, lobby.prize_pool - (p.paid_fee or 0))
    SQL.update_run(lobby.run_id, 'open', count_participants(lobby), lobby.prize_pool, false, false)
    broadcast_lobby(lobby)
    return true
  end
  Core.finish_participant(lobby, p, reason or 'left')
  return true
end

-- Cancela lobby antes da largada.
function Core.cancel_lobby(src, payload)
  local track_id = U.sanitize_id(type(payload) == 'table' and payload.track_id or Core._active_by_src[src] or '')
  local lobby = Core._lobbies[track_id]
  if not lobby then return false, 'lobby_inexistente' end
  local user = user_of(src)
  if not user or (user.char_id ~= lobby.organizer_char_id and not has_admin(src)) then return false, 'sem_autoridade' end
  if lobby.state ~= 'open' and lobby.state ~= 'countdown' then return false, 'ja_iniciada' end
  for _, p in pairs(lobby.participants) do
    money_export('giveBank', p.src, p.paid_fee, 'racha_refund')
    p.status, Core._active_by_src[p.src] = 'cancelled', nil
    SQL.insert_result({ run_id = lobby.run_id, track_id = lobby.track_id, char_id = p.char_id, nickname = p.nickname, vehicle_plate = p.vehicle and p.vehicle.plate or '', vehicle_model = p.vehicle and p.vehicle.model or '', checkpoints = p.checkpoints or 0, status = 'cancelled', payout = 0 })
    TriggerClientEvent(E.RACE_ABORT, p.src, { reason = 'cancelada' })
  end
  SQL.update_run(lobby.run_id, 'cancelled', count_participants(lobby), lobby.prize_pool, false, true)
  Core._lobbies[track_id] = nil
  Core.metrics.cancelled = Core.metrics.cancelled + 1
  return true
end

-- Remove participante ao desconectar.
function Core.drop_src(src)
  local lobby = Core._lobbies[Core._active_by_src[src] or '']
  local p = lobby and lobby.participants[src]
  if not lobby or not p then Core._active_by_src[src] = nil; return end
  if lobby.state == 'open' then
    if p.char_id == lobby.organizer_char_id then
      for _, row in pairs(lobby.participants) do
        money_export('giveBank', row.src, row.paid_fee, 'racha_refund')
        Core._active_by_src[row.src] = nil
        if row.src and row.src > 0 then TriggerClientEvent(E.RACE_ABORT, row.src, { reason = 'organizador_saiu' }) end
      end
      SQL.update_run(lobby.run_id, 'cancelled', count_participants(lobby), lobby.prize_pool, false, true)
      Core._lobbies[lobby.track_id] = nil
    else
      money_export('giveBank', src, p.paid_fee, 'racha_refund')
      lobby.participants[src], Core._active_by_src[src] = nil, nil
      for i = #lobby.order, 1, -1 do if lobby.order[i] == src then table.remove(lobby.order, i) end end
      lobby.prize_pool = math.max(0, lobby.prize_pool - (p.paid_fee or 0))
      SQL.update_run(lobby.run_id, 'open', count_participants(lobby), lobby.prize_pool, false, false)
    end
    return
  end
  Core.finish_participant(lobby, p, 'dnf')
end

-- Expira lobbies abertos e corridas estouradas.
function Core.tick()
  local n = now_ms()
  for track_id, lobby in pairs(Core._lobbies) do
    if lobby.state == 'open' and n - lobby.created_ms > Cfg.LOBBY_TTL_MS then
      for _, p in pairs(lobby.participants) do money_export('giveBank', p.src, p.paid_fee, 'racha_refund'); Core._active_by_src[p.src] = nil; TriggerClientEvent(E.RACE_ABORT, p.src, { reason = 'lobby_expirado' }) end
      SQL.update_run(lobby.run_id, 'expired', count_participants(lobby), lobby.prize_pool, false, true)
      Core._lobbies[track_id] = nil
    elseif lobby.state == 'running' and n > (lobby.deadline_ms or n + 1) then
      for _, p in pairs(lobby.participants) do if p.status == 'running' then Core.finish_participant(lobby, p, 'timeout') end end
    end
  end
end

-- Envia alerta simples para jogadores com permissao policial.
function Core.alert_police(track)
  if not track or track.illegal ~= true then return end
  local ok, cops = pcall(function() return exports.vhub_groups:getUsersByPermission(Cfg.POLICE_PERMISSION) end)
  if not ok or type(cops) ~= 'table' then return end
  for _, src in ipairs(cops) do notify(src, ('Denuncia anonima: racha em %s.'):format(track.district or track.label or 'local desconhecido'), 'warn') end
end
