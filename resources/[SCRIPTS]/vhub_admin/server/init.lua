-- server/init.lua — ciclo de vida replay-safe do vhub_admin
---@diagnostic disable: undefined-global

local SQL = VHubAdmin.SQL
local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E

VHubAdmin.ready = false

local seenSpawn = {}

-- Envia somente capacidades e seletores que o servidor autorizou.
local function sendSetup(src, open)
  Core:syncAdminBag(src)
  TriggerClientEvent(E.SETUP, src, {
    hotkey = CFG.hotkey_open,
    is_admin = Core.hasPerm(src, 'panel'),
    open = open == true,
    actions = Core:allowedActions(src),
    selectors = Core:selectors(),
  })
end

-- Reidrata uma sessão existente quando o resource reinicia.
local function recoverSession(src)
  local ok, user = pcall(function() return exports.vhub:getUser(src) end)
  if ok and type(user) == 'table' and user.char_id then
    Core:setSession(src, user)
    if VHubAdmin.Moderation then VHubAdmin.Moderation:hydrate(src, user) end
    sendSetup(src, false)
  end
end

AddEventHandler('onResourceStart', function(resource)
  if resource ~= GetCurrentResourceName() then return end

  Citizen.CreateThread(function()
    if not SQL:initSchema() then return end

    for _ = 1, 50 do
      local ok, status = pcall(function() return exports.vhub:Status() end)
      if ok and type(status) == 'table' then
        VHubAdmin.ready = true
        break
      end
      Citizen.Wait(200)
    end
    if not VHubAdmin.ready then return end

    if VHubAdmin.Moderation then VHubAdmin.Moderation:hydrateActive() end
    for _, raw in ipairs(GetPlayers()) do recoverSession(tonumber(raw)) end
  end)
end)

-- Mantém a sessão atualizada; a operação é idempotente em replay institucional.
AddEventHandler('vHub:characterLoad', function(user)
  if type(user) ~= 'table' or not user.source then return end
  Core:setSession(user.source, user)
  if VHubAdmin.Moderation then VHubAdmin.Moderation:hydrate(user.source, user) end
  if VHubAdmin.ready then sendSetup(user.source, false) end
end)

-- Envia setup somente em spawn novo; restart já passa por recoverSession.
AddEventHandler('vHub:playerSpawn', function(user)
  if type(user) ~= 'table' or not user.source then return end
  local src = tonumber(user.source)
  local spawn = tonumber(user.spawns) or 0
  Core:setSession(src, user)

  if seenSpawn[src] == spawn then return end
  seenSpawn[src] = spawn

  if VHubAdmin.Moderation then VHubAdmin.Moderation:hydrate(src, user) end
  if VHubAdmin.ready then sendSetup(src, false) end
end)

AddEventHandler('playerDropped', function()
  local src = source
  seenSpawn[src] = nil
  if VHubAdmin.Moderation then VHubAdmin.Moderation:drop(src) end
  Core:dropSession(src)
end)

RegisterNetEvent(E.OPEN_PANEL)
AddEventHandler(E.OPEN_PANEL, function()
  local src = source
  if not VHubAdmin.ready or not Core:guard(src, 'panel', 'panel') then return end
  sendSetup(src, true)
end)
