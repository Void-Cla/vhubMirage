-- client/noclip.lua — noclip com god+invis automáticos e 3 velocidades
--   W sozinho = ~5 m/s (corrida de ped)   ctrl+W = lento (~1 m/s)   shift+W = ~28 m/s (100 km/h)
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

-- velocidades em m/frame (assume 60 fps)
local SP_SLOW  = 0.017  -- ctrl+W — rastejamento (~1 m/s)
local SP_NORM  = 0.083  -- W puro — corrida de ped (~5 m/s)
local SP_FAST  = 0.467  -- shift+W — ~28 m/s aprox 100 km/h

-- controles bloqueados durante voo (lidos via IsDisabledControlPressed)
local DISABLED_CTRL = { 30, 31, 32, 33, 34, 35, 21, 22, 36, 24, 25 }

local CTRL_FWD   = 32   -- W
local CTRL_BACK  = 33   -- S
local CTRL_LEFT  = 34   -- A
local CTRL_RIGHT = 35   -- D
local CTRL_SHIFT = 21   -- LSHIFT — velocidade rapida + sobe via camera
local CTRL_SPACE = 22   -- SPACE  — sobe verticalmente
local CTRL_CTRL  = 36   -- LCTRL  — velocidade lenta + desce

local function checkAdmin()
  if S.is_admin then return true end
  VHubAdmin.notify('Sem permissao.'); return false
end

local function getNoclipEntity(ped)
  if IsPedInAnyVehicle(ped, false) then
    return GetVehiclePedIsIn(ped, false), true
  end
  return ped, false
end

local function rayGroundZ(x, y, fromZ)
  fromZ = fromZ or 900.0
  RequestCollisionAtCoord(x, y, fromZ)
  local t = 0
  while not HasCollisionLoadedAroundEntity(PlayerPedId()) and t < 1500 do
    Citizen.Wait(50); t = t + 50
  end
  local handle = StartExpensiveSynchronousShapeTestLosProbe(
    x, y, fromZ, x, y, -500.0, 1, PlayerPedId(), 4)
  local _, hit, endCoords = GetShapeTestResult(handle)
  if hit == 1 or hit == true then return endCoords.z end
  for z = fromZ, 0.0, -25.0 do
    local ok, gz = GetGroundZFor_3dCoord(x, y, z, false)
    if ok and gz ~= 0.0 then return gz end
  end
end


local function enable(ped)
  local ent, isVehicle = getNoclipEntity(ped)
  S.noclip = true

  S.god = true
  SetPlayerInvincible(PlayerId(), true)
  SetEntityProofs(ent, true, true, true, true, true, true, true, true)
  if isVehicle then SetEntityProofs(ped, true, true, true, true, true, true, true, true) end

  S.invis = true
  SetEntityVisible(ped, false, false)
  SetEntityAlpha(ped, 0, false)
  NetworkSetEntityInvisibleToNetwork(ped, true)
  SetEntityLocallyInvisible(ped)
  if isVehicle then
    SetEntityVisible(ent, false, false)
    SetEntityAlpha(ent, 0, false)
    NetworkSetEntityInvisibleToNetwork(ent, true)
  end

  SetEntityCollision(ent, false, false)
  SetEntityHasGravity(ent, false)
  SetEntityVelocity(ent, 0.0, 0.0, 0.0)
  FreezeEntityPosition(ent, false)
  if isVehicle then SetEntityCollision(ped, false, false) end
end

local function disable(ped)
  local ent, isVehicle = getNoclipEntity(ped)
  S.noclip = false

  S.god = false
  SetPlayerInvincible(PlayerId(), false)
  SetEntityProofs(ent, false, false, false, false, false, false, false, false)
  if isVehicle then SetEntityProofs(ped, false, false, false, false, false, false, false, false) end

  S.invis = false
  SetEntityVisible(ped, true, false)
  SetEntityAlpha(ped, 255, false)
  NetworkSetEntityInvisibleToNetwork(ped, false)
  if isVehicle then
    SetEntityVisible(ent, true, false)
    SetEntityAlpha(ent, 255, false)
    NetworkSetEntityInvisibleToNetwork(ent, false)
  end

  Citizen.CreateThread(function()
    Citizen.Wait(50)
    local c = GetEntityCoords(ent)
    local gz = rayGroundZ(c.x, c.y, c.z + 30.0)
    if gz then
      SetEntityCoordsNoOffset(ent, c.x, c.y, gz + (isVehicle and 1.0 or 0.05), false, false, false)
    end
    ClearPedTasksImmediately(ped)
    SetEntityCollision(ent, true, true)
    SetEntityHasGravity(ent, true)
    SetEntityVelocity(ent, 0.0, 0.0, -1.0)
    FreezeEntityPosition(ent, false)
  end)
end


local function toggleNoclip()
  local ped = PlayerPedId()
  if S.noclip then disable(ped) else enable(ped) end
  VHubAdmin.notify(S.noclip and 'Noclip ON — god+invis' or 'Noclip OFF')
  SendNUIMessage({
    action = VHubAdmin.UI.STATE_SYNC,
    data   = { noclip = S.noclip, god = S.god, invis = S.invis },
  })
end

RegisterNetEvent(E.TOGGLE_NOCLIP)
AddEventHandler(E.TOGGLE_NOCLIP, toggleNoclip)

RegisterCommand('nc',     function() if checkAdmin() then toggleNoclip() end end, false)
RegisterCommand('noclip', function() if checkAdmin() then toggleNoclip() end end, false)

-- tecla N (control 311) — toggle rapido sem abrir painel
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if IsControlJustPressed(0, 311) and S.is_admin then
      toggleNoclip()
    end
  end
end)


Citizen.CreateThread(function()
  while true do
    if not S.noclip then
      Citizen.Wait(200)
    else
      Citizen.Wait(0)
      local ped = PlayerPedId()
      local ent = getNoclipEntity(ped)

      SetEntityCollision(ent, false, false)
      SetEntityHasGravity(ent, false)

      for _, c in ipairs(DISABLED_CTRL) do DisableControlAction(0, c, true) end

      local holdCtrl  = IsDisabledControlPressed(0, CTRL_CTRL)
      local holdShift = IsDisabledControlPressed(0, CTRL_SHIFT)
      local sp
      if holdCtrl then
        sp = SP_SLOW
      elseif holdShift then
        sp = SP_FAST
      else
        sp = SP_NORM
      end

      local cam = GetGameplayCamRot(2)
      local rx, rz = math.rad(cam.x), math.rad(cam.z)
      local fx = -math.sin(rz) * math.cos(rx)
      local fy =  math.cos(rz) * math.cos(rx)
      local fz =  math.sin(rx)
      local sx =  math.cos(rz)
      local sy =  math.sin(rz)

      local dx, dy, dz = 0.0, 0.0, 0.0

      if IsDisabledControlPressed(0, CTRL_FWD) then
        dx = dx + fx * sp; dy = dy + fy * sp; dz = dz + fz * sp
      end
      if IsDisabledControlPressed(0, CTRL_BACK) then
        dx = dx - fx * sp; dy = dy - fy * sp; dz = dz - fz * sp
      end
      if IsDisabledControlPressed(0, CTRL_LEFT)  then dx = dx - sx * sp; dy = dy - sy * sp end
      if IsDisabledControlPressed(0, CTRL_RIGHT) then dx = dx + sx * sp; dy = dy + sy * sp end

      if IsDisabledControlPressed(0, CTRL_SPACE) then dz = dz + sp end
      if holdCtrl and not IsDisabledControlPressed(0, CTRL_FWD) then dz = dz - SP_SLOW end

      local pos = GetEntityCoords(ent)
      SetEntityCoordsNoOffset(ent, pos.x + dx, pos.y + dy, pos.z + dz, false, false, false)
      SetEntityHeading(ent, cam.z % 360.0)
    end
  end
end)
