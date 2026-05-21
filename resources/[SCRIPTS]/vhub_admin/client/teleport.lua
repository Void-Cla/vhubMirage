-- client/teleport.lua  execu  o de TPs (com fallback ground + parachute)
---@diagnostic disable: undefined-global

local E = VHubAdmin.E

-- TP simples para (x,y,z): freeze + coords + espera colis o + libera
local function tpTo(x, y, z, h)
  Citizen.CreateThread(function()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    if h then SetEntityHeading(ped, h + 0.0) end
    local t = 0
    while not HasCollisionLoadedAroundEntity(ped) and t < 4000 do
      RequestCollisionAtCoord(x, y, z); Citizen.Wait(50); t = t + 50
    end
    FreezeEntityPosition(ped, false)
    VHubAdmin.notify(('Teleportado (%.1f, %.1f, %.1f)'):format(x, y, z))
  end)
end

-- TP ao waypoint COM ground-detection correto via raycast vertical.
--   1) teleporta para (x, y, 800) e congela
--   2) carrega colis o em volta do ped
--   3) raycast vertical para baixo (flags=1 = world only)
--   4) snap exato ao ground (gz + 0.05)
--   5) fallback: GetGroundZFor_3dCoord, depois para-quedas
local function tpToWaypoint()
  Citizen.CreateThread(function()
    local wp = GetFirstBlipInfoId(8)
    if not DoesBlipExist(wp) then
      VHubAdmin.notify('Sem marcador no mapa.'); return
    end
    local c = GetBlipInfoIdCoord(wp)
    local x, y = c.x + 0.0, c.y + 0.0
    local ped  = PlayerPedId()
    local h    = GetEntityHeading(ped)

    -- passo 1: teleporta para altitude segura e congela
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, x, y, 800.0, false, false, false)

    -- passo 2: carrega colis o
    RequestCollisionAtCoord(x, y, 800.0)
    local t = 0
    while not HasCollisionLoadedAroundEntity(ped) and t < 5000 do
      RequestCollisionAtCoord(x, y, 800.0)
      Citizen.Wait(50); t = t + 50
    end
    Citizen.Wait(150)  -- d   tempo extra para LOD descarregar

    -- passo 3: raycast vertical 800   -500
    local gz
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
      x, y, 800.0, x, y, -500.0, 1, ped, 4)
    local _, hit, endCoords = GetShapeTestResult(handle)
    if hit == 1 or hit == true then gz = endCoords.z end

    -- fallback nativo se raycast falhou
    if not gz then
      for z = 800.0, 0.0, -25.0 do
        local ok, g = GetGroundZFor_3dCoord(x, y, z, false)
        if ok and g and g ~= 0.0 then gz = g; break end
      end
    end

    if gz then
      SetEntityCoordsNoOffset(ped, x, y, gz + 0.05, false, false, false)
      SetEntityHeading(ped, h)
      ClearPedTasksImmediately(ped)
      SetEntityVelocity(ped, 0.0, 0.0, -1.0)
      FreezeEntityPosition(ped, false)
      VHubAdmin.notify(('Teleportado ao marcador (%.1f, %.1f, %.1f)'):format(x, y, gz))
    else
      -- fallback p ra-quedas em altitude
      SetEntityCoordsNoOffset(ped, x, y, 1000.0, false, false, false)
      FreezeEntityPosition(ped, false)
      GiveWeaponToPed(ped, GetHashKey('GADGET_PARACHUTE'), 1, false, true)
      VHubAdmin.notify('Solo n o resolvido. P ra-quedas entregue.')
    end
  end)
end

RegisterNetEvent(E.DO_TP)
AddEventHandler(E.DO_TP, function(x, y, z, mode, h)
  if mode == 'waypoint' then tpToWaypoint(); return end
  if x and y and z then tpTo(x, y, z, h) end
end)

-- comandos slash
RegisterCommand('tp', function(_, args)
  if not VHubAdmin.state.is_admin then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_TP, t)
  else VHubAdmin.notify('Uso: /tp <id>') end
end, false)

RegisterCommand('tptome', function(_, args)
  if not VHubAdmin.state.is_admin then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_TPTOME, t)
  else VHubAdmin.notify('Uso: /tptome <id>') end
end, false)

RegisterCommand('bring', function(_, args)
  if not VHubAdmin.state.is_admin then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_TPTOME, t) end
end, false)

RegisterCommand('tpgo', function()
  if not VHubAdmin.state.is_admin then return end
  TriggerServerEvent(E.ACT_TPGO)
end, false)

RegisterCommand('tpcds', function(_, args)
  if not VHubAdmin.state.is_admin then return end
  -- aceita /tpcds 123 456 78  OU  /tpcds 123,456,78
  local raw = table.concat(args, ' '):gsub(',', ' ')
  local x, y, z = raw:match('([%-%.%d]+)%s+([%-%.%d]+)%s+([%-%.%d]+)')
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if x and y and z then TriggerServerEvent(E.ACT_TPCDS, x, y, z)
  else VHubAdmin.notify('Uso: /tpcds <x> <y> <z>') end
end, false)

RegisterCommand('tpall', function()
  if not VHubAdmin.state.is_admin then return end
  TriggerServerEvent(E.ACT_TPALL)
end, false)

RegisterCommand('tplast', function()
  if not VHubAdmin.state.is_admin then return end
  TriggerServerEvent(E.ACT_TPLAST)
end, false)
