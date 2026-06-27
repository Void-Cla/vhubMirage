-- server/init.lua — wire de todos os modulos via VHubRachaBoot.on_ready.
-- Garante que NADA roda antes do vhub estar pronto (resolve 'ensure manual').

local Cfg = VHubRachaCfg
local U   = VHubRachaUtils
local CP  = VHubRachaCP
local E   = VHubRachaE
local ST  = VHubRachaState
local SQL = VHubRachaSQL
local LB  = VHubRachaLobby
local RT  = VHubRachaRuntime
local ED  = VHubRachaEditor
local R   = VHubRachaRanking
local Lang = VHubRachaLang
local B   = VHubRachaBoot


-- ============================================================
-- ANTI-SPAM — rate-limit por jogador nos eventos NAO-gameplay (PRD: event/packet spam).
-- Gameplay (RACE_CHECKPOINT/TICK) fica de fora: tem validacao/cap proprios em anti_cheat.
-- ============================================================

local _rl = {}   -- [src] = { [tag] = last_ms }

-- true se o jogador disparou `tag` ha menos de window_ms (descarta o evento)
local function rate_limited(src, tag, window_ms)
  local t = _rl[src]; if not t then t = {}; _rl[src] = t end
  local now = GetGameTimer()
  if now - (t[tag] or -1e9) < window_ms then return true end
  t[tag] = now
  return false
end

-- ── Schema + catalogo (roda quando boot ficar ready) ───────────────────────

B.on_ready(function()
  local ok, err = SQL.apply_schema()
  if not ok then
    VHubRachaLog.error('schema falhou: ' .. tostring(err))
    return
  end

  -- Espelha config → SQL (normaliza coords)
  for _, t in ipairs(VHubRachaTracks or {}) do
    local cps  = CP.normalize_list(t.checkpoints, 0)
    local grid = CP.normalize_list(t.grid, t.start and t.start.h or 0)
    local start = CP.normalize(t.start, 0) or (grid[1] or { x = 0, y = 0, z = 0, h = 0 })
    SQL.upsert_track({
      id            = t.id,
      label         = t.label or t.id,
      district      = t.district or '',
      kind          = t.kind or 'sprint',
      creator_char  = 0,
      illegal       = t.illegal,
      alerts_police = t.alerts_police,
      laps          = t.laps or 1,
      min_players   = t.min_players or 1,
      max_players   = t.max_players or #grid,
      vehicle_class = t.vehicle_class or 'car',
      default_fee   = t.default_fee or 0,
      limit_seconds = t.limit_seconds or 300,
      start         = start,
      source        = 'config',
      category      = t.category,   -- categoria fixa da pista (#36; default 'normal')
    })
    SQL.set_checkpoints(t.id, cps)
    SQL.set_grid(t.id, grid)
  end

  -- Carrega catalogo (config + custom)
  ST.set_catalog(SQL.load_catalog())

  local n = 0; for _ in pairs(ST._catalog) do n = n + 1 end
  VHubRachaLog.info('%d pistas carregadas.', n)

  -- Ranqueado: liga o cron de decay (no-op se desligado no config)
  VHubRachaRanked.start_decay_cron()
end, 'schema_catalog')

-- ── Cron GC ────────────────────────────────────────────────────────────────

B.on_ready(function()
  Citizen.CreateThread(function()
    while true do
      Citizen.Wait(30000)
      pcall(LB.gc_idle)
    end
  end)
end, 'cron_gc')

-- ── Lifecycle de player ────────────────────────────────────────────────────

AddEventHandler('playerDropped', function()
  local src = source
  _rl[src] = nil
  if not B.READY then return end
  LB.on_player_dropped(src)
  RT.on_player_dropped(src)
end)

AddEventHandler('vHub:playerDeath', function(user)
  if not B.READY or not user or not user.source then return end
  RT.on_abort(user.source, 'morte')
end)

-- ── Net events ─────────────────────────────────────────────────────────────

-- monta os dados do painel — REUSO: NUI propria do racha E app embutido do iPad
local function build_panel_data()
  local catalog = {}
  for id, t in pairs(ST.catalog()) do
    catalog[#catalog + 1] = {
      id = id, label = t.label, district = t.district, kind = t.kind,
      illegal = t.illegal, alerts_police = t.alerts_police,
      laps = t.laps, min_players = t.min_players, max_players = t.max_players,
      vehicle_class = t.vehicle_class, default_fee = t.default_fee,
      limit_seconds = t.limit_seconds, source = t.source,
      category = t.category or 'normal',
      cps = #(t.checkpoints or {}), color = t.color,
    }
  end
  table.sort(catalog, function(a, b) return a.label < b.label end)

  return {
    catalog = catalog,
    lobbies = ST.public_lobbies(),
    ranking = R.top('sprint', 'time', 10),
    history = R.recent({}, 15),
    cfg = {
      brand_name = Cfg.BRAND_NAME,
      brand_tag  = Cfg.BRAND_TAG,
      max_fee    = Cfg.MAX_ENTRY_FEE,
    },
  }
end

-- NUI_OPEN / openPanel / send_open REMOVIDOS: o painel standalone nao existe
-- mais. O iPad consome `build_panel_data` exclusivamente pelo relay abaixo.

-- relay do APP EMBUTIDO do iPad (broker vhub_ipad). Reusa a lógica do painel
-- (LB.* / R.* / ED.*) e responde pelo push do iPad (appPush). Contrato de 11 ações
-- espelhando o painel /racha. Roda em thread PRÓPRIA: as funções usam Citizen.Await
-- e o yield NÃO pode cruzar a fronteira C do export (senão a corrotina é abandonada).
exports('ipadRelay', function(src, action, data)
  if type(src) ~= 'number' or not GetPlayerName(src) then return false end
  if not B.READY then return false end
  data = (type(data) == 'table') and data or {}

  CreateThread(function()
    local ok, err = pcall(function()
      local inst_id = tostring(data.inst_id or '')

      -- ── painel / lobbies ──────────────────────────────────────
      if action == 'open' or action == 'refresh' then
        exports.vhub_ipad:appPush(src, 'racha', 'data', build_panel_data())

      elseif action == 'create' then
        local cok, cdata = LB.create(src, data)
        if cok then
          TriggerClientEvent(E.NOTIFY, src, 'Lobby criado. Vá ao ponto de largada e confirme.', 'success')
          exports.vhub_ipad:closeIpad(src)   -- vai à largada (totem in-game assume)
        else
          exports.vhub_ipad:appPush(src, 'racha', 'result', { ok = false, kind = 'create', data = cdata })
        end

      elseif action == 'join' then
        local jok, jdata = LB.join(src, inst_id, data.password)
        if jok then
          TriggerClientEvent(E.NOTIFY, src, 'Você entrou. Vá ao ponto de largada e confirme.', 'success')
          exports.vhub_ipad:closeIpad(src)
        else
          exports.vhub_ipad:appPush(src, 'racha', 'result', { ok = false, kind = 'join', data = jdata })
        end

      -- ── consultas (read-only) ─────────────────────────────────
      elseif action == 'ranking' then
        local rows = R.top(tostring(data.kind or 'sprint'), tostring(data.mode or 'wins'), 50)
        exports.vhub_ipad:appPush(src, 'racha', 'ranking', { rows = rows })

      elseif action == 'history' then
        local rows = R.recent(data, 30)
        exports.vhub_ipad:appPush(src, 'racha', 'history', { rows = rows })

      elseif action == 'results' then
        local results = R.results_of(tonumber(data.history_id) or 0)
        exports.vhub_ipad:appPush(src, 'racha', 'results', { results = results })

      elseif action == 'ranked' then
        exports.vhub_ipad:appPush(src, 'racha', 'ranked', { rows = R.ranked_ladder(50) })

      elseif action == 'profile' then
        -- char_id PROPRIO vem da sessao (server-side, nunca do cliente).
        local req_cid = tonumber(data.char_id) or 0
        local user    = VHubRachaSessions.get(src)
        local own_cid = user and tonumber(user.char_id) or 0
        local cid     = (req_cid > 0) and req_cid or own_cid
        -- Anti-enumeracao: perfil de TERCEIRO so se ele ja correu ranqueada.
        if cid > 0 and (cid == own_cid or VHubRachaRanked.has_played(cid)) then
          exports.vhub_ipad:appPush(src, 'racha', 'profile', R.profile_of(cid))
        end

      -- ── editor (in-game, keyboard): abre edição → fecha o iPad ─
      elseif action == 'editor_open' then
        ED.open(src)
        exports.vhub_ipad:closeIpad(src)

      elseif action == 'editor_phase' then
        ED.set_phase(src, tostring(data.phase or 'idle'))

      elseif action == 'editor_discard' then
        ED.discard(src)

      elseif action == 'editor_save' then
        ED.save(src, data)
        exports.vhub_ipad:appPush(src, 'racha', 'data', build_panel_data())
      end
    end)
    if not ok then VHubRachaLog.error('ipadRelay: ' .. tostring(err)) end
  end)

  return true
end)

-- Lobby IN-GAME (bridge `vhub_racha.action` da ready-zone em nui_bridge.lua):
-- confirmar presenca / sair / pedir entrada. Criar e demais fluxos chegam pelo
-- relay do iPad (ipadRelay) — o painel standalone que os disparava foi removido
-- (#36). CANCEL/FORCE_START sairam (sem consumidor in-game).
RegisterNetEvent(E.LOBBY_CONFIRM, function(inst_id)
  if not B.READY then return end
  local src = source
  if rate_limited(src, 'lobby_confirm', 500) then return end
  local ok = LB.confirm_presence(src, inst_id, false)
  if not ok then
    TriggerClientEvent(E.NOTIFY, src, Lang.t('lobby.outside_ready_zone'), 'error')
  end
end)

RegisterNetEvent(E.LOBBY_JOIN, function(inst_id)
  if not B.READY then return end
  local src = source
  if rate_limited(src, 'lobby_join', 800) then return end
  -- Lobby protegido por senha so entra pelo iPad (que coleta a senha); o bridge
  -- in-game junta sem senha (fluxo de lobby aberto).
  local ok, data = LB.join(src, inst_id)
  TriggerClientEvent(E.NOTIFY, src, ok and 'Voce entrou no lobby.' or
    ('Falha ao entrar: %s'):format(tostring(data)), ok and 'success' or 'error')
end)

RegisterNetEvent(E.LOBBY_LEAVE, function(inst_id)
  if not B.READY then return end
  local src = source
  if rate_limited(src, 'lobby_leave', 500) then return end
  LB.leave(src, inst_id)
  TriggerClientEvent(E.NOTIFY, src, 'Voce saiu do lobby.', 'info')
end)

-- Race
RegisterNetEvent(E.RACE_CHECKPOINT, function(payload)
  if not B.READY then return end
  RT.on_checkpoint(source, payload or {})
end)

RegisterNetEvent(E.RACE_TICK, function(payload)
  if not B.READY then return end
  RT.on_tick(source, payload or {})
end)

RegisterNetEvent(E.RACE_ABORT, function(reason)
  if not B.READY then return end
  RT.on_abort(source, tostring(reason or 'manual'))
end)

-- NUI queries (ranking/history/results/ranked/profile) REMOVIDAS: todas chegam
-- pelo relay do iPad (ipadRelay → R.*). A anti-enumeracao do perfil de terceiro
-- (Ranked.has_played) vive agora no ramo 'profile' do ipadRelay.

-- Editor IN-GAME (keyboard). O start/save/discard vem pelo iPad (ipadRelay).
RegisterNetEvent(E.EDITOR_PHASE,   function(p)
  if B.READY then ED.set_phase(source, (p and p.phase) or 'idle') end
end)
RegisterNetEvent(E.EDITOR_ADD_GRID,function() if B.READY then ED.add_grid(source) end end)
RegisterNetEvent(E.EDITOR_ADD_CP,  function() if B.READY then ED.add_cp(source) end end)
RegisterNetEvent(E.EDITOR_UNDO,    function() if B.READY then ED.undo(source) end end)
-- EDITOR_SAVE / EDITOR_DISCARD chegam pelo iPad (ipadRelay editor_save/discard).

-- ── Comandos ────────────────────────────────────────────────────────────────

-- /racha (painel) REMOVIDO: o painel abre exclusivamente pelo iPad (ipadRelay).
-- Mantidos abaixo apenas comandos de GAMEPLAY in-game (treino) e debug do editor.

-- /racha_treino <track_id> → cria lobby treino e abre o totem.
-- Treino e FIEL ao ranqueado: player vai ate o totem e aperta [E] para confirmar.
-- Diferenças do ranqueado: sem fee, sem recompensa, min_players=1 (solo).
RegisterCommand(Cfg.CMD_TRAINING, function(src, args)
  if src <= 0 then return end
  if not B.READY then return end
  local track_id = U.sanitize_id(args[1] or '')
  if track_id == '' then
    TriggerClientEvent(E.NOTIFY, src,
      ('Uso: /%s <track_id>'):format(Cfg.CMD_TRAINING), 'info')
    return
  end
  local ok, data = LB.create(src, { track_id = track_id, mode = 'treino' })
  if not ok then
    TriggerClientEvent(E.NOTIFY, src, ('Falha: %s'):format(tostring(data)), 'error')
  end
end, false)

-- Editor backup (caso NUI esteja com problema)
RegisterCommand(Cfg.CMD_EDITOR_DEBUG, function(src, args)
  if src <= 0 then return end
  if not B.READY then return end
  local sub = tostring(args[1] or '')
  if sub == 'add_grid' then ED.add_grid(src)
  elseif sub == 'add_cp' then ED.add_cp(src)
  elseif sub == 'undo' then ED.undo(src)
  elseif sub == 'discard' then ED.discard(src)
  else ED.open(src) end
end, false)

RegisterCommand('vhub_racha_status', function(src)
  if src ~= 0 then return end
  local s = ST.status_snapshot()
  VHubRachaLog.info('ready=%s tracks=%d lobbies=%d pending=%d racing=%d drafts=%d',
    tostring(B.READY), s.catalog_size, s.lobbies, s.pending, s.racing, s.drafts)
end, true)
