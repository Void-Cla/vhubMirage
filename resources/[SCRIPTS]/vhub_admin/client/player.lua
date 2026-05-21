-- client/player.lua  heal, god, freeze, revive, invis, skin
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

local function isAdm() return S.is_admin end

-- ----------------------------------------------------------------------------
-- HEAL
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.DO_HEAL)
AddEventHandler(E.DO_HEAL, function()
  local ped = PlayerPedId()
  SetEntityHealth(ped, 200)
  SetPedArmour(ped, 100)
  ClearPedBloodDamage(ped)
  VHubAdmin.notify('HP e colete restaurados.')
end)

-- ----------------------------------------------------------------------------
-- GOD
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.TOGGLE_GOD)
AddEventHandler(E.TOGGLE_GOD, function()
  S.god = not S.god
  SetPlayerInvincible(PlayerId(), S.god)
  SetEntityProofs(PlayerPedId(), S.god, S.god, S.god, S.god, S.god, S.god, S.god, S.god)
  VHubAdmin.notify(S.god and 'God ATIVADO' or 'God DESATIVADO')
  SendNUIMessage({ action = VHubAdmin.UI.STATE_SYNC, data = { god = S.god } })
end)

-- ----------------------------------------------------------------------------
-- FREEZE (do alvo)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.TOGGLE_FREEZE)
AddEventHandler(E.TOGGLE_FREEZE, function(force)
  if force == false then
    S.freeze = false; FreezeEntityPosition(PlayerPedId(), false)
    VHubAdmin.notify('Descongelado.')
    return
  end
  S.freeze = not S.freeze
  FreezeEntityPosition(PlayerPedId(), S.freeze)
  VHubAdmin.notify(S.freeze and 'Voc  foi congelado por um admin.' or 'Voc  foi descongelado.')
end)

-- ----------------------------------------------------------------------------
-- INVIS
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.TOGGLE_INVIS)
AddEventHandler(E.TOGGLE_INVIS, function()
  S.invis = not S.invis
  SetEntityVisible(PlayerPedId(), not S.invis, false)
  VHubAdmin.notify(S.invis and 'Invis vel.' or 'Vis vel.')
  SendNUIMessage({ action = VHubAdmin.UI.STATE_SYNC, data = { invis = S.invis } })
end)

-- ----------------------------------------------------------------------------
-- REVIVE
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.DO_REVIVE)
AddEventHandler(E.DO_REVIVE, function()
  local ped = PlayerPedId()
  local c = GetEntityCoords(ped)
  NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
  SetEntityHealth(ped, 200); SetPedArmour(ped, 100); ClearPedBloodDamage(ped)
  VHubAdmin.notify('Revivido.')
end)

-- ----------------------------------------------------------------------------
-- SKIN
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.DO_SKIN)
AddEventHandler(E.DO_SKIN, function(model)
  Citizen.CreateThread(function()
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then VHubAdmin.notify('Skin inv lida.'); return end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 5000 do Citizen.Wait(50); t = t + 50 end
    if not HasModelLoaded(hash) then VHubAdmin.notify('Skin n o carregou.'); return end
    SetPlayerModel(PlayerId(), hash)
    SetPedDefaultComponentVariation(PlayerPedId())
    SetModelAsNoLongerNeeded(hash)
    VHubAdmin.notify('Skin alterada: ' .. model)
  end)
end)

-- ----------------------------------------------------------------------------
-- Comandos slash
-- ----------------------------------------------------------------------------
RegisterCommand('god', function()
  if not isAdm() then return end
  TriggerServerEvent(E.ACT_GOD)
end, false)

RegisterCommand('heal', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_HEAL, t)
  else
    local ped = PlayerPedId()
    SetEntityHealth(ped, 200); SetPedArmour(ped, 100); ClearPedBloodDamage(ped)
    VHubAdmin.notify('HP restaurado.')
  end
end, false)

RegisterCommand('healall', function()
  if not isAdm() then return end
  TriggerServerEvent(E.ACT_HEALALL)
end, false)

RegisterCommand('revive', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_REVIVE, t)
  else TriggerServerEvent(E.ACT_REVIVE, GetPlayerServerId(PlayerId())) end
end, false)

RegisterCommand('reviveall', function()
  if not isAdm() then return end
  TriggerServerEvent(E.ACT_REVIVEALL)
end, false)

RegisterCommand('freeze', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_FREEZE, t) end
end, false)

RegisterCommand('unfreeze', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_FREEZE, t) end
end, false)

RegisterCommand('invis', function()
  if not isAdm() then return end
  TriggerServerEvent(E.ACT_INVIS)
end, false)

RegisterCommand('skin', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  local m = args[2]
  if t and m then TriggerServerEvent(E.ACT_SKIN, t, m)
  elseif args[1] and not tonumber(args[1]) then
    TriggerServerEvent(E.ACT_SKIN, GetPlayerServerId(PlayerId()), args[1])
  else VHubAdmin.notify('Uso: /skin <modelo>  ou  /skin <id> <modelo>') end
end, false)

RegisterCommand('kill', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_KILL, t) end
end, false)
