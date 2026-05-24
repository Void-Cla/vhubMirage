-- client/modes/drag.lua — 1/4 mile (semaforo visual + linha unica de chegada).
-- O semaforo visual ja e renderizado pelo countdown.lua. Aqui so configuracao.

VHubRachaModes = VHubRachaModes or {}

VHubRachaModes.drag = {
  id = 'drag',
  start = function(active)
    active.best_lap_ms = 0
    active.false_start = false
  end,
  on_start = function(_a) end,
  on_checkpoint = function(_a, _i) end,
  on_finish = function(_a, _p) end,
}
