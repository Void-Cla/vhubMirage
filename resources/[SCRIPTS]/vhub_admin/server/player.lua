-- server/player.lua — ferramentas de staff sem criar escritor paralelo de ped
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local E = VHubAdmin.E

local function targetOrSelf(src, raw)
  if raw == nil or raw == '' then return src end
  return Core:onlineTarget(raw)
end

RegisterNetEvent(E.ACT_HEAL)
AddEventHandler(E.ACT_HEAL, function(target)
  local src = source
  if not Core:guard(src, 'heal', 'moderation') then return end
  local targetSrc = targetOrSelf(src, target)
  if not targetSrc or not Core:heal(targetSrc) then
    return Core:notify(src, 'Não foi possível curar o alvo.', 'erro')
  end
  Core:notify(src, ('[%d] curado.'):format(targetSrc), 'sucesso')
  if targetSrc ~= src then Core:notify(targetSrc, 'Você foi curado pela equipe.', 'sucesso') end
  Core:audit(src, 'heal', targetSrc, {})
end)

RegisterNetEvent(E.ACT_HEALALL)
AddEventHandler(E.ACT_HEALALL, function()
  local src = source
  if not Core:guard(src, 'heal', 'moderation') then return end
  Citizen.CreateThread(function()
    local count = 0
    for _, raw in ipairs(GetPlayers()) do
      if Core:heal(tonumber(raw)) then count = count + 1 end
      if count % 25 == 0 then Citizen.Wait(0) end
    end
    Core:audit(src, 'healall', nil, { count = count })
    Core:notify(src, ('%d jogadores curados.'):format(count), 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_GOD)
AddEventHandler(E.ACT_GOD, function()
  local src = source
  if not Core:guard(src, 'god', 'moderation') then return end
  TriggerClientEvent(E.TOGGLE_GOD, src)
  Core:audit(src, 'god', src, {})
end)

RegisterNetEvent(E.ACT_NOCLIP)
AddEventHandler(E.ACT_NOCLIP, function()
  local src = source
  if not Core:guard(src, 'noclip', 'moderation') then return end
  TriggerClientEvent(E.TOGGLE_NOCLIP, src)
  Core:audit(src, 'noclip', src, {})
end)

RegisterNetEvent(E.ACT_FREEZE)
AddEventHandler(E.ACT_FREEZE, function(target)
  local src = source
  if not Core:guard(src, 'freeze', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  if not targetSrc then return Core:notify(src, 'Alvo inválido.', 'erro') end
  TriggerClientEvent(E.TOGGLE_FREEZE, targetSrc)
  Core:audit(src, 'freeze', targetSrc, {})
end)

RegisterNetEvent(E.ACT_REVIVE)
AddEventHandler(E.ACT_REVIVE, function(target)
  local src = source
  if not Core:guard(src, 'revive', 'moderation') then return end
  local targetSrc = targetOrSelf(src, target)
  if not targetSrc or not Core:revive(targetSrc) then
    return Core:notify(src, 'Não foi possível reviver o alvo.', 'erro')
  end
  Core:notify(src, ('[%d] revivido.'):format(targetSrc), 'sucesso')
  Core:audit(src, 'revive', targetSrc, {})
end)

RegisterNetEvent(E.ACT_REVIVEALL)
AddEventHandler(E.ACT_REVIVEALL, function()
  local src = source
  if not Core:guard(src, 'revive', 'moderation') then return end
  Citizen.CreateThread(function()
    local count = 0
    for _, raw in ipairs(GetPlayers()) do
      if Core:revive(tonumber(raw)) then count = count + 1 end
      if count % 25 == 0 then Citizen.Wait(0) end
    end
    Core:audit(src, 'reviveall', nil, { count = count })
    Core:notify(src, ('%d jogadores revividos.'):format(count), 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_INVIS)
AddEventHandler(E.ACT_INVIS, function()
  local src = source
  if not Core:guard(src, 'invisible', 'moderation') then return end
  TriggerClientEvent(E.TOGGLE_INVIS, src)
  Core:audit(src, 'invis', src, {})
end)

RegisterNetEvent(E.ACT_STAMINA)
AddEventHandler(E.ACT_STAMINA, function()
  local src = source
  if not Core:guard(src, 'buff', 'moderation') then return end
  TriggerClientEvent(E.TOGGLE_STAMINA, src)
  Core:audit(src, 'stamina', src, {})
end)

RegisterNetEvent(E.ACT_JUMP)
AddEventHandler(E.ACT_JUMP, function()
  local src = source
  if not Core:guard(src, 'buff', 'moderation') then return end
  TriggerClientEvent(E.TOGGLE_JUMP, src)
  Core:audit(src, 'jump', src, {})
end)

RegisterNetEvent(E.ACT_CLEANPED)
AddEventHandler(E.ACT_CLEANPED, function()
  local src = source
  if not Core:guard(src, 'heal', 'moderation') then return end
  TriggerClientEvent(E.DO_CLEANPED, src)
  Core:audit(src, 'cleanped', src, {})
end)

RegisterNetEvent(E.ACT_SKIN)
AddEventHandler(E.ACT_SKIN, function(rawTarget, rawModel)
  local src = source
  if not Core:guard(src, 'skin', 'moderation') then return end
  local targetSrc = Core:onlineTarget(rawTarget)
  if not targetSrc then return Core:notify(src, 'Alvo inválido.', 'erro') end
  local model = VHubAdmin.U.identifier(rawModel, 64)
  if not model then return Core:notify(src, 'Modelo inválido.', 'erro') end

  local ok = false
  pcall(function() ok = exports.vhub_player_state:setPedModel(targetSrc, model) end)
  if not ok then return Core:notify(src, 'Skin recusada pelo owner de ped.', 'erro') end
  Core:notify(src, ('[%d] skin %s aplicada.'):format(targetSrc, model), 'sucesso')
  Core:audit(src, 'skin', targetSrc, { model = model })
end)

RegisterNetEvent(E.ACT_KILL)
AddEventHandler(E.ACT_KILL, function(target)
  local src = source
  if not Core:guard(src, 'god', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  if not targetSrc then return Core:notify(src, 'Alvo inválido.', 'erro') end
  TriggerClientEvent(E.TOGGLE_FREEZE, targetSrc, false)
  local ok = false
  pcall(function() ok = exports.vhub_player_state:kill(targetSrc) end)
  if not ok then return Core:notify(src, 'Ped indisponível.', 'erro') end
  Core:audit(src, 'kill', targetSrc, {})
  Core:notify(src, ('[%d] eliminado.'):format(targetSrc), 'sucesso')
end)
