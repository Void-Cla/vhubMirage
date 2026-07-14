-- server/teleport.lua — teleporte autorizado pelo owner vhub_player_state
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E
local U = VHubAdmin.U

local history = {}
local waypointPending = {}

-- Guarda a posição atual antes de uma movimentação administrativa.
local function pushHistory(src)
  local pos = Core:coordsOf(src)
  if not pos then return end
  local stack = history[src] or {}
  stack[#stack + 1] = pos
  if #stack > CFG.limits.tp_history then table.remove(stack, 1) end
  history[src] = stack
end

-- Executa o teleporte e informa falha sem expor detalhes de implementação.
local function move(src, target, pos, action, payload)
  if not Core:teleport(target, pos) then
    Core:notify(src, 'Teleporte recusado pelo owner do jogador.', 'erro')
    return false
  end
  Core:audit(src, action, target ~= src and target or nil, payload or {})
  return true
end

RegisterNetEvent(E.ACT_TP)
AddEventHandler(E.ACT_TP, function(target)
  local src = source
  if not Core:guard(src, 'tp', 'teleport') then return end
  local targetSrc = Core:onlineTarget(target)
  local pos = targetSrc and Core:coordsOf(targetSrc) or nil
  if not targetSrc or not pos then return Core:notify(src, 'Alvo indisponível.', 'erro') end

  pushHistory(src)
  pos.y = pos.y + 1.5
  move(src, src, pos, 'tp', { target = targetSrc })
end)

RegisterNetEvent(E.ACT_TPTOME)
AddEventHandler(E.ACT_TPTOME, function(target)
  local src = source
  if not Core:guard(src, 'bring', 'teleport') then return end
  local targetSrc = Core:onlineTarget(target)
  local pos = Core:coordsOf(src)
  if not targetSrc or not pos then return Core:notify(src, 'Alvo indisponível.', 'erro') end

  pushHistory(targetSrc)
  pos.y = pos.y + 1.5
  if move(src, targetSrc, pos, 'bring', { target = targetSrc }) then
    Core:notify(targetSrc, 'Você foi trazido pela equipe.', 'info')
  end
end)

RegisterNetEvent(E.ACT_TPGO)
AddEventHandler(E.ACT_TPGO, function()
  local src = source
  if not Core:guard(src, 'tpgo', 'teleport') then return end
  waypointPending[src] = GetGameTimer() + 15000
  TriggerClientEvent(E.REQUEST_WAYPOINT, src)
end)

RegisterNetEvent(E.ACT_TPWAYPOINT)
AddEventHandler(E.ACT_TPWAYPOINT, function(pos)
  local src = source
  local expires = waypointPending[src]
  waypointPending[src] = nil
  if not expires or expires < GetGameTimer() or not Core.hasPerm(src, 'tpgo') then return end
  if not Core:rate(src, 'waypoint') or not U.validCoords(pos) then
    return Core:notify(src, 'Marcador inválido.', 'erro')
  end

  local heading = U.number(pos.h, -3600, 3600) or 0.0
  pushHistory(src)
  move(src, src, { x = pos.x, y = pos.y, z = pos.z, h = heading }, 'tpgo', {})
end)

RegisterNetEvent(E.ACT_TPCDS)
AddEventHandler(E.ACT_TPCDS, function(x, y, z, heading)
  local src = source
  if not Core:guard(src, 'tpcds', 'teleport') then return end
  local pos = { x = x, y = y, z = z, h = U.number(heading, -3600, 3600) or 0.0 }
  if not U.validCoords(pos) then return Core:notify(src, 'Coordenadas inválidas.', 'erro') end

  pushHistory(src)
  move(src, src, pos, 'tpcds', { x = pos.x, y = pos.y, z = pos.z })
end)

RegisterNetEvent(E.ACT_TPALL)
AddEventHandler(E.ACT_TPALL, function()
  local src = source
  if not Core:guard(src, 'tpall', 'tpall') then return end
  local pos = Core:coordsOf(src)
  if not pos then return end

  Citizen.CreateThread(function()
    local moved = 0
    for _, raw in ipairs(GetPlayers()) do
      local target = tonumber(raw)
      if target and target ~= src and Core:getCharId(target) then
        pushHistory(target)
        Core:teleport(target, { x = pos.x, y = pos.y + 1.5, z = pos.z, h = pos.h })
        moved = moved + 1
        if moved % 25 == 0 then Citizen.Wait(0) end
      end
    end
    Core:audit(src, 'tpall', nil, { moved = moved })
    Core:notify(src, ('%d jogadores movidos.'):format(moved), 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_TPZ)
AddEventHandler(E.ACT_TPZ, function(zoneId)
  local src = source
  if not Core:guard(src, 'tp', 'teleport') then return end
  local id = U.identifier(zoneId, 32)
  local zone = id and CFG.teleport_zones[id] or nil
  if not zone then return Core:notify(src, 'Destino desconhecido.', 'erro') end

  pushHistory(src)
  move(src, src, zone, 'tpz', { zone = id })
end)

RegisterNetEvent(E.ACT_TPLAST)
AddEventHandler(E.ACT_TPLAST, function()
  local src = source
  if not Core:guard(src, 'tp', 'teleport') then return end
  local stack = history[src]
  local previous = stack and table.remove(stack) or nil
  if not previous then return Core:notify(src, 'Sem histórico de teleporte.', 'info') end

  move(src, src, previous, 'tplast', {})
end)

AddEventHandler('playerDropped', function()
  history[source] = nil
  waypointPending[source] = nil
end)
