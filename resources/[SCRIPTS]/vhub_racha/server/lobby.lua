-- server/lobby.lua — lifecycle do lobby (lobby → pending → warmup → racing).
-- Fluxo novo:
--   1) M.create → instancia em estado 'lobby' (visivel no painel)
--   2) M.join   → jogador entra, paga fee, vai para 'pending' (precisa confirmar na ready-zone)
--   3) M.confirm_presence → jogador confirma estando dentro da ready-zone
--   4) Quando todos confirmam OU host forca start → M.start (warmup countdown)
--   5) Apos countdown → runtime.begin_racing
--
-- Treino (mode=treino): sem fee, sem ranking, solo (min_players=1)

VHubRachaLobby = {}
local L = VHubRachaLobby
local Cfg = VHubRachaCfg
local U   = VHubRachaUtils
local ST  = VHubRachaState
local E   = VHubRachaE
local RW  = VHubRachaRewards
local MA  = VHubRachaMath

local function ms() return GetGameTimer() end

local function user_of(src)
  local B = VHubRachaBoot
  if not B or not B.vHub or not B.vHub.Auth then
    print(('vhub_racha: lobby.user_of(%s) -> nil (no vHub/Auth)'):format(tostring(src)))
    return nil
  end

  local attempts = 20
  local lookup_key = tonumber(src) or src
  for i = 1, attempts do
    local ok, user = pcall(function() return B.vHub.Auth:getUser(lookup_key) end)
    if ok and user then
      if i > 1 then
        print(('vhub_racha: lobby.user_of(%s) -> acquired after %d tries'):format(tostring(src), i))
      end
      return user
    end
    Citizen.Wait(100)
  end

  local sessions = B.vHub.Auth._sessions or {}
  local direct = sessions[lookup_key] or sessions[tostring(lookup_key)] or sessions[tostring(src)]
  if direct then
    print(('vhub_racha: lobby.user_of(%s) -> found via _sessions direct key'):format(tostring(src)))
    return direct
  end

  for k, v in pairs(sessions) do
    if type(v) == 'table' then
      if v.source == src or tostring(v.source) == tostring(src) or tostring(k) == tostring(src) then
        print(('vhub_racha: lobby.user_of(%s) -> found in _sessions by value key=%s'):format(tostring(src), tostring(k)))
        return v
      end
    end
  end

  print(('vhub_racha: lobby.user_of(%s) -> nil after %d attempts and fallbacks'):format(tostring(src), attempts))
  pcall(function()
    local cnt = 0
    for k,_ in pairs(B.vHub.Auth._sessions or {}) do cnt = cnt + 1 end
    print(('vhub_racha: vHub.Auth._sessions count=%d'):format(cnt))
    local i = 0
    for k,_ in pairs(B.vHub.Auth._sessions or {}) do
      i = i + 1
      if i <= 16 then
        print(('vhub_racha: session_key[%d]=%s'):format(i, tostring(k)))
      end
    end
  end)
  return nil
end

local function notify(src, msg, kind)
  if src and src > 0 then TriggerClientEvent(E.NOTIFY, src, msg, kind or 'info') end
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

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

-- Sincroniza estado da instancia para clientes em lobby/pending
-- (para HUD/NUI mostrar contadores corretos)
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
      pending_deadline = inst.pending_deadline or 0,
      ready_zone       = inst.ready_zone,
      starts_at        = inst.starts_at or 0,
    }, true)
  end
end

-- Conta confirmados (precisa estar no estado 'pending' ou 'warmup')
local function count_confirmed(inst)
  local n = 0
  for _, p in pairs(inst.players or {}) do
    if p.confirmed == true then n = n + 1 end
  end
  inst.confirmed_count = n
  return n
end

-- ── Ready Zone (definida no centro do start da pista) ──────────────────────

local function compute_ready_zone(track)
  local cfg = Cfg.READY_ZONE or {}
  local s = track and track.start or { x = 0, y = 0, z = 0 }
  -- track pode definir um override em track.ready_zone
  if track and type(track.ready_zone) == 'table' then
    return {
      x = tonumber(track.ready_zone.x) or s.x,
      y = tonumber(track.ready_zone.y) or s.y,
      z = tonumber(track.ready_zone.z) or s.z,
      radius = tonumber(track.ready_zone.radius) or (cfg.RADIUS_M or 18.0),
      z_tol  = tonumber(track.ready_zone.z_tol) or (cfg.Z_TOLERANCE or 5.0),
    }
  end
  return {
    x = s.x, y = s.y, z = s.z,
    radius = cfg.RADIUS_M or 18.0,
    z_tol  = cfg.Z_TOLERANCE or 5.0,
  }
end

-- ── Create / Join / Leave / Cancel ─────────────────────────────────────────

function L.create(src, payload)
  local user = user_of(src); if not user then return false, 'sem_sessao' end
  local track_id = U.sanitize_id((payload and payload.track_id) or '')
  local track = ST.track(track_id); if not track then return false, 'pista_inexistente' end

  local mode = (payload and payload.mode == 'treino') and 'treino' or 'rankeada'
  if track.kind == 'freerun' then mode = 'treino' end   -- freerun = sempre sem premio

  local entry_fee = U.clamp_int((payload and payload.entry_fee) or track.default_fee or 0,
                                0, Cfg.MAX_ENTRY_FEE)
  if mode == 'treino' or track.kind == 'timeattack' then entry_fee = 0 end

  local laps = U.clamp_int((payload and payload.laps) or track.laps or 1, 1, 10)
  if track.kind == 'freerun' then laps = 0 end

  local cp_total = #(track.checkpoints or {}) * math.max(1, laps)
  local min_players = U.clamp_int((payload and payload.min_players) or track.min_players or 1, 1, 12)
  local max_players = U.clamp_int((payload and payload.max_players) or track.max_players or 8, 1, 12)
  if mode == 'treino' then min_players = 1 end

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
    ready_zone    = compute_ready_zone(track),
  }
  ST.put_instance(inst)
  ST.metrics.instances_created = ST.metrics.instances_created + 1

  -- Auto-join criador
  local ok, data = L.join(src, inst.id)
  if not ok then
    ST.remove_instance(inst.id)
    return false, data
  end

  -- TimeAttack solo: ja inicia direto
  if track.kind == 'timeattack' then
    L.confirm_presence(src, inst.id, true)
    return L.start(inst.id, true)
  end

  return true, { inst_id = inst.id }
end

function L.join(src, inst_id)
  local user = user_of(src); if not user then return false, 'sem_sessao' end
  local inst = ST.instance(inst_id); if not inst then return false, 'instancia_inexistente' end
  if inst.state ~= 'lobby' and inst.state ~= 'pending' then return false, 'lobby_fechado' end
  if inst.players[src] then return false, 'ja_no_lobby' end
  if ST.instance_by_src(src) then return false, 'ja_em_outra_corrida' end
  if ST.count_players(inst) >= (inst.max_players or 8) then return false, 'lobby_cheio' end

  -- Cobra fee
  if (inst.entry_fee or 0) > 0 then
    local paid, err = RW.charge_entry(src, inst.entry_fee, 'racha_join')
    if not paid then return false, 'saldo_insuficiente' end
  end

  -- Aloca grid slot
  local grid_slot = nil
  for i = 1, (inst.max_players or 8) do
    if not inst.grid_used[i] then grid_slot = i; break end
  end
  if not grid_slot then return false, 'sem_grid' end
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

  -- Primeira entrada → entra em estado 'pending' (deadline pra confirmar)
  if inst.state == 'lobby' then
    inst.state = 'pending'
    inst.pending_deadline = ms() + (Cfg.PENDING_TTL_MS or 300000)
    -- Agenda check do deadline
    SetTimeout((Cfg.PENDING_TTL_MS or 300000) + 200, function()
      local i = ST.instance(inst.id)
      if not i or i.state ~= 'pending' then return end
      L._handle_pending_deadline(i)
    end)
  end

  broadcast_lobby_state(inst)
  TriggerClientEvent(E.LOBBY_PENDING, src, {
    inst_id = inst.id,
    ready_zone = inst.ready_zone,
    pending_deadline = inst.pending_deadline,
    mode = inst.mode,
    track_label = inst.label,
  })

  return true, { inst_id = inst.id, grid_slot = grid_slot }
end

function L.leave(src, inst_id)
  local inst = ST.instance(inst_id); if not inst then return false end
  local player = inst.players[src]; if not player then return false end

  -- Devolve fee se ainda nao começou
  if (inst.state == 'lobby' or inst.state == 'pending') and (inst.entry_fee or 0) > 0 then
    RW.refund(src, inst.entry_fee, 'racha_leave')
    inst.pot_total = math.max(0, (inst.pot_total or 0) - inst.entry_fee)
  end

  inst.players[src] = nil
  inst.grid_used[player.grid_slot or 0] = nil
  ST.unbind_src(src)
  Player(src).state:set('vhub_racha', nil, true)

  -- Host saiu antes da corrida → cancela
  if (inst.state == 'lobby' or inst.state == 'pending')
     and player.char_id == inst.creator_char then
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

function L.cancel(inst_id, reason)
  local inst = ST.instance(inst_id); if not inst then return false end
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

-- ── Ready Zone confirmation ────────────────────────────────────────────────

-- Verifica se o jogador esta dentro da ready-zone do lobby
local function in_ready_zone(src, zone)
  if not zone then return false end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false end
  local pos = GetEntityCoords(ped)
  if not pos then return false end
  local dz = math.abs(pos.z - zone.z)
  if dz > (zone.z_tol or 5.0) then return false end
  return MA.point_in_circle(pos.x, pos.y, zone.x, zone.y, zone.radius or 18.0)
end

-- Confirma presenca (cliente pediu via NUI ou [E])
-- force=true ignora verificacao de zona (uso interno para TimeAttack)
function L.confirm_presence(src, inst_id, force)
  local inst = ST.instance(inst_id); if not inst then return false end
  if inst.state ~= 'pending' then return false, 'estado_invalido' end
  local player = inst.players[src]; if not player then return false, 'fora_do_lobby' end
  if player.confirmed then return true end

  if not force and not in_ready_zone(src, inst.ready_zone) then
    return false, 'fora_da_ready_zone'
  end

  player.confirmed = true
  count_confirmed(inst)
  broadcast_lobby_state(inst)
  TriggerClientEvent(E.LOBBY_CONFIRMED, src, { inst_id = inst.id })
  notify(src, 'Presenca confirmada.', 'success')

  -- Todos confirmaram? Inicia direto
  if inst.confirmed_count >= ST.count_players(inst)
     and inst.confirmed_count >= (inst.min_players or 1) then
    L.start(inst.id, false)
  end

  return true
end

-- Deadline da pendencia expirou — remove quem nao confirmou e tenta iniciar
function L._handle_pending_deadline(inst)
  if not inst or inst.state ~= 'pending' then return end
  -- Remove nao-confirmados (devolve fee)
  local kicked = {}
  for src, p in pairs(inst.players) do
    if not p.confirmed then kicked[#kicked + 1] = src end
  end
  for _, src in ipairs(kicked) do
    notify(src, 'Voce nao confirmou a tempo — saiu do lobby.', 'error')
    L.leave(src, inst.id)
  end

  -- Se tem o minimo de confirmados, inicia
  local remaining = ST.count_players(inst)
  if remaining >= (inst.min_players or 1) then
    L.start(inst.id, false)
  else
    L.cancel(inst.id, 'sem_presenca_minima')
  end
end

-- ── Start (warmup countdown) ───────────────────────────────────────────────

function L.start(inst_id, solo)
  local inst = ST.instance(inst_id); if not inst then return false, 'inst_inexistente' end
  if inst.state ~= 'pending' and inst.state ~= 'lobby' then return false, 'estado_invalido' end

  -- Se modo treino: pode comecar com 1
  -- Caso contrario: precisa min_players confirmados
  local n_total = ST.count_players(inst)
  local n_conf  = count_confirmed(inst)
  if not solo and inst.mode ~= 'treino' and n_conf < (inst.min_players or 1) then
    return false, 'jogadores_insuficientes'
  end

  -- Remove nao-confirmados (silencioso, sem fee refund pq agora fica injusto)
  -- Em modo treino, considera todos confirmados automaticamente
  if inst.mode == 'treino' or solo then
    for _, p in pairs(inst.players) do p.confirmed = true end
  else
    local kicked = {}
    for src, p in pairs(inst.players) do
      if not p.confirmed then kicked[#kicked + 1] = src end
    end
    for _, src in ipairs(kicked) do
      L.leave(src, inst.id)
    end
  end

  inst.state = 'warmup'
  inst.starts_at = ms() + (Cfg.COUNTDOWN_MS or 7000)
  inst.started_at = os.time()

  local track = ST.track(inst.track_id)
  for src, p in pairs(inst.players) do
    local grid_slot = (track.grid and track.grid[p.grid_slot]) or track.start
    TriggerClientEvent(E.RACE_PREPARE, src, {
      inst_id    = inst.id,
      track      = track,
      laps       = inst.laps,
      mode       = inst.mode,
      grid_pos   = grid_slot,
      starts_at  = inst.starts_at,
      countdown  = Cfg.COUNTDOWN_MS or 7000,
    })
  end

  -- Agenda transicao para racing
  SetTimeout(Cfg.COUNTDOWN_MS or 7000, function()
    local i = ST.instance(inst_id)
    if not i or i.state ~= 'warmup' then return end
    if VHubRachaRuntime and VHubRachaRuntime.begin_racing then
      VHubRachaRuntime.begin_racing(i)
    end
  end)

  -- Alerta polícia
  if inst.alerts_police and Cfg.POLICE then
    L._police_alert(inst)
  end

  ST.metrics.instances_started = ST.metrics.instances_started + 1
  return true, { inst_id = inst.id }
end

function L._police_alert(inst)
  local B = VHubRachaBoot
  if not B or not B.vHub or not B.vHub.Auth or not B.vHub.Auth._sessions then return end
  local track = ST.track(inst.track_id); if not track or not track.start then return end
  for psrc, _ in pairs(B.vHub.Auth._sessions) do
    local has_perm = false
    pcall(function() has_perm = exports.vhub_groups:hasPermission(psrc, Cfg.POLICE.PERMISSION) end)
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

-- ── GC de lobbies estagnados ────────────────────────────────────────────────

function L.gc_idle()
  local now = ms()
  local ttl = Cfg.LOBBY_TTL_MS or 600000
  for inst_id, inst in pairs(ST._instances) do
    if (inst.state == 'lobby' or inst.state == 'pending')
       and (now - (inst.created_ms or now)) > ttl then
      L.cancel(inst_id, 'lobby_expirou')
    end
  end
  ST.gc_drafts(Cfg.EDITOR_DRAFT_TTL_MS or 1800000)
end

-- Player dropped → trata como leave/abort
function L.on_player_dropped(src)
  local inst = ST.instance_by_src(src); if not inst then return end
  if inst.state == 'lobby' or inst.state == 'pending' then
    L.leave(src, inst.id)
  end
end
