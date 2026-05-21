-- client/jail.lua  aplica  o local do jail (teleporte fixo + bloqueio de a  es)
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

RegisterNetEvent(E.JAIL_APPLY)
AddEventHandler(E.JAIL_APPLY, function(data)
  if type(data) ~= 'table' then return end
  S.jail = { expires_at = tonumber(data.expires_at) or 0, pos = data.pos }
  local p = data.pos
  if p then
    local ped = PlayerPedId()
    SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
    SetEntityHeading(ped, p.h or 0.0)
  end
  VHubAdmin.notify('Voc  foi preso. ' .. (data.reason or ''))
end)

RegisterNetEvent(E.JAIL_RELEASE)
AddEventHandler(E.JAIL_RELEASE, function()
  S.jail = nil
  VHubAdmin.notify('Voc  foi liberado.')
end)

-- thread: mant m no per metro do jail e bloqueia armas (1Hz)
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(2000)
    if S.jail then
      if S.jail.expires_at <= os.time() then S.jail = nil
      else
        local ped = PlayerPedId()
        local c   = GetEntityCoords(ped)
        local p   = S.jail.pos
        if p and #(c - vector3(p.x, p.y, p.z)) > 30.0 then
          SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
          VHubAdmin.notify('Voc  ainda est  preso.')
        end
        DisablePlayerFiring(PlayerId(), true)
      end
    end
  end
end)

-- Suprimir tiro/ataque enquanto preso (16ms frame loop s  enquanto preso)
Citizen.CreateThread(function()
  while true do
    if not S.jail then Citizen.Wait(500)
    else
      Citizen.Wait(0)
      DisableControlAction(0, 24, true)   -- attack
      DisableControlAction(0, 25, true)   -- aim
      DisableControlAction(0, 47, true)   -- weapon
      DisableControlAction(0, 58, true)
    end
  end
end)
