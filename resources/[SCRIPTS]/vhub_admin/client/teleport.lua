-- client/teleport.lua - resolve waypoint; movimento pertence ao vhub_hss
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

local function finite(value, minimum, maximum)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
  if minimum and number < minimum then return nil end
  if maximum and number > maximum then return nil end
  return number
end

local function requestWaypoint(requestId)
  requestId = finite(requestId, 1)
  if not requestId or requestId % 1 ~= 0 then return end

  local blip = GetFirstBlipInfoId(8)
  if not DoesBlipExist(blip) then
    VHubAdmin.notify('Sem marcador no mapa.')
    return
  end

  local coords = GetBlipInfoIdCoord(blip)
  TriggerServerEvent(E.ACT_TPWAYPOINT_BEGIN, {
    request_id = requestId,
    x = coords.x + 0.0,
    y = coords.y + 0.0,
  })
end

local function scanGround(x, y)
  NewLoadSceneStartSphere(x, y, 0.0, 100.0, 0)

  local deadline = GetGameTimer() + 3000
  while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do
    RequestCollisionAtCoord(x, y, 0.0)
    RequestCollisionAtCoord(x, y, 1000.0)
    Citizen.Wait(50)
  end

  local iteration = 0
  for z = 1000.0, -100.0, -25.0 do
    RequestCollisionAtCoord(x, y, z)
    local found, ground = GetGroundZFor_3dCoord(x, y, z, false)
    if found and ground then return ground end

    iteration = iteration + 1
    if iteration % 4 == 0 then Citizen.Wait(25) end
  end

  local handle = StartExpensiveSynchronousShapeTestLosProbe(
    x, y, 1000.0, x, y, -300.0, 1, PlayerPedId(), 4)
  local _, hit, endCoords = GetShapeTestResult(handle)
  if (hit == 1 or hit == true) and endCoords then return endCoords.z end
  return nil
end

local function resolveWaypoint(payload)
  if type(payload) ~= 'table' then return end
  local requestId = finite(payload.request_id, 1)
  local x = finite(payload.x, -9000, 9000)
  local y = finite(payload.y, -9000, 9000)
  if not requestId or requestId % 1 ~= 0 or not x or not y then return end

  local ok, ground = pcall(scanGround, x, y)
  NewLoadSceneStop()
  if not ok or not ground then
    VHubAdmin.notify('Nao foi possivel resolver o solo do marcador.')
    return
  end

  TriggerServerEvent(E.ACT_TPWAYPOINT, {
    request_id = requestId,
    z = ground + 0.05,
  })
end

RegisterNetEvent(E.REQUEST_WAYPOINT)
AddEventHandler(E.REQUEST_WAYPOINT, requestWaypoint)

RegisterNetEvent(E.RESOLVE_WAYPOINT)
AddEventHandler(E.RESOLVE_WAYPOINT, resolveWaypoint)

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

RegisterCommand('tpway', function()
  if S.is_admin then TriggerServerEvent(E.ACT_TPGO) end
end, false)

RegisterCommand('tppgo', function()
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
