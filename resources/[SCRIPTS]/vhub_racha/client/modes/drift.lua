-- client/modes/drift.lua — pontuacao por angulo + velocidade lateral.

VHubRachaModes = VHubRachaModes or {}
local Cfg = VHubRachaCfg
local V   = VHubRachaVeh

VHubRachaModes.drift = {
  id = 'drift',
  start = function(active)
    active.drift_score      = 0
    active.drift_combo      = 1.0
    active.drift_active_ms  = 0
    active.drift_break_ms   = 0
    active.drift_last_speed = 0
  end,
  on_start = function(_a) end,
  on_checkpoint = function(_a, _i) end,
  on_finish = function(_a, _p) end,
}

CreateThread(function()
  local last_t = GetGameTimer()
  while true do
    local active = VHubRachaLocal and VHubRachaLocal.active_race and VHubRachaLocal.active_race() or nil
    if not active or active.track.kind ~= 'drift'
       or active.aborted or active.finished or active.started_ms == 0 then
      Wait(250)
      last_t = GetGameTimer()
    else
      Wait(80)
      local now = GetGameTimer()
      local dt_ms = now - last_t
      last_t = now
      if dt_ms < 1 then dt_ms = 80 end

      local ped = PlayerPedId()
      local veh = V.ped_vehicle(ped)
      if veh == 0 then
        active.drift_combo = 1.0
        active.drift_active_ms = 0
      else
        local fwd, lat = V.local_velocity(veh)
        local speed = math.abs(fwd) + math.abs(lat)
        local angle_deg = 0
        if speed > 1.0 then
          angle_deg = math.deg(math.atan(math.abs(lat), math.abs(fwd)))
        end
        local on_air = V.is_in_air(veh)
        local cfg = Cfg.DRIFT

        local last_s = active.drift_last_speed or 0
        local impact = math.abs(speed - last_s)
        active.drift_last_speed = speed
        local impact_hit = impact > (cfg.IMPACT_THRESHOLD or 8)

        if not on_air and angle_deg >= cfg.MIN_ANGLE_DEG
           and fwd >= cfg.MIN_SPEED_KMH and not impact_hit then
          active.drift_active_ms = (active.drift_active_ms or 0) + dt_ms
          active.drift_break_ms = 0
          local elapsed_sec = active.drift_active_ms / 1000
          local mult = 1.0
          for i, threshold in ipairs(cfg.COMBO_THRESHOLDS or {}) do
            if elapsed_sec >= threshold then mult = cfg.COMBO_MULT[i] or mult end
          end
          active.drift_combo = mult
          local pts_per_sec = (angle_deg * fwd) / (cfg.POINTS_DIVISOR or 40)
          if pts_per_sec > (cfg.CAP_PER_SEC or 150) then pts_per_sec = cfg.CAP_PER_SEC or 150 end
          local pts = math.floor((pts_per_sec * mult) * (dt_ms / 1000))
          if pts > 0 then active.drift_score = (active.drift_score or 0) + pts end
        else
          active.drift_break_ms = (active.drift_break_ms or 0) + dt_ms
          if active.drift_break_ms >= (cfg.BREAK_MS or 700) or impact_hit then
            active.drift_active_ms = 0
            active.drift_combo = impact_hit and (cfg.IMPACT_PENALTY or 0.5) or 1.0
          end
        end
      end
    end
  end
end)
