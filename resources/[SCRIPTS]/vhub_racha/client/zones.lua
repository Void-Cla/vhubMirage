-- client/zones.lua - blips, marcadores e interacao fisica do vhub_racha.

local Cfg, E = VHubRachaCfg, VHubRachaE
local blips, nearby = {}, nil

local function help(text)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayHelp(0, false, true, 1)
end

local function add_blips()
  if not Cfg.BLIP.show then return end
  for _, track in ipairs(VHubRachaTracks) do
    if not blips[track.id] then
      local b = AddBlipForCoord(track.start.x, track.start.y, track.start.z)
      SetBlipSprite(b, Cfg.BLIP.sprite); SetBlipColour(b, Cfg.BLIP.color)
      SetBlipScale(b, Cfg.BLIP.scale); SetBlipAsShortRange(b, true)
      BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Racha - ' .. track.label); EndTextCommandSetBlipName(b)
      blips[track.id] = b
    end
  end
end

AddEventHandler('onClientResourceStart', function(res) if res == GetCurrentResourceName() then add_blips() end end)

Citizen.CreateThread(function()
  add_blips()
  while true do
    local coords = GetEntityCoords(PlayerPedId())
    local best, best_dist = nil, Cfg.MARKER_RADIUS + 0.01
    for _, track in ipairs(VHubRachaTracks) do
      local dist = #(coords - vector3(track.start.x, track.start.y, track.start.z))
      if dist < best_dist then best, best_dist = track, dist end
    end
    nearby = best and { track = best, dist = best_dist } or nil
    Citizen.Wait(650)
  end
end)

Citizen.CreateThread(function()
  while true do
    local wait = 500
    if nearby then
      local track, color = nearby.track, nearby.track.color or Cfg.COLOR
      wait = nearby.dist <= 18.0 and 0 or 150
      DrawMarker(23, track.start.x, track.start.y, track.start.z - 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 7.5, 7.5, 1.2, color.r, color.g, color.b, 125, false, false, 2, false, nil, nil, false)
      DrawMarker(4, track.start.x, track.start.y, track.start.z + 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, color.r, color.g, color.b, 180, false, true, 2, false, nil, nil, false)
      if nearby.dist <= Cfg.INTERACT_RADIUS then
        local ped, veh = PlayerPedId(), GetVehiclePedIsIn(PlayerPedId(), false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
          help(('Pressione ~INPUT_CONTEXT~ para abrir %s'):format(track.label))
          if IsControlJustPressed(0, 38) then TriggerServerEvent(E.NUI_OPEN, { track_id = track.id }) end
        else
          help('Entre como motorista para acessar a largada')
        end
      end
    end
    Citizen.Wait(wait)
  end
end)
