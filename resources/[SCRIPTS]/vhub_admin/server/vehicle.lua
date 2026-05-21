-- server/vehicle.lua  spawncar / delveh / fix / tuning / carcolor
-- Para opera  es em ve culos REGISTRADOS, delegamos ao vhub_garage (admin exports).
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local E    = VHubAdmin.E
local U    = VHubAdmin.U

local function reqPerm(src, k)
  if not Core.hasPerm(src, k) then Core.notify(src, 'Sem permiss o.'); return false end
  return true
end

RegisterNetEvent(E.ACT_SPAWNCAR)
AddEventHandler(E.ACT_SPAWNCAR, function(model)
  local src = source; if not reqPerm(src, 'spawncar') then return end
  model = U.safeText(tostring(model or ''):lower(), 32)
  if model == '' then Core.notify(src, 'Modelo vazio.'); return end
  TriggerClientEvent(E.DO_SPAWNCAR, src, model)
  Core:audit(src, 'spawncar', src, { model = model })
end)

RegisterNetEvent(E.ACT_DELVEH)
AddEventHandler(E.ACT_DELVEH, function()
  local src = source; if not reqPerm(src, 'delveh') then return end
  TriggerClientEvent(E.DO_DELVEH, src)
  Core:audit(src, 'delveh', src, {})
end)

RegisterNetEvent(E.ACT_FIX)
AddEventHandler(E.ACT_FIX, function()
  local src = source; if not reqPerm(src, 'fix') then return end
  TriggerClientEvent(E.DO_FIX, src)
  Core:audit(src, 'fix', src, {})
end)

RegisterNetEvent(E.ACT_TUNING)
AddEventHandler(E.ACT_TUNING, function()
  local src = source; if not reqPerm(src, 'tuning') then return end
  TriggerClientEvent(E.DO_TUNING, src)
  Core:audit(src, 'tuning', src, {})
end)

RegisterNetEvent(E.ACT_CARCOLOR)
AddEventHandler(E.ACT_CARCOLOR, function(r, g, b)
  local src = source; if not reqPerm(src, 'carcolor') then return end
  r = U.clamp(tonumber(r) or 0, 0, 255)
  g = U.clamp(tonumber(g) or 0, 0, 255)
  b = U.clamp(tonumber(b) or 0, 0, 255)
  TriggerClientEvent(E.DO_CARCOLOR, src, r, g, b)
  Core:audit(src, 'carcolor', src, { r = r, g = g, b = b })
end)
