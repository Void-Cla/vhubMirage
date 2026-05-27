-- client/nui_bridge.lua - ponte oficial entre corrida local/state bag e NUI.
-- NUI desenha. Servidor autoriza estado. Cliente calcula apenas telemetria visual.

local Cfg = VHubRachaCfg
local E   = VHubRachaE
local V   = VHubRachaVeh
local L   = VHubRachaLocal

local TELEMETRY_INTERVAL = 250
local last_bag_json = nil
local last_telemetry_ms = 0
local local_started_ms = 0

VHubRachaNui = VHubRachaNui or {
  ready = false,
  ready_at = 0,
}

local function enabled()
  return Cfg and Cfg.HUD and Cfg.HUD.USE_NUI == true
end

local function nui(action, data)
  if enabled() then SendNUIMessage({ action = action, data = data or {} }) end
end

local function bridge(kind, payload)
  if enabled() then SendNUIMessage({ type = kind, payload = payload or {} }) end
end

local function encode(v)
  local ok, out = pcall(function() return json.encode(v or {}) end)
  return ok and out or ''
end

local function send_bag_if_changed(bag)
  local j = encode(bag or {})
  if j == last_bag_json then return end
  last_bag_json = j
  if enabled() then SendNUIMessage({ type = 'vhub_racha.bag_update', bag = bag or {} }) end
end

local function next_cp(active)
  if not active or not active.track or type(active.track.checkpoints) ~= 'table' then return nil end
  local cps = active.track.checkpoints
  if #cps == 0 then return nil end
  local idx = ((math.max(1, tonumber(active.cp_index) or 1) - 1) % #cps) + 1
  return cps[idx], idx, #cps
end

local function cp_telemetry(active)
  local cp = next_cp(active)
  if not cp then return nil, nil end

  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  local dx, dy = cp.x - pos.x, cp.y - pos.y
  local dist = math.sqrt(dx * dx + dy * dy)

  return dist
end

local function speed_kmh()
  local ped = PlayerPedId()
  local veh = V and V.ped_vehicle and V.ped_vehicle(ped) or 0
  if veh == 0 then return 0 end
  return math.max(0, math.floor(V.speed_kmh(veh) or 0))
end

RegisterNetEvent(E.RACE_PREPARE, function(payload)
  if not enabled() or type(payload) ~= 'table' then return end
  local track = payload.track or {}
  local cp_total = #(track.checkpoints or {}) * (tonumber(payload.laps) or tonumber(track.laps) or 1)
  nui('hud_show', {
    cps_total = cp_total > 0 and cp_total or 1,
    laps_total = tonumber(payload.laps) or tonumber(track.laps) or 1,
    players_total = tonumber(payload.players_total) or 0,
    mode = payload.mode or 'rankeada',
  })
  nui('hud_countdown', { seconds = math.max(1, math.ceil((tonumber(payload.countdown) or Cfg.COUNTDOWN_MS or 7000) / 1000)) })
end)

RegisterNetEvent(E.RACE_START, function(_payload)
  if not enabled() then return end
  local_started_ms = GetGameTimer()
  nui('hud_start', { elapsed_ms = 0, _local = true, _force = true })
end)

RegisterNetEvent(E.RACE_FINISH, function(payload)
  if not enabled() then return end
  nui('hud_finish', payload or {})
  local_started_ms = 0
end)

RegisterNetEvent(E.RACE_ABORT, function(_reason)
  if not enabled() then return end
  nui('hud_hide', {})
  local_started_ms = 0
end)

AddEventHandler('vhub_racha:local:bag_update', function(bag)
  if not enabled() then return end
  send_bag_if_changed(bag or {})
end)

CreateThread(function()
  while true do
    Wait(TELEMETRY_INTERVAL)
    if enabled() then
      local active = L and L.active_race and L.active_race() or nil
      local bag = L and L.bag or {}
      if active and not active.aborted and not active.finished then
        local now = GetGameTimer()
        if now - last_telemetry_ms >= TELEMETRY_INTERVAL then
          last_telemetry_ms = now

          local dist = cp_telemetry(active)
          local started = local_started_ms > 0 and local_started_ms or now
          local cp_total = tonumber(active.cp_total) or tonumber(bag.cp_total) or 0
          local cp_next = tonumber(active.cp_index) or ((tonumber(bag.cp_done) or 0) + 1)

          bridge('vhub_racha.telemetry', {
            state = bag.state or (active.started_ms and active.started_ms > 0 and 'racing' or 'warmup'),
            elapsed_ms = local_started_ms > 0 and math.max(0, now - started) or 0,
            speed_kmh = speed_kmh(),
            cp_index = cp_next,
            cp_total = cp_total,
            cp_done = tonumber(bag.cp_done) or math.max(0, cp_next - 1),
            lap = tonumber(bag.lap) or 1,
            laps = tonumber(active.laps) or tonumber(bag.laps) or 1,
            placement = tonumber(bag.placement) or 0,
            players_total = tonumber(bag.players_total) or tonumber(active.players_total) or 0,
            drift_score = tonumber(active.drift_score) or tonumber(bag.drift_score) or 0,
            drift_combo = tonumber(active.drift_combo) or tonumber(bag.drift_combo) or 1,
            distance_m = dist,
          })
        end
      end
    end
  end
end)

RegisterNUICallback('nui_ready', function(data, cb)
  VHubRachaNui.ready = true
  VHubRachaNui.ready_at = GetGameTimer()
  VHubRachaNui.href = type(data) == 'table' and tostring(data.href or '') or ''
  cb({
    ok = true,
    use_nui = enabled(),
    ready = true,
  })
end)

RegisterNUICallback('vhub_racha.action', function(data, cb)
  data = type(data) == 'table' and data or {}
  local action = tostring(data.action or '')
  if action == 'confirm_presence' then
    TriggerServerEvent(E.LOBBY_CONFIRM, data.inst_id or (L.pending and L.pending.inst_id) or '')
  elseif action == 'leave_lobby' then
    TriggerServerEvent(E.LOBBY_LEAVE, data.inst_id or (L.pending and L.pending.inst_id) or '')
  elseif action == 'request_join' then
    TriggerServerEvent(E.LOBBY_JOIN, data.inst_id or '')
  else
    cb({ ok = false, err = 'acao_invalida' })
    return
  end
  cb({ ok = true })
end)

RegisterNUICallback('vhub_racha.request_sync', function(_data, cb)
  send_bag_if_changed((L and L.bag) or {})
  cb({ ok = true })
end)
