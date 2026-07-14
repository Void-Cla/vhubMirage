-- client/player.lua - efeitos efemeros autorizados pelo servidor
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state
local running = true
local buffRunning = false

local function syncFlags()
  VHubAdmin.syncUi({
    noclip = S.noclip,
    god = S.god,
    freeze = S.freeze,
    invis = S.invis,
    stamina = S.stamina,
    jump = S.jump,
  })
end

local function ensureBuffThread()
  if buffRunning or not (S.stamina or S.jump) then return end
  buffRunning = true
  Citizen.CreateThread(function()
    while running and (S.stamina or S.jump) do
      if S.stamina then RestorePlayerStamina(PlayerId(), 1.0) end
      if S.jump then
        SetSuperJumpThisFrame(PlayerId())
        Citizen.Wait(0)
      else
        Citizen.Wait(250)
      end
    end
    buffRunning = false
  end)
end

RegisterNetEvent(E.TOGGLE_GOD)
AddEventHandler(E.TOGGLE_GOD, function()
  S.god = not S.god
  local ped = PlayerPedId()
  SetPlayerInvincible(PlayerId(), S.god)
  SetEntityInvincible(ped, S.god)
  SetPedCanRagdoll(ped, not S.god)
  SetEntityProofs(ped, S.god, S.god, S.god, S.god, S.god, S.god, S.god, S.god)
  VHubAdmin.notify(S.god and 'Invencibilidade ativada.' or 'Invencibilidade desativada.')
  syncFlags()
end)

RegisterNetEvent(E.TOGGLE_STAMINA)
AddEventHandler(E.TOGGLE_STAMINA, function()
  S.stamina = not S.stamina
  ensureBuffThread()
  VHubAdmin.notify(S.stamina and 'Stamina ativada.' or 'Stamina desativada.')
  syncFlags()
end)

RegisterNetEvent(E.TOGGLE_JUMP)
AddEventHandler(E.TOGGLE_JUMP, function()
  S.jump = not S.jump
  ensureBuffThread()
  VHubAdmin.notify(S.jump and 'Super pulo ativado.' or 'Super pulo desativado.')
  syncFlags()
end)

RegisterNetEvent(E.TOGGLE_FREEZE)
AddEventHandler(E.TOGGLE_FREEZE, function(force)
  if force == false then S.freeze = false else S.freeze = not S.freeze end
  FreezeEntityPosition(PlayerPedId(), S.freeze)
  VHubAdmin.notify(S.freeze and 'Voce foi congelado.' or 'Voce foi descongelado.')
  syncFlags()
end)

RegisterNetEvent(E.TOGGLE_INVIS)
AddEventHandler(E.TOGGLE_INVIS, function()
  S.invis = not S.invis
  SetEntityVisible(PlayerPedId(), not S.invis, false)
  VHubAdmin.notify(S.invis and 'Invisibilidade ativada.' or 'Invisibilidade desativada.')
  syncFlags()
end)

RegisterNetEvent(E.DO_CLEANPED)
AddEventHandler(E.DO_CLEANPED, function()
  local ped = PlayerPedId()
  ClearPedBloodDamage(ped)
  ResetPedVisibleDamage(ped)
  ClearPedWetness(ped)
  ClearPedEnvDirt(ped)
end)

AddEventHandler('vhub_admin:cleanupEffects', function()
  S.god, S.freeze, S.invis, S.stamina, S.jump = false, false, false, false, false
  local ped = PlayerPedId()
  SetPlayerInvincible(PlayerId(), false)
  SetEntityInvincible(ped, false)
  SetEntityProofs(ped, false, false, false, false, false, false, false, false)
  SetPedCanRagdoll(ped, true)
  SetEntityVisible(ped, true, false)
  ResetEntityAlpha(ped)
  FreezeEntityPosition(ped, false)
  syncFlags()
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then running = false end
end)

RegisterCommand('god', function()
  if S.is_admin then TriggerServerEvent(E.ACT_GOD) end
end, false)

RegisterCommand('heal', function(_, args)
  if not S.is_admin then return end
  TriggerServerEvent(E.ACT_HEAL, tonumber(args[1]))
end, false)

RegisterCommand('healall', function()
  if S.is_admin then TriggerServerEvent(E.ACT_HEALALL) end
end, false)

RegisterCommand('revive', function(_, args)
  if S.is_admin then TriggerServerEvent(E.ACT_REVIVE, tonumber(args[1])) end
end, false)

RegisterCommand('reviveall', function()
  if S.is_admin then TriggerServerEvent(E.ACT_REVIVEALL) end
end, false)

RegisterCommand('freeze', function(_, args)
  if S.is_admin and tonumber(args[1]) then TriggerServerEvent(E.ACT_FREEZE, tonumber(args[1])) end
end, false)

RegisterCommand('invis', function()
  if S.is_admin then TriggerServerEvent(E.ACT_INVIS) end
end, false)

RegisterCommand('stamina', function()
  if S.is_admin then TriggerServerEvent(E.ACT_STAMINA) end
end, false)

RegisterCommand('superjump', function()
  if S.is_admin then TriggerServerEvent(E.ACT_JUMP) end
end, false)

RegisterCommand('cleanped', function()
  if S.is_admin then TriggerServerEvent(E.ACT_CLEANPED) end
end, false)

RegisterCommand('kill', function(_, args)
  if S.is_admin and tonumber(args[1]) then TriggerServerEvent(E.ACT_KILL, tonumber(args[1])) end
end, false)
