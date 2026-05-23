-- client/race.lua - execucao visual da corrida; servidor valida progresso.

local E, Cfg = VHubRachaE, VHubRachaCfg
local active, route_blip, frozen_vehicle, last_hud_ms, last_checkpoint_ms = nil, nil, nil, 0, 0

local function remove_route() if route_blip and DoesBlipExist(route_blip) then RemoveBlip(route_blip) end; route_blip = nil end
local function set_route(point, number)
  remove_route()
  route_blip = AddBlipForCoord(point.x, point.y, point.z)
  SetBlipSprite(route_blip, 1); SetBlipColour(route_blip, 5); SetBlipScale(route_blip, 0.85)
  SetBlipRoute(route_blip, true); ShowNumberOnBlip(route_blip, number or 1)
  BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Checkpoint'); EndTextCommandSetBlipName(route_blip)
  SetNewWaypoint(point.x + 0.0, point.y + 0.0)
end
local function cleanup()
  remove_route()
  if frozen_vehicle and DoesEntityExist(frozen_vehicle) then FreezeEntityPosition(frozen_vehicle, false); SetVehicleDoorsLocked(frozen_vehicle, 1) end
  frozen_vehicle, active = nil, nil
  SendNUIMessage({ action = 'raceEnd' })
end
local function draw_text(text, x, y, scale)
  SetTextFont(4); SetTextScale(scale, scale); SetTextColour(255, 255, 255, 220); SetTextOutline(); SetTextCentre(true)
  SetTextEntry('STRING'); AddTextComponentString(text); DrawText(x, y)
end

RegisterNetEvent(E.RACE_PREPARE, function(data)
  if type(data) ~= 'table' or type(data.grid) ~= 'table' then return end
  local ped, veh = PlayerPedId(), GetVehiclePedIsIn(PlayerPedId(), false)
  if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
  DoScreenFadeOut(350); Citizen.Wait(420)
  SetEntityCoordsNoOffset(veh, data.grid.x + 0.0, data.grid.y + 0.0, data.grid.z + 0.15, false, false, false)
  SetEntityHeading(veh, data.grid.h or 0.0); SetVehicleOnGroundProperly(veh)
  FreezeEntityPosition(veh, true); SetVehicleDoorsLocked(veh, 4); frozen_vehicle = veh
  DoScreenFadeIn(350)
  SendNUIMessage({ action = 'countdown', data = { ms = data.countdown_ms or Cfg.COUNTDOWN_MS, track = data.track and data.track.label or 'Racha', slot = data.slot or 1 } })
end)

RegisterNetEvent(E.RACE_START, function(data)
  if type(data) ~= 'table' or type(data.track) ~= 'table' then return end
  if frozen_vehicle and DoesEntityExist(frozen_vehicle) then FreezeEntityPosition(frozen_vehicle, false); SetVehicleDoorsLocked(frozen_vehicle, 1) end
  active = {
    run_id = data.run_id, token = data.token, self = data.self or {},
    track = data.track, laps = data.laps or 1, lap = 1, next_checkpoint = 1,
    progress = 0, started_at = GetGameTimer(), standings = data.standings or {},
  }
  if active.track.checkpoints[1] then set_route(active.track.checkpoints[1], 1) end
  SendNUIMessage({ action = 'raceStart', data = active })
  PlaySoundFrontend(-1, 'Oneshot_Final', 'MP_MISSION_COUNTDOWN_SOUNDSET', false)
end)

RegisterNetEvent(E.RACE_CHECKPOINT, function(data)
  if not active or type(data) ~= 'table' or data.token ~= active.token then return end
  active.lap = data.lap or active.lap; active.next_checkpoint = data.next_checkpoint or active.next_checkpoint
  active.progress = data.progress or active.progress; active.self = data.self or active.self; active.standings = data.standings or active.standings
  if active.track.checkpoints[active.next_checkpoint] then set_route(active.track.checkpoints[active.next_checkpoint], active.next_checkpoint) end
  SendNUIMessage({ action = 'raceHud', data = active })
  PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', false)
end)

RegisterNetEvent(E.RACE_PROGRESS, function(data)
  if active and type(data) == 'table' and data.run_id == active.run_id then active.standings = data.standings or active.standings; SendNUIMessage({ action = 'raceHud', data = active }) end
end)
RegisterNetEvent(E.RACE_FINISH, function(data) SendNUIMessage({ action = 'finish', data = data or {} }); cleanup() end)
RegisterNetEvent(E.RACE_ABORT, function(data) SendNUIMessage({ action = 'abort', data = data or {} }); cleanup() end)

Citizen.CreateThread(function()
  while true do
    local wait = 600
    if active then
      wait = 0
      local ped, veh = PlayerPedId(), GetVehiclePedIsIn(PlayerPedId(), false)
      if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
        TriggerServerEvent(E.RACE_ABORT, { reason = 'dnf' }); cleanup()
      else
        local point = active.track.checkpoints[active.next_checkpoint]
        if point then
          local dist, color = #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)), active.track.color or Cfg.COLOR
          DrawMarker(1, point.x, point.y, point.z - 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 12.0, 12.0, 8.0, 255, 255, 255, 35, false, false, 2, false, nil, nil, false)
          DrawMarker(21, point.x, point.y, point.z + 1.0, 0.0, 0.0, 0.0, 0.0, 180.0, 130.0, 3.0, 3.0, 2.0, color.r, color.g, color.b, 120, true, false, 2, true, nil, nil, false)
          if dist <= (active.track.checkpoint_radius or Cfg.CHECKPOINT_RADIUS) and GetGameTimer() - last_checkpoint_ms > 600 then
            last_checkpoint_ms = GetGameTimer()
            TriggerServerEvent(E.RACE_CHECKPOINT, { run_id = active.run_id, token = active.token })
          end
        end
        if GetGameTimer() - last_hud_ms > 250 then
          last_hud_ms = GetGameTimer(); active.elapsed_ms = last_hud_ms - active.started_at
          SendNUIMessage({ action = 'raceHud', data = active })
        end
        draw_text(('VOLTA %d/%d  CP %d/%d'):format(active.lap, active.laps, active.next_checkpoint, #(active.track.checkpoints or {})), 0.5, 0.91, 0.42)
      end
    end
    Citizen.Wait(wait)
  end
end)
