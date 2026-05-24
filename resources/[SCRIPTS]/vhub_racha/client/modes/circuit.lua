-- client/modes/circuit.lua — voltas multiplas, best_lap_ms.
VHubRachaModes = VHubRachaModes or {}

VHubRachaModes.circuit = {
  id = 'circuit',
  start = function(active)
    active.best_lap_ms = 0
    active.last_lap_at = 0
  end,
  on_start = function(active) active.last_lap_at = GetGameTimer() end,
  on_checkpoint = function(active, idx)
    local cps_per_lap = #(active.track.checkpoints or {})
    if cps_per_lap == 0 then return end
    if (idx % cps_per_lap) == 0 then
      local now = GetGameTimer()
      local lap_ms = now - (active.last_lap_at or now)
      if lap_ms > 0 and (active.best_lap_ms == 0 or lap_ms < active.best_lap_ms) then
        active.best_lap_ms = lap_ms
      end
      active.last_lap_at = now
    end
  end,
  on_finish = function(_a, _p) end,
}
