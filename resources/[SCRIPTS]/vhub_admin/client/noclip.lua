-- client/noclip.lua  noclip "pacote completo" (god + invis + voo)
--   ativar: god mode on, invis on, gravity off, collision off, voa via velocity
--   desativar: restaura tudo + procura ch o + entrega no solo
---@diagnostic disable: undefined-global

local E   = VHubAdmin.E
local CFG = VHubAdmin.cfg
local S   = VHubAdmin.state

local function checkAdmin()
  if S.is_admin then return true end
  VHubAdmin.notify('Sem permiss o.'); return false
end

-- Raycast vertical para ch o REAL (ignora estruturas via flags=1 = world)
-- Mais confi vel que GetGroundZFor_3dCoord, que pega teto/quintal/ponte.
local function rayGroundZ(x, y, fromZ)
  fromZ = fromZ or 900.0
  RequestCollisionAtCoord(x + 0.0, y + 0.0, fromZ)
  local t = 0
  while not HasCollisionLoadedAroundEntity(PlayerPedId()) and t < 1500 do
    Citizen.Wait(50); t = t + 50
  end
  -- shape test: flags=1 (world only, ignora veh culos e props din micos)
  local handle = StartExpensiveSynchronousShapeTestLosProbe(
    x + 0.0, y + 0.0, fromZ,
    x + 0.0, y + 0.0, -500.0,
    1, PlayerPedId(), 4)
  local _, hit, endCoords = GetShapeTestResult(handle)
  if hit == 1 or hit == true then return endCoords.z end
  -- fallback: native cl ssica
  for z = fromZ, 0.0, -25.0 do
    local ok, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 0.0, false)
    if ok and gz ~= 0.0 then return gz end
  end
end

local function enable(ped)
  S.noclip = true
  -- god mode
  if not S.god then
    S.god = true
    SetPlayerInvincible(PlayerId(), true)
    SetEntityProofs(ped, true, true, true, true, true, true, true, true)
  end
  -- invisibilidade
  if not S.invis then
    S.invis = true
    SetEntityVisible(ped, false, false)
    SetEntityLocallyInvisible(ped)
  end
  -- voo
  SetEntityCollision(ped, false, false)
  SetEntityHasGravity(ped, false)
  SetEntityVelocity(ped, 0.0, 0.0, 0.0)
  FreezeEntityPosition(ped, false)
end

local function disable(ped)
  -- 1) sinaliza para a thread principal parar de aplicar voo
  S.noclip = false
  -- 2) restaura god/invis (pacote completo)
  if S.god then
    S.god = false
    SetPlayerInvincible(PlayerId(), false)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
  end
  if S.invis then
    S.invis = false
    SetEntityVisible(ped, true, false)
  end
  -- 3) descida ao ch o de verdade (raycast + clear tasks + gravity)
  Citizen.CreateThread(function()
    Citizen.Wait(50)  -- garante que a thread de voo j  saiu do else-branch
    local c  = GetEntityCoords(ped)
    local gz = rayGroundZ(c.x, c.y, c.z + 30.0)
    if gz then
      -- snap exato ao ch o (sem offset) e clear area para descarregar f sicas residuais
      SetEntityCoordsNoOffset(ped, c.x, c.y, gz + 0.05, false, false, false)
      ClearAreaOfEverything(c.x, c.y, gz, 3.0, false, false, false, false)
    end
    -- agora restaura collision/gravity e limpa tasks (matar qualquer estado animado)
    ClearPedTasksImmediately(ped)
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetEntityVelocity(ped, 0.0, 0.0, -1.0)  -- empurr o para a engine recalcular ground
    FreezeEntityPosition(ped, false)
  end)
end

local function toggleNoclip()
  local ped = PlayerPedId()
  if S.noclip then disable(ped) else enable(ped) end
  VHubAdmin.notify(S.noclip and 'Noclip ATIVADO (god+invis)' or 'Noclip DESATIVADO')
  SendNUIMessage({
    action = VHubAdmin.UI.STATE_SYNC,
    data = { noclip = S.noclip, god = S.god, invis = S.invis },
  })
end

RegisterNetEvent(E.TOGGLE_NOCLIP)
AddEventHandler(E.TOGGLE_NOCLIP, toggleNoclip)

RegisterCommand('nc',     function() if checkAdmin() then toggleNoclip() end end, false)
RegisterCommand('noclip', function() if checkAdmin() then toggleNoclip() end end, false)

-- thread ativa s  quando noclip == true
-- IMPORTANTE: desabilitamos controles de movimento via DisableControlAction
-- e LEMOS via IsDisabledControlPressed (caso contr rio IsControlPressed retorna
-- false para qualquer controle desabilitado).
Citizen.CreateThread(function()
  -- bindings (control id   eixo, sinal)
  -- 32 = W (forward)   33 = S (back)   34 = A (strafe left)   35 = D (strafe right)
  -- 44 = Q (up)        38 = E (down)
  -- 21 = SHIFT (fast)  19 = CTRL alt (slow) (usamos 36 = SPRINT? n o, INPUT_DUCK)
  -- Usaremos 21 = SPRINT (shift) p/ acelerar, 19 = INPUT_VEH_CIN_CAM (alt) p/ devagar
  local DISABLED = { 30, 31, 32, 33, 34, 35, 44, 38, 21, 19, 22, 24, 25, 36 }
  while true do
    if not S.noclip then
      Citizen.Wait(250)
    else
      Citizen.Wait(0)
      local ped = PlayerPedId()
      -- garante estado de voo (alguns scripts resetam por frame)
      SetEntityCollision(ped, false, false)
      SetEntityHasGravity(ped, false)
      for _, c in ipairs(DISABLED) do DisableControlAction(0, c, true) end

      local sp = CFG.noclip.speed_norm
      if IsDisabledControlPressed(0, 21) then sp = CFG.noclip.speed_fast end  -- shift
      if IsDisabledControlPressed(0, 19) then sp = CFG.noclip.speed_slow end  -- alt

      local cam = GetGameplayCamRot(2)
      local rx, rz = math.rad(cam.x), math.rad(cam.z)
      local fx = -math.sin(rz) * math.cos(rx)
      local fy =  math.cos(rz) * math.cos(rx)
      local fz =  math.sin(rx)
      local sxx =  math.cos(rz)
      local syy =  math.sin(rz)

      local dx, dy, dz = 0.0, 0.0, 0.0
      if IsDisabledControlPressed(0, 32) then dx=dx+fx*sp; dy=dy+fy*sp; dz=dz+fz*sp end  -- W
      if IsDisabledControlPressed(0, 33) then dx=dx-fx*sp; dy=dy-fy*sp; dz=dz-fz*sp end  -- S
      if IsDisabledControlPressed(0, 34) then dx=dx-sxx*sp; dy=dy-syy*sp end             -- A
      if IsDisabledControlPressed(0, 35) then dx=dx+sxx*sp; dy=dy+syy*sp end             -- D
      if IsDisabledControlPressed(0, 44) then dz=dz+sp end                                -- Q (up)
      if IsDisabledControlPressed(0, 38) then dz=dz-sp end                                -- E (down)

      SetEntityVelocity(ped, dx, dy, dz)
      -- alinha o ped  c mera (visual)
      SetEntityHeading(ped, cam.z % 360.0)
    end
  end
end)
