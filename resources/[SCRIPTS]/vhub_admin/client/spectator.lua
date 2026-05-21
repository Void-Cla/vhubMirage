-- client/spectator.lua  /spec <id>: NetworkSetInSpectatorMode + HUD info
---@diagnostic disable: undefined-global

local E  = VHubAdmin.E
local UI = VHubAdmin.UI
local S  = VHubAdmin.state

local _origin = nil  -- coords originais antes do spec

local function startSpec(data)
  local pid = GetPlayerFromServerId(data.target)
  if pid == -1 then
    if data.coords then
      local ped = PlayerPedId()
      if not _origin then
        local c = GetEntityCoords(ped)
        _origin = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped) }
      end
      SetEntityCoordsNoOffset(ped, data.coords.x, data.coords.y, data.coords.z, false, false, false)
    end
    return
  end
  if not _origin then
    local c = GetEntityCoords(PlayerPedId())
    _origin = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(PlayerPedId()) }
  end
  local tped = GetPlayerPed(pid)
  if not tped or tped == 0 then return end
  NetworkSetInSpectatorMode(true, tped)
  S.spec_target = data.target
  if not data.keep then
    VHubAdmin.notify(('Espectando [%d]. /spec novamente para sair.'):format(data.target))
  end
  SendNUIMessage({ action = UI.SPEC_HUD, data = { target = data.target, on = true } })
end

local function stopSpec()
  NetworkSetInSpectatorMode(false, 0)
  if _origin then
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, _origin.x, _origin.y, _origin.z, false, false, false)
    SetEntityHeading(ped, _origin.h or 0.0)
    _origin = nil
  end
  S.spec_target = nil
  SendNUIMessage({ action = UI.SPEC_HUD, data = { on = false } })
end

RegisterNetEvent(E.SPEC_START)
AddEventHandler(E.SPEC_START, startSpec)

RegisterNetEvent(E.SPEC_STOP)
AddEventHandler(E.SPEC_STOP, stopSpec)

-- pede update peri dico ao servidor (alvo se moveu / OOS)
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(2000)
    if S.spec_target then TriggerServerEvent(E.SPEC_UPDATE) end
  end
end)

-- comando
RegisterCommand('spec', function(_, args)
  if not S.is_admin then return end
  local t = tonumber(args[1])
  if S.spec_target then TriggerServerEvent(E.ACT_SPEC, S.spec_target); return end
  if t then TriggerServerEvent(E.ACT_SPEC, t)
  else VHubAdmin.notify('Uso: /spec <id>') end
end, false)

-- HUD durante o spec
Citizen.CreateThread(function()
  while true do
    if not S.spec_target then Citizen.Wait(500)
    else
      Citizen.Wait(0)
      SetTextScale(0.32, 0.32); SetTextFont(4); SetTextProportional(true)
      SetTextColour(255, 220, 80, 220); SetTextOutline()
      SetTextEntry('STRING')
      AddTextComponentString(('  Espectando ID %d   /spec para sair'):format(S.spec_target))
      DrawText(0.5, 0.02)
    end
  end
end)
