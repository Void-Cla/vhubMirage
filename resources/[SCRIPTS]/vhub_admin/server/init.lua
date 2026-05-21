-- server/init.lua  bootstrap do vhub_admin
---@diagnostic disable: undefined-global

local SQL  = VHubAdmin.SQL
local Core = VHubAdmin.Core
local CFG  = VHubAdmin.cfg
local E    = VHubAdmin.E

local _pronto = false

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    SQL:initSchema()
    -- aguarda core vHub
    for _ = 1, 50 do
      if Core:vHub() then _pronto = true; break end
      Citizen.Wait(200)
    end
    if not _pronto then
      print('[vhub_admin][ERRO] vHub n o dispon vel ap s 10s')
      return
    end
    -- envia setup p/ jogadores online (restart em produ  o)
    for _, s in ipairs(GetPlayers()) do
      local src = tonumber(s)
      Core:syncAdminBag(src)
      TriggerClientEvent(E.SETUP, src, {
        hotkey  = CFG.hotkey_open,
        actions = VHubAdmin.ACTIONS,
      })
    end
    print('[vhub_admin] pronto')
  end)
end)

-- sess es vivas
AddEventHandler('vHub:characterLoad', function(user)
  Core:setSession(user.source, user)
  Core:syncAdminBag(user.source)
end)

AddEventHandler('vHub:playerSpawn', function(user)
  Core:setSession(user.source, user)
  Core:syncAdminBag(user.source)
  TriggerClientEvent(E.SETUP, user.source, {
    hotkey  = CFG.hotkey_open,
    actions = VHubAdmin.ACTIONS,
  })
  -- aplica jail se char ainda preso
  Citizen.CreateThread(function()
    if not user.char_id then return end
    local j = SQL:jailGet(user.char_id)
    if j and tonumber(j.expires_at) > os.time() then
      TriggerClientEvent(E.JAIL_APPLY, user.source,
        { expires_at = j.expires_at, pos = CFG.jail_pos })
    end
  end)
end)

AddEventHandler('playerDropped', function()
  Core:dropSession(source)
end)

-- evento "abrir painel"
RegisterNetEvent(E.OPEN_PANEL)
AddEventHandler(E.OPEN_PANEL, function()
  local src = source
  if not _pronto then return end
  if not Core.hasPerm(src, 'panel') then
    Core.notify(src, 'Sem permiss o de administrador.'); return
  end
  TriggerClientEvent(E.IS_ADMIN, src, true)
end)

-- cron: libera jail/mute expirados (60s)
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(60 * 1000)
    Citizen.CreateThread(function()
      local rows = SQL:jailListExpired() or {}
      for _, r in ipairs(rows) do
        SQL:jailRemove(r.char_id)
        -- se online, libera no client
        for src, u in pairs(Core.sessions) do
          if u.char_id == r.char_id then
            TriggerClientEvent(E.JAIL_RELEASE, src); break
          end
        end
      end
      local m = SQL:muteListExpired() or {}
      for _, r in ipairs(m) do SQL:muteRemove(r.char_id) end
    end)
  end
end)
