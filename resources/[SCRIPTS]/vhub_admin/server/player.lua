-- server/player.lua  heal / god / freeze / revive / invisible / skin / kill
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local E    = VHubAdmin.E
local U    = VHubAdmin.U

local function reqPerm(src, k)
  if not Core.hasPerm(src, k) then
    Core.notify(src, 'Sem permiss o.'); return false
  end
  return true
end

RegisterNetEvent(E.ACT_HEAL)
AddEventHandler(E.ACT_HEAL, function(target)
  local src = source; if not reqPerm(src, 'heal') then return end
  local t = U.toSrc(target) or src
  TriggerClientEvent(E.DO_HEAL, t)
  if t ~= src then
    Core.notify(src, ('[%d] curado.'):format(t))
    Core.notify(t, 'Voc  foi curado por um admin.')
  end
  Core:audit(src, 'heal', t, {})
end)

RegisterNetEvent(E.ACT_HEALALL)
AddEventHandler(E.ACT_HEALALL, function()
  local src = source; if not reqPerm(src, 'heal') then return end
  for _, s in ipairs(GetPlayers()) do TriggerClientEvent(E.DO_HEAL, tonumber(s)) end
  Core:audit(src, 'healall', nil, {})
end)

RegisterNetEvent(E.ACT_GOD)
AddEventHandler(E.ACT_GOD, function()
  local src = source; if not reqPerm(src, 'god') then return end
  TriggerClientEvent(E.TOGGLE_GOD, src)
  Core:audit(src, 'god', src, {})
end)

RegisterNetEvent(E.ACT_FREEZE)
AddEventHandler(E.ACT_FREEZE, function(target)
  local src = source; if not reqPerm(src, 'freeze') then return end
  local t = U.toSrc(target); if not t then return end
  TriggerClientEvent(E.TOGGLE_FREEZE, t)
  Core.notify(src, ('[%d] toggle freeze.'):format(t))
  Core:audit(src, 'freeze', t, {})
end)

RegisterNetEvent(E.ACT_REVIVE)
AddEventHandler(E.ACT_REVIVE, function(target)
  local src = source; if not reqPerm(src, 'revive') then return end
  local t = U.toSrc(target) or src
  TriggerClientEvent(E.DO_REVIVE, t)
  Core.notify(src, ('[%d] revivido.'):format(t))
  if t ~= src then Core.notify(t, 'Voc  foi revivido por um admin.') end
  Core:audit(src, 'revive', t, {})
end)

RegisterNetEvent(E.ACT_REVIVEALL)
AddEventHandler(E.ACT_REVIVEALL, function()
  local src = source; if not reqPerm(src, 'revive') then return end
  for _, s in ipairs(GetPlayers()) do TriggerClientEvent(E.DO_REVIVE, tonumber(s)) end
  Core:audit(src, 'reviveall', nil, {})
end)

RegisterNetEvent(E.ACT_INVIS)
AddEventHandler(E.ACT_INVIS, function()
  local src = source; if not reqPerm(src, 'invisible') then return end
  TriggerClientEvent(E.TOGGLE_INVIS, src)
  Core:audit(src, 'invis', src, {})
end)

RegisterNetEvent(E.ACT_SKIN)
AddEventHandler(E.ACT_SKIN, function(target, model)
  local src = source; if not reqPerm(src, 'skin') then return end
  local t = U.toSrc(target) or src
  model = U.safeText(tostring(model or ''), 32)
  if model == '' then Core.notify(src, 'Model vazio.'); return end
  TriggerClientEvent(E.DO_SKIN, t, model)
  Core:audit(src, 'skin', t, { model = model })
end)

RegisterNetEvent(E.ACT_KILL)
AddEventHandler(E.ACT_KILL, function(target)
  local src = source; if not reqPerm(src, 'god') then return end
  local t = U.toSrc(target); if not t then return end
  TriggerClientEvent(E.TOGGLE_FREEZE, t, false)  -- destrava se travado
  local ped = GetPlayerPed(tostring(t))
  if ped and ped ~= 0 then SetEntityHealth(ped, 0) end
  Core.notify(src, ('[%d] morto.'):format(t))
  Core:audit(src, 'kill', t, {})
end)
