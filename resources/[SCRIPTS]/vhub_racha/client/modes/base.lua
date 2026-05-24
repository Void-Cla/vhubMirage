-- client/modes/base.lua — interface base (no-op). Outros modos fallback aqui.

VHubRachaModes = VHubRachaModes or {}

VHubRachaModes.base = {
  id = 'base',
  start         = function(_active, _payload) end,
  on_start      = function(_active) end,
  on_checkpoint = function(_active, _idx) end,
  on_finish     = function(_active, _payload) end,
}
