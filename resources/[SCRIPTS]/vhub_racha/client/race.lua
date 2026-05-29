-- client/race.lua — orquestracao do ciclo de corrida no cliente.
-- prepare → warmup (grid + countdown) → racing (modo ativo, totem ativo) → finish.

local E    = VHubRachaE
local V    = VHubRachaVeh
local CP   = VHubRachaCP
local L    = VHubRachaLocal
local Lang = VHubRachaLang
-- TOT pode ainda não estar carregado no momento em que este arquivo for executado.
-- Usamos um proxy que encaminha chamadas para `VHubRachaTotem` quando disponível
-- para evitar `attempt to index a nil value (upvalue 'TOT')` por ordem de carga.
local TOT = setmetatable({}, {
  __index = function(_, k)
    local t = rawget(_G, 'VHubRachaTotem')
    if t then
      local v = t[k]
      if type(v) == 'function' then
        return function(...)
          return v(...)
        end
      else
        return v
      end
    end
    -- noop guard: evita erros se chamado antes do totem existir
    return function() end
  end
})

VHubRachaModes = VHubRachaModes or {}

local function mode_for(kind)
  return VHubRachaModes[kind] or VHubRachaModes.base
end

local function next_target(active)
  if not active or not active.track then return nil end
  local cps = active.track.checkpoints or {}
  if #cps == 0 then return nil end
  local idx = ((active.cp_index - 1) % #cps) + 1
  return cps[idx]
end

-- Gerencia blips dos proximos checkpoints (mostra sempre os proximos 2)
local function clear_next_blips()
  if not L or not L._cp_blips then return end
  for _, b in ipairs(L._cp_blips) do
    if DoesBlipExist(b) then RemoveBlip(b) end
  end
  L._cp_blips = {}
end

local function update_next_blips(active)
  clear_next_blips()
  if not active or not active.track then return end
  local cps = active.track.checkpoints or {}
  if #cps == 0 then return end
  local idx = ((active.cp_index - 1) % #cps) + 1
  local n1 = cps[idx]
  local n2 = cps[(idx % #cps) + 1]
  local blips = {}
  if n1 then
    local b1 = AddBlipForCoord(n1.x, n1.y, n1.z)
    SetBlipSprite(b1, 1)
    SetBlipColour(b1, 5)
    SetBlipScale(b1, 0.9)
    SetBlipAsShortRange(b1, true)
    SetBlipRoute(b1, true)
    SetBlipRouteColour(5)
    blips[#blips+1] = b1
  end
  if n2 then
    local b2 = AddBlipForCoord(n2.x, n2.y, n2.z)
    SetBlipSprite(b2, 1)
    SetBlipColour(b2, 3)
    SetBlipScale(b2, 0.8)
    SetBlipAsShortRange(b2, true)
    blips[#blips+1] = b2
  end
  L._cp_blips = blips
end

-- Atualiza totem para o proximo CP (substitui blip/marker vanilla)
local function refresh_totem(active)
  local cp = next_target(active)
  if not cp then TOT.clear(); return end
  local is_finish = (active.cp_index >= active.cp_total)
  TOT.set_target({
    x = cp.x, y = cp.y, z = cp.z,
    kind = active.track.kind,
    is_finish = is_finish,
    label = is_finish and 'CHEGADA' or ('CP ' .. tostring(active.cp_index)),
  })
  -- Atualiza blips dos proximos checkpoints
  pcall(update_next_blips, active)
end

-- ── Prepare: teleporta para grid, congela ──────────────────────────────────

RegisterNetEvent(E.RACE_PREPARE, function(payload)
  if type(payload) ~= 'table' or not payload.track then return end
  local track = payload.track
  local grid  = payload.grid_pos

  local active = {
    inst_id     = payload.inst_id,
    track       = {
      id          = track.id, label = track.label, kind = track.kind,
      laps        = payload.laps or track.laps or 1,
      grid        = track.grid or {},
      start       = track.start,
      checkpoints = CP.normalize_list(track.checkpoints or {}, 0),
    },
    laps        = payload.laps or 1,
    mode        = payload.mode or 'rankeada',
    cp_index    = 1,
    cp_total    = (#(track.checkpoints or {})) * (payload.laps or 1),
    started_ms  = 0,
    top_speed   = 0,
    drift_score = 0,
    drift_combo = 1.0,
    finished    = false,
    aborted     = false,
    grid        = grid,
    starts_at   = payload.starts_at or 0,
    countdown   = payload.countdown or 7000,
    players_total = payload.players_total or 0,
  }
  VHubRachaLocal.set_active(active)

  -- Teleporta veiculo/ped para grid
  local ped = PlayerPedId()
  local _, veh = V.is_driver(ped)
  local target = (veh ~= 0) and veh or ped
  if grid and grid.x then
    RequestCollisionAtCoord(grid.x, grid.y, grid.z)
    SetEntityCoordsNoOffset(target, grid.x, grid.y, grid.z, false, false, false)
    SetEntityHeading(target, grid.h or 0.0)
    FreezeEntityPosition(target, true)
  end

  -- Inicia modo
  local mode = mode_for(active.track.kind)
  active.mode_ref = mode
  if mode and type(mode.start) == 'function' then
    pcall(mode.start, active, payload)
  end

  -- Inicia totem para o primeiro CP
  refresh_totem(active)
end)

-- ── Start: descongela e libera ─────────────────────────────────────────────

RegisterNetEvent(E.RACE_START, function(payload)
  local active = VHubRachaLocal.active_race(); if not active then return end
  active.started_ms = (payload and payload.started_ms) or GetGameTimer()
  local ped = PlayerPedId()
  local veh = V.ped_vehicle(ped)
  if veh ~= 0 then FreezeEntityPosition(veh, false)
  else FreezeEntityPosition(ped, false) end

  local m = active.mode_ref
  if m and type(m.on_start) == 'function' then pcall(m.on_start, active) end

  -- Notify de modo
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(
    active.mode == 'treino' and Lang.t('notify.training_mode') or Lang.t('notify.ranked_mode'))
  EndTextCommandThefeedPostTicker(false, true)
end)

-- ── Loop de deteccao de checkpoint (substitui marker vanilla) ──────────────

CreateThread(function()
  while true do
    local active = VHubRachaLocal.active_race()
    if not active or active.aborted or active.finished or active.started_ms == 0 then
      Wait(300)
    else
      Wait(50)   -- 20Hz: suficiente; também envia projeção ao NUI quando ativo
      local target = next_target(active)
      if target then
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local radius = target.radius or 11.0

        if CP.inside(pos.x, pos.y, pos.z, target, radius) then
          local veh = V.ped_vehicle(ped)
          local speed = (veh ~= 0) and V.speed_kmh(veh) or 0
          if speed > (active.top_speed or 0) then active.top_speed = math.floor(speed) end

          TriggerServerEvent(E.RACE_CHECKPOINT, {
            cp_index = active.cp_index,
            pos      = { x = pos.x, y = pos.y, z = pos.z },
            speed    = math.floor(speed),
            t_ms     = GetGameTimer(),
          })

          local m = active.mode_ref
          if m and type(m.on_checkpoint) == 'function' then
            pcall(m.on_checkpoint, active, active.cp_index)
          end

          active.cp_index = active.cp_index + 1
          if active.cp_index > active.cp_total then
            active.finished = true
            TOT.clear()
          else
            refresh_totem(active)
          end
        end
      end
      -- Telemetria (HUD) e responsabilidade UNICA de nui_bridge.lua.
      -- Projecao do totem e responsabilidade UNICA de totem.lua.
      -- race.lua so detecta CP e define o alvo do totem (refresh_totem).
    end
  end
end)

-- ── Finish ─────────────────────────────────────────────────────────────────

RegisterNetEvent(E.RACE_FINISH, function(payload)
  local active = VHubRachaLocal.active_race()
  local m = active and active.mode_ref
  if m and type(m.on_finish) == 'function' then pcall(m.on_finish, active, payload) end

  TOT.clear()
  clear_next_blips()

  -- Envia ao NUI o resumo se estiver aberta
  SendNUIMessage({ action = 'race_finish', data = payload or {} })

  -- Toast
  local mode = (payload and payload.mode) or (active and active.mode) or 'rankeada'
  if mode == 'treino' then
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(Lang.t('race.training_no_reward'))
    EndTextCommandThefeedPostTicker(false, true)
  else
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(
      Lang.t('race.finished_pos', { tonumber(payload and payload.placement) or 0 }))
    EndTextCommandThefeedPostTicker(false, true)
  end

  VHubRachaLocal.clear_active()
end)

-- ── Abort detection (saiu do veiculo) ──────────────────────────────────────

CreateThread(function()
  while true do
    Wait(2500)
    local active = VHubRachaLocal.active_race()
    if active and not active.finished and not active.aborted and active.started_ms > 0 then
      local kind = active.track.kind
      if kind ~= 'freerun' then
        local ped = PlayerPedId()
        local veh = V.ped_vehicle(ped)
        if veh == 0 then
          active.aborted = true
          TOT.clear()
          TriggerServerEvent(E.RACE_ABORT, 'fora_do_veiculo')
          BeginTextCommandThefeedPost('STRING')
          AddTextComponentSubstringPlayerName(Lang.t('race.left_vehicle'))
          EndTextCommandThefeedPostTicker(false, true)
        end
      end
    end
  end
end)

-- ── Alerta policia ─────────────────────────────────────────────────────────

RegisterNetEvent(E.RACE_POLICE, function(data)
  if type(data) ~= 'table' or not data.start then return end
  local h = AddBlipForCoord(data.start.x, data.start.y, data.start.z)
  SetBlipSprite(h, 161)
  SetBlipColour(h, 1)
  SetBlipScale(h, 0.95)
  SetBlipFlashes(h, true)
  SetBlipAsShortRange(h, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(Lang.t('police.blip_label', { data.label or '?' }))
  EndTextCommandSetBlipName(h)

  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(
    Lang.t('police.alert_body', { data.label or '?', data.kind or '?' }))
  EndTextCommandThefeedPostTicker(false, true)

  SetTimeout(tonumber(data.ttl_ms) or 90000, function()
    if DoesBlipExist(h) then RemoveBlip(h) end
  end)
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  TOT.clear()
  VHubRachaLocal.clear_active()
end)
