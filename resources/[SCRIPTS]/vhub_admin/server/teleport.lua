-- server/teleport.lua  tp / tptome / tpgo / tpcds / tpall / tplast
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local CFG  = VHubAdmin.cfg
local E    = VHubAdmin.E
local U    = VHubAdmin.U

-- hist rico de tp [src] = stack {x,y,z,h}
local Hist = {}
local function push(src, c)
  Hist[src] = Hist[src] or {}
  table.insert(Hist[src], { x = c.x, y = c.y, z = c.z, h = c.h or 0.0 })
  if #Hist[src] > CFG.limits.tp_history then table.remove(Hist[src], 1) end
end

-- TP at  jogador
RegisterNetEvent(E.ACT_TP)
AddEventHandler(E.ACT_TP, function(target)
  local src = source; if not Core.hasPerm(src, 'tp') then return end
  local t = U.toSrc(target); if not t then return end
  local c = Core.coordsOf(t); if not c then
    Core.notify(src, 'Alvo n o encontrado.'); return end
  local mine = Core.coordsOf(src)
  if mine then push(src, { x = mine.x, y = mine.y, z = mine.z }) end
  TriggerClientEvent(E.DO_TP, src, c.x, c.y + 1.5, c.z)
  Core:audit(src, 'tp', t, {})
end)

-- Trazer jogador
RegisterNetEvent(E.ACT_TPTOME)
AddEventHandler(E.ACT_TPTOME, function(target)
  local src = source; if not Core.hasPerm(src, 'bring') then return end
  local t = U.toSrc(target); if not t then return end
  local c = Core.coordsOf(src); if not c then return end
  TriggerClientEvent(E.DO_TP, t, c.x, c.y + 1.5, c.z)
  Core.notify(t, 'Voc  foi teleportado por um admin.')
  Core:audit(src, 'tptome', t, {})
end)

-- TP para waypoint (cliente resolve coords + colis o)
RegisterNetEvent(E.ACT_TPGO)
AddEventHandler(E.ACT_TPGO, function()
  local src = source; if not Core.hasPerm(src, 'tpgo') then return end
  local c = Core.coordsOf(src)
  if c then push(src, { x = c.x, y = c.y, z = c.z }) end
  TriggerClientEvent(E.DO_TP, src, nil, nil, nil, 'waypoint')
  Core:audit(src, 'tpgo', nil, {})
end)

-- TP para coordenadas
RegisterNetEvent(E.ACT_TPCDS)
AddEventHandler(E.ACT_TPCDS, function(x, y, z, h)
  local src = source; if not Core.hasPerm(src, 'tpcds') then return end
  if not U.validCoords({ x = x, y = y, z = z }) then
    Core.notify(src, 'Coordenadas inv lidas.'); return
  end
  local c = Core.coordsOf(src)
  if c then push(src, { x = c.x, y = c.y, z = c.z }) end
  TriggerClientEvent(E.DO_TP, src, tonumber(x), tonumber(y), tonumber(z), nil, tonumber(h) or 0.0)
  Core:audit(src, 'tpcds', nil, { x = x, y = y, z = z })
end)

-- Trazer todos a mim
RegisterNetEvent(E.ACT_TPALL)
AddEventHandler(E.ACT_TPALL, function()
  local src = source; if not Core.hasPerm(src, 'tpall') then return end
  local c = Core.coordsOf(src); if not c then return end
  for _, s in ipairs(GetPlayers()) do
    s = tonumber(s)
    if s and s ~= src then
      TriggerClientEvent(E.DO_TP, s, c.x, c.y + 1.5, c.z)
    end
  end
  Core:audit(src, 'tpall', nil, {})
end)

-- Voltar  posi  o anterior
RegisterNetEvent(E.ACT_TPLAST)
AddEventHandler(E.ACT_TPLAST, function()
  local src = source; if not Core.hasPerm(src, 'tp') then return end
  local stack = Hist[src]
  if not stack or #stack == 0 then
    Core.notify(src, 'Sem hist rico de teleporte.'); return
  end
  local prev = table.remove(stack)
  TriggerClientEvent(E.DO_TP, src, prev.x, prev.y, prev.z, nil, prev.h)
  Core:audit(src, 'tplast', nil, {})
end)

AddEventHandler('playerDropped', function() Hist[source] = nil end)
