-- client/jail.lua  reflexo visual do jail e bloqueio efêmero de controles
---@diagnostic disable: undefined-global

local S = VHubAdmin.state
local running = true

-- Reflete a prisão a partir da State Bag do próprio jogador (servidor é o escritor único:
-- Player(src).state:set('vhub_admin_jail', payload, true) em server/moderation.lua). O client só
-- ESPELHA o estado autoritativo (L-01/L-02) — nunca decide prender/soltar. Cobre late-join e
-- reconexão (a bag replicada chega no set inicial). Mesmo padrão de vhub_admin_world (world.lua).
AddStateBagChangeHandler('vhub_admin_jail', nil, function(bagName, _, data)
  if bagName ~= ('player:' .. GetPlayerServerId(PlayerId())) then return end
  if type(data) == 'table' then
    S.jail = { expires_at = tonumber(data.expires_at) or 0, pos = data.pos }
    VHubAdmin.notify('Você foi preso. ' .. (data.reason or ''))
  else
    if S.jail then VHubAdmin.notify('Você foi liberado.') end
    S.jail = nil
  end
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
