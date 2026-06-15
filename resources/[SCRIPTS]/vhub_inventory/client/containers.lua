---@diagnostic disable: undefined-global, lowercase-global

-- client/containers.lua — HAL de baús (L2): markers de baú fixo + porta-malas.
-- Servidor valida tudo; aqui so desenho, proximidade, tecla e animacao da tampa.

local E = VHubInvE

local _open     = false
local _trunkVeh = nil     -- veiculo cujo porta-malas esta aberto (anim da tampa)
local _running  = true    -- saida deterministica da thread de markers (L-06)


-- ============================================================
-- HELPERS
-- ============================================================

-- texto 3D leve (projecao de mundo -> tela)
local function drawText3D(x, y, z, text)
  local on, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
  if not on then return end
  SetTextScale(0.35, 0.35); SetTextFont(4); SetTextColour(255, 255, 255, 215)
  SetTextOutline(); SetTextCentre(true)
  SetTextEntry('STRING'); AddTextComponentString(text)
  DrawText(sx, sy)
end

-- fecha o baú: tira foco, avisa servidor, fecha a tampa
local function closeChest()
  if not _open then return end
  _open = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'container_close' })
  TriggerServerEvent(E.CLOSE_CONTAINER)
  if _trunkVeh and DoesEntityExist(_trunkVeh) then SetVehicleDoorShut(_trunkVeh, 5, false) end
  _trunkVeh = nil
end


-- ============================================================
-- SERVIDOR -> NUI
-- ============================================================

RegisterNetEvent(E.CONTAINER_OPEN)
AddEventHandler(E.CONTAINER_OPEN, function(data)
  _open = true
  SetNuiFocus(true, true)
  if _trunkVeh and DoesEntityExist(_trunkVeh) then SetVehicleDoorOpen(_trunkVeh, 5, false, false) end
  SendNUIMessage({ action = 'container_open', data = data })
end)

RegisterNetEvent(E.CONTAINER_DELTA)
AddEventHandler(E.CONTAINER_DELTA, function(d)
  SendNUIMessage({ action = 'container_delta', delta = d })
end)

RegisterNetEvent(E.CONTAINER_CLOSE)
AddEventHandler(E.CONTAINER_CLOSE, function() closeChest() end)


-- ============================================================
-- NUI -> SERVIDOR (intencao)
-- ============================================================

RegisterNUICallback('container_close', function(_, cb) closeChest(); cb('ok') end)

RegisterNUICallback('store', function(d, cb)
  TriggerServerEvent(E.STORE, { from = d.from, to = d.to, qty = d.qty })
  cb('ok')
end)

RegisterNUICallback('retrieve', function(d, cb)
  TriggerServerEvent(E.RETRIEVE, { from = d.from, to = d.to, qty = d.qty })
  cb('ok')
end)


-- ============================================================
-- BAÚS DA CONFIG (coletados uma vez) + deteccao de range
-- ============================================================

local function collectChests()
  local list = {}
  for name, c in pairs(Inventory.Chests and Inventory.Chests.static or {}) do
    list[#list + 1] = { kind = 'static', key = name, coords = c.coords, range = c.range or 2.0, label = c.label or name }
  end
  for grp, c in pairs(Inventory.Chests and Inventory.Chests.faction or {}) do
    list[#list + 1] = { kind = 'faction', key = grp, coords = c.coords, range = c.range or 2.5, label = c.label or grp }
  end
  return list
end

local _chests = collectChests()

-- baú fixo/faccao dentro do range? retorna o desc de abertura ou nil
local function chestInRange()
  local ppos = GetEntityCoords(PlayerPedId())
  for _, ch in ipairs(_chests) do
    if #(ppos - vector3(ch.coords.x, ch.coords.y, ch.coords.z)) <= ch.range then
      return {
        kind  = ch.kind,
        name  = ch.kind == 'static'  and ch.key or nil,
        group = ch.kind == 'faction' and ch.key or nil,
      }
    end
  end
  return nil
end

-- veiculo no range do porta-malas? retorna o veiculo ou nil
local function vehicleInRange()
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return GetVehiclePedIsIn(ped, false) end
  local p = GetEntityCoords(ped)
  local c = GetClosestVehicle(p.x, p.y, p.z, Inventory.Trunk.range or 5.5, 0, 71)
  return (c and c ~= 0) and c or nil
end


-- ============================================================
-- TECLA UNIFICADA 'I' — baú fixo perto > porta-malas perto > mochila
-- ============================================================

RegisterCommand('vhub_inv', function()
  if _open or IsNuiFocused() then return end   -- ja aberto / outra NUI no foco

  local chest = chestInRange()
  if chest then TriggerServerEvent(E.OPEN_CONTAINER, chest); return end

  local veh = vehicleInRange()
  if veh then
    local plate = GetVehicleNumberPlateText(veh)   -- nativa client-side confiavel
    if plate then
      _trunkVeh = veh
      -- netId p/ o servidor validar distancia (best-effort); placa decide o acesso
      TriggerServerEvent(E.OPEN_CONTAINER, {
        kind  = 'trunk',
        plate = plate:gsub('%s+$', ''),
        netId = NetworkGetNetworkIdFromEntity(veh),
      })
      return
    end
  end

  TriggerEvent('vhub_inventory:open_backpack')      -- nada perto: abre a mochila
end, false)

RegisterKeyMapping('vhub_inv', 'Abrir inventario / baú', 'keyboard', 'I')


-- ============================================================
-- MARKERS dos baús fixos (visual; abrir e via 'I') — proximity-gated
-- ============================================================

CreateThread(function()
  if #_chests == 0 then return end   -- sem baús fixos: thread nem roda (resmon 0)

  while _running do
    local sleep = 1000
    local ppos  = GetEntityCoords(PlayerPedId())

    for _, ch in ipairs(_chests) do
      local d = #(ppos - vector3(ch.coords.x, ch.coords.y, ch.coords.z))
      if d < 15.0 then
        sleep = 0   -- thread esquenta sozinha quando ha baú perto
        DrawMarker(1, ch.coords.x, ch.coords.y, ch.coords.z - 0.95, 0,0,0, 0,0,0,
          0.5, 0.5, 0.4, 248, 200, 105, 180, false, false, 2, false, nil, nil, false)
        if d < ch.range and not _open then
          drawText3D(ch.coords.x, ch.coords.y, ch.coords.z + 0.25, '[I] ' .. ch.label)
        end
      end
    end

    Wait(sleep)
  end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  _running = false                       -- encerra a thread de markers (L-06)
  if _open then SetNuiFocus(false, false) end
end)
