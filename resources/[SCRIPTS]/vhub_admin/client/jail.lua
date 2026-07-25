-- client/jail.lua  reflexo visual do jail e bloqueio efêmero de controles
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state
local running = true

RegisterNetEvent(E.JAIL_APPLY)
AddEventHandler(E.JAIL_APPLY, function(data)
  if type(data) ~= 'table' then return end
  S.jail = { expires_at = tonumber(data.expires_at) or 0, pos = data.pos }
  VHubAdmin.notify('Você foi preso. ' .. (data.reason or ''))
end)

RegisterNetEvent(E.JAIL_RELEASE)
AddEventHandler(E.JAIL_RELEASE, function()
  S.jail = nil
  VHubAdmin.notify('Você foi liberado.')
end)

-- Suprimir tiro/ataque enquanto preso (frame loop só enquanto preso)
Citizen.CreateThread(function()
  while running do
    if not S.jail then Citizen.Wait(1000)
    else
      Citizen.Wait(0)
      if S.jail.expires_at <= os.time() then
        S.jail = nil
      else
        DisablePlayerFiring(PlayerId(), true)
        DisableControlAction(0, 24, true)   -- attack
        DisableControlAction(0, 25, true)   -- aim
        DisableControlAction(0, 47, true)   -- weapon
        DisableControlAction(0, 58, true)
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then running = false end
end)
