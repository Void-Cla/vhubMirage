-- client/overlay.lua - projecao efemera das informacoes administrativas no mundo
---@diagnostic disable: undefined-global

local CFG = VHubAdmin.cfg.wall
local E = VHubAdmin.E
local S = VHubAdmin.state
local UI = VHubAdmin.UI

local alive = true
local rows = {}
local mugshots = {}
local nextSnapshotAt = 0

local function clearOverlay()
  SendNUIMessage({ action = UI.OVERLAY_CLEAR })
  for ped, entry in pairs(mugshots) do
    if entry.handle then pcall(UnregisterPedheadshot, entry.handle) end
    mugshots[ped] = nil
  end
end

local function indexRows(rawRows)
  local indexed = {}
  if type(rawRows) ~= 'table' then return indexed end

  for index, row in ipairs(rawRows) do
    local src = type(row) == 'table' and tonumber(row.src) or nil
    if src and src > 0 and index <= CFG.max_players then indexed[src] = row end
  end
  return indexed
end

local function mugshotUrl(ped)
  local entry = mugshots[ped]
  if not entry then
    local handle = RegisterPedheadshot(ped)
    if not handle or handle == 0 then return nil end
    entry = { handle = handle }
    mugshots[ped] = entry
  end

  if entry.txd then return ('nui-img://%s/%s'):format(entry.txd, entry.txd) end
  if not IsPedheadshotValid(entry.handle) or not IsPedheadshotReady(entry.handle) then return nil end

  local txd = GetPedheadshotTxdString(entry.handle)
  if not txd or txd == '' then return nil end
  entry.txd = txd
  return ('nui-img://%s/%s'):format(txd, txd)
end

local function collectVisiblePlayers()
  local me = PlayerPedId()
  local origin = GetEntityCoords(me)
  local visible = {}
  local activeMugs = {}

  for _, player in ipairs(GetActivePlayers()) do
    local src = GetPlayerServerId(player)
    local info = rows[src]
    if info then
      local ped = GetPlayerPed(player)
      if ped ~= 0 and DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        if #(origin - coords) <= CFG.draw_distance then
          local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.35)
          local onScreen, screenX, screenY = World3dToScreen2d(head.x, head.y, head.z)
          if onScreen then
            activeMugs[ped] = true
            visible[#visible + 1] = {
              src = src,
              hp = math.max(0, math.min(100, GetEntityHealth(ped) - 100)),
              sx = screenX,
              sy = screenY,
              mugshot = mugshotUrl(ped),
            }
          end
        end
      end
    end
  end

  for ped, entry in pairs(mugshots) do
    if not activeMugs[ped] then
      if entry.handle then pcall(UnregisterPedheadshot, entry.handle) end
      mugshots[ped] = nil
    end
  end

  return visible
end

RegisterNetEvent(E.WALL_STATE)
AddEventHandler(E.WALL_STATE, function(enabled, snapshot)
  S.wall_enabled = enabled == true and S.is_admin
  rows = S.wall_enabled and indexRows(snapshot) or {}
  nextSnapshotAt = GetGameTimer() + CFG.refresh_ms

  if S.wall_enabled then
    SendNUIMessage({ action = UI.OVERLAY_SNAPSHOT, data = snapshot })
    VHubAdmin.notify('Wall administrativo ativado.')
  else
    clearOverlay()
    VHubAdmin.notify('Wall administrativo desativado.')
  end
end)

RegisterNetEvent(E.WALL_SNAPSHOT)
AddEventHandler(E.WALL_SNAPSHOT, function(snapshot)
  if not S.wall_enabled or not S.is_admin then return end
  rows = indexRows(snapshot)
  SendNUIMessage({ action = UI.OVERLAY_SNAPSHOT, data = snapshot })
end)

Citizen.CreateThread(function()
  local cleared = true
  while alive do
    if not S.wall_enabled or not S.is_admin then
      if not cleared then clearOverlay(); cleared = true end
      Citizen.Wait(1000)
    else
      cleared = false
      local now = GetGameTimer()
      if now >= nextSnapshotAt then
        nextSnapshotAt = now + CFG.refresh_ms
        TriggerServerEvent(E.REQ_WALL_SNAPSHOT)
      end

      SendNUIMessage({ action = UI.OVERLAY_UPDATE, data = collectVisiblePlayers() })
      Citizen.Wait(CFG.update_ms)
    end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  alive = false
  S.wall_enabled = false
  clearOverlay()
end)
