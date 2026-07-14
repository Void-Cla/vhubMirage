-- server/spectator.lua - autorizacao de espectador sem movimentar o administrador
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local E = VHubAdmin.E

local watching = {}

local function stop(src, reason)
  local target = watching[src]
  if not target then return false end
  watching[src] = nil
  TriggerClientEvent(E.SPEC_STOP, src)
  if reason then Core:notify(src, reason, 'info') end
  return true
end

RegisterNetEvent(E.ACT_SPEC)
AddEventHandler(E.ACT_SPEC, function(rawTarget)
  local src = source
  if not Core:guard(src, 'spec', 'moderation') then return end

  if watching[src] then
    local target = watching[src]
    stop(src, 'Espectador encerrado.')
    Core:audit(src, 'spec_stop', target, {})
    return
  end

  local target = Core:onlineTarget(rawTarget)
  if not target or target == src then return Core:notify(src, 'Alvo indisponivel.', 'erro') end

  watching[src] = target
  TriggerClientEvent(E.SPEC_START, src, { target = target, keep = false })
  Core:notify(src, ('Espectando [%d].'):format(target), 'sucesso')
  Core:audit(src, 'spec_start', target, {})
end)

-- Reconfirma um espectador ativo sem aceitar coordenada nem estado do cliente.
RegisterNetEvent(E.SPEC_UPDATE)
AddEventHandler(E.SPEC_UPDATE, function()
  local src = source
  local target = watching[src]
  if not target then return end
  if not Core:rate(src, 'spec_update', 1000) then return end
  if not Core:onlineTarget(target) then
    stop(src, 'Alvo desconectou. Espectador encerrado.')
    return
  end
  TriggerClientEvent(E.SPEC_START, src, { target = target, keep = true })
end)

AddEventHandler('playerDropped', function()
  local dropped = tonumber(source)
  watching[dropped] = nil
  for adminSrc, target in pairs(watching) do
    if target == dropped then stop(adminSrc, 'Alvo desconectou. Espectador encerrado.') end
  end
end)
