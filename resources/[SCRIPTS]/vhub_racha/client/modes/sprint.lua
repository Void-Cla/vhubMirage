-- client/modes/sprint.lua — A→B simples.
VHubRachaModes = VHubRachaModes or {}

VHubRachaModes.sprint = {
  id = 'sprint',
  start = function(active) active.best_lap_ms = 0 end,
  on_start = function(_a) end,
  on_checkpoint = function(_a, _i) end,
  on_finish = function(_a, _p) end,
}
