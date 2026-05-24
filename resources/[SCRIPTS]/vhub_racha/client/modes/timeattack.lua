-- client/modes/timeattack.lua — solo contra o tempo.
VHubRachaModes = VHubRachaModes or {}

VHubRachaModes.timeattack = {
  id = 'timeattack',
  start = function(active) active.best_lap_ms = 0 end,
  on_start = function(_a) end,
  on_checkpoint = function(_a, _i) end,
  on_finish = function(_a, _p) end,
}
