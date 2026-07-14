-- client/teleport.lua - resolve waypoint; movimento pertence ao vhub_player_state
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

local function resolveWaypoint()
  local blip = GetFirstBlipInfoId(8)
  if not DoesBlipExist(blip) then
    VHubAdmin.notify('Sem marcador no mapa.')
    return
  end

  local coords = GetBlipInfoIdCoord(blip)
  local x, y = coords.x + 0.0, coords.y + 0.0
  RequestCollisionAtCoord(x, y, 800.0)
  local elapsed = 0
  while not HasCollisionLoadedAroundEntity(PlayerPedId()) and elapsed < 2000 do
    RequestCollisionAtCoord(x, y, 800.0)
    Citizen.Wait(50)
    elapsed = elapsed + 50
  end

  local ground = nil
  local handle = StartExpensiveSynchronousShapeTestLosProbe(x, y, 1000.0, x, y, -300.0, 1, PlayerPedId(), 4)
  local _, hit, endCoords = GetShapeTestResult(handle)
  if hit == 1 or hit == true then ground = endCoords.z end
  if not ground then
    for z = 1000.0, 0.0, -25.0 do
      local ok, value = GetGroundZFor_3dCoord(x, y, z, false)
      if ok and value and value ~= 0.0 then ground = value; break end
    end
  end
  if not ground then
    VHubAdmin.notify('Nao foi possivel resolver o solo do marcador.')
    return
  end

  TriggerServerEvent(E.ACT_TPWAYPOINT, {
    x = x,
    y = y,
    z = ground + 0.05,
    h = GetEntityHeading(PlayerPedId()),
  })
end

RegisterNetEvent(E.REQUEST_WAYPOINT)
AddEventHandler(E.REQUEST_WAYPOINT, resolveWaypoint)

RegisterCommand('tp', function(_, args)
  if not S.is_admin then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent(E.ACT_TP, target) else VHubAdmin.notify('Uso: /tp <id>') end
end, false)

RegisterCommand('tptome', function(_, args)
  if not S.is_admin then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent(E.ACT_TPTOME, target) else VHubAdmin.notify('Uso: /tptome <id>') end
end, false)

RegisterCommand('bring', function(_, args)
  if not S.is_admin then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent(E.ACT_TPTOME, target) end
end, false)

RegisterCommand('tpgo', function()
  if S.is_admin then TriggerServerEvent(E.ACT_TPGO) end
end, false)

RegisterCommand('tpcds', function(_, args)
  if not S.is_admin then return end
  local raw = table.concat(args, ' '):gsub(',', ' ')
  local x, y, z, h = raw:match('([%-%.%d]+)%s+([%-%.%d]+)%s+([%-%.%d]+)%s*([%-%.%d]*)')
  x, y, z, h = tonumber(x), tonumber(y), tonumber(z), tonumber(h)
  if x and y and z then TriggerServerEvent(E.ACT_TPCDS, x, y, z, h)
  else VHubAdmin.notify('Uso: /tpcds <x> <y> <z> [h]') end
end, false)

RegisterCommand('tpall', function()
  if S.is_admin then TriggerServerEvent(E.ACT_TPALL) end
end, false)

RegisterCommand('tplast', function()
  if S.is_admin then TriggerServerEvent(E.ACT_TPLAST) end
end, false)

RegisterCommand('tpz', function(_, args)
  if not S.is_admin then return end
  local zone = args[1]
  if zone then TriggerServerEvent(E.ACT_TPZ, zone)
  else VHubAdmin.notify('Uso: /tpz <destino>') end
end, false)
