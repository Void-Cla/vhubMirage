-- client/sync.lua — report adaptive de drift_score + top_speed ao server.

local E = VHubRachaE
local V = VHubRachaVeh

local _prev_finished = false   -- detecta transição → finished para flush final

CreateThread(function()
  while true do
    local active = VHubRachaLocal.active_race()
    if not active or active.aborted or active.started_ms == 0 then
      _prev_finished = false
      Wait(2000)
    elseif active.finished then
      -- flush final: envia uma vez ao detectar finished, depois dorme
      if not _prev_finished then
        _prev_finished = true
        TriggerServerEvent(E.RACE_TICK, {
          drift_score = active.drift_score or 0,
          top_speed   = active.top_speed   or 0,
          best_lap_ms = active.best_lap_ms or 0,
          t_ms        = GetGameTimer(),
        })
      end
      Wait(2000)
    else
      _prev_finished = false
      Wait(1000)
      local ped = PlayerPedId()
      local veh = V.ped_vehicle(ped)
      local kmh = (veh ~= 0) and V.speed_kmh(veh) or 0
      if kmh > (active.top_speed or 0) then
        active.top_speed = math.floor(kmh)
      end
      TriggerServerEvent(E.RACE_TICK, {
        drift_score = active.drift_score or 0,
        top_speed   = active.top_speed   or 0,
        best_lap_ms = active.best_lap_ms or 0,
        t_ms        = GetGameTimer(),
      })
    end
  end
end)
