-- server/teleport.lua — teleporte autorizado pelo owner vhub_hss
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E
local U = VHubAdmin.U

local history = {}
local waypointPending = {}
local waypointSequence = {}

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
  local current = Core:coordsOf(src)
  if not current then return Core:notify(src, 'Posição atual indisponível.', 'erro') end

  local requestId = (waypointSequence[src] or 0) + 1
  waypointSequence[src] = requestId
  waypointPending[src] = {
    source = src,
    request_id = requestId,
    heading = current.h,
    stage = 'marker',
    expires = GetGameTimer() + 15000,
  }
  TriggerClientEvent(E.REQUEST_WAYPOINT, src, requestId)
end)

RegisterNetEvent(E.ACT_TPWAYPOINT_BEGIN)
AddEventHandler(E.ACT_TPWAYPOINT_BEGIN, function(payload)
  local src = source
  local pending = waypointPending[src]
  if not pending or pending.source ~= src or pending.stage ~= 'marker' then return end
  if pending.expires < GetGameTimer() or not Core.hasPerm(src, 'tpgo') then
    waypointPending[src] = nil
    return
  end

  local requestId = type(payload) == 'table' and U.number(payload.request_id, 1) or nil
  local x = type(payload) == 'table' and U.number(payload.x, -9000, 9000) or nil
  local y = type(payload) == 'table' and U.number(payload.y, -9000, 9000) or nil
  if requestId ~= pending.request_id or requestId % 1 ~= 0 or not x or not y
      or not Core:rate(src, 'waypoint_begin', 250) then
    waypointPending[src] = nil
    return Core:notify(src, 'Marcador inválido.', 'erro')
  end

  pending.x = x
  pending.y = y
  pending.stage = 'ground'
  pending.expires = GetGameTimer() + 10000
  TriggerClientEvent(E.RESOLVE_WAYPOINT, src, {
    request_id = requestId,
    x = x,
    y = y,
  })
end)

RegisterNetEvent(E.ACT_TPWAYPOINT)
AddEventHandler(E.ACT_TPWAYPOINT, function(payload)
  local src = source
  local pending = waypointPending[src]
  waypointPending[src] = nil
  if not pending or pending.source ~= src or pending.stage ~= 'ground' then return end
  if pending.expires < GetGameTimer() or not Core.hasPerm(src, 'tpgo') then return end

  local requestId = type(payload) == 'table' and U.number(payload.request_id, 1) or nil
  local z = type(payload) == 'table' and U.number(payload.z, -200, 2000) or nil
  if requestId ~= pending.request_id or requestId % 1 ~= 0 or not z
      or not Core:rate(src, 'waypoint') then
    return Core:notify(src, 'Marcador inválido.', 'erro')
  end

  local pos = { x = pending.x, y = pending.y, z = z, h = pending.heading or 0.0 }
  if not U.validCoords(pos) then return Core:notify(src, 'Marcador inválido.', 'erro') end

  pushHistory(src)
  move(src, src, pos, 'tpgo', { request_id = requestId })
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
  waypointSequence[source] = nil
end)
