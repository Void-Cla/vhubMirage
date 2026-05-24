-- client/modes/speedtrap.lua — soma velocidade nos radares com bonus combo.

VHubRachaModes = VHubRachaModes or {}
local Cfg = VHubRachaCfg
local V   = VHubRachaVeh

VHubRachaModes.speedtrap = {
  id = 'speedtrap',
  start = function(active)
    active.trap_total = 0
    active.trap_combo = 1.0
    active.trap_hits  = 0
  end,
  on_start = function(_a) end,
  on_checkpoint = function(active, _idx)
    local ped = PlayerPedId()
    local veh = V.ped_vehicle(ped)
    local kmh = (veh ~= 0) and V.speed_kmh(veh) or 0
    local cfg = Cfg.SPEEDTRAP or {}
    local bonus = cfg.COMBO_BONUS or 1.05
    active.trap_hits  = (active.trap_hits or 0) + 1
    active.trap_combo = (active.trap_combo or 1.0) * bonus
    active.trap_total = (active.trap_total or 0) + math.floor(kmh * active.trap_combo)
    -- Reaproveita drift_score como "score visivel" pro server (HUD le este campo)
    active.drift_score = active.trap_total
  end,
  on_finish = function(_a, _p) end,
}
