-- client/init.lua  bootstrap, state global, NUI focus, notifica  o
---@diagnostic disable: undefined-global

local E  = VHubAdmin.E
local UI = VHubAdmin.UI

VHubAdmin.state = {
  pronto      = false,
  is_admin    = false,
  hotkey      = 'F6',
  actions     = {},
  noclip      = false,
  god         = false,
  freeze      = false,
  invis       = false,
  panel_open  = false,
  spec_target = nil,
  jail        = nil,   -- { expires_at, pos }
}
local S = VHubAdmin.state

-- ----------------------------------------------------------------------------
-- Notifica  o
-- ----------------------------------------------------------------------------
function VHubAdmin.notify(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg or ''))
  EndTextCommandThefeedPostTicker(false, true)
end

RegisterNetEvent(E.NOTIFY)
AddEventHandler(E.NOTIFY, function(msg) VHubAdmin.notify(msg) end)

RegisterNetEvent(E.SETUP)
AddEventHandler(E.SETUP, function(setup)
  if type(setup) ~= 'table' then return end
  S.hotkey  = setup.hotkey  or 'F6'
  S.actions = setup.actions or {}
  S.pronto  = true
  TriggerEvent('vhub_admin:setupReady')
end)

RegisterNetEvent(E.IS_ADMIN)
AddEventHandler(E.IS_ADMIN, function(v)
  S.is_admin = v == true
  if S.is_admin then VHubAdmin.openPanel() end
end)

-- atalho 'admin' + hotkey via RegisterKeyMapping
RegisterCommand('admin', function()
  if S.panel_open then VHubAdmin.closePanel()
  else TriggerServerEvent(E.OPEN_PANEL) end
end, false)
RegisterKeyMapping('admin', 'Abrir painel admin (vHub)', 'keyboard', 'F6')

-- ----------------------------------------------------------------------------
-- NUI open/close (centralizado)
-- ----------------------------------------------------------------------------
function VHubAdmin.openPanel(view)
  S.panel_open = true
  SetNuiFocus(true, true)
  SendNUIMessage({
    action = UI.OPEN,
    data = {
      view    = view or 'dashboard',
      actions = S.actions,
      flags   = {
        noclip = S.noclip, god = S.god, freeze = S.freeze, invis = S.invis,
      },
    },
  })
end

function VHubAdmin.closePanel()
  if not S.panel_open then return end
  S.panel_open = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = UI.CLOSE })
end

RegisterNUICallback('close', function(_, cb)
  VHubAdmin.closePanel(); cb({ ok = true })
end)

-- ----------------------------------------------------------------------------
-- State Bag bridge: admin acordou
-- ----------------------------------------------------------------------------
AddStateBagChangeHandler('vhub_is_admin', ('player:%s'):format(GetPlayerServerId(PlayerId())),
  function(_, _, value)
    S.is_admin = value == true
  end)

-- aliases  sync flags ap s respawn
AddEventHandler('vhub_player_state:spawned', function()
  -- limpa efeitos client-side perigosos para n o ficar travado
  if S.noclip then S.noclip = false end
  if S.god    then S.god    = false; SetPlayerInvincible(PlayerId(), false) end
  if S.freeze then S.freeze = false; FreezeEntityPosition(PlayerPedId(), false) end
  if S.invis  then S.invis  = false; SetEntityVisible(PlayerPedId(), true, false) end
end)
