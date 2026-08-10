-- client/init.lua - estado efemero, foco NUI e capacidade administrativa
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local UI = VHubAdmin.UI

VHubAdmin.state = {
  ready = false,
  is_admin = false,
  hotkey = 'F6',
  actions = {},
  selectors = {},
  panel_open = false,
  wall_enabled = false,
  noclip = false,
  god = false,
  freeze = false,
  invis = false,
  stamina = false,
  jump = false,
  spec_target = nil,
  jail = nil,
}
local S = VHubAdmin.state
local focus_lock_running = false

local function lockPanelControls()
  if focus_lock_running then return end
  focus_lock_running = true
  Citizen.CreateThread(function()
    while S.panel_open do
      DisableAllControlActions(0)
      DisableAllControlActions(1)
      DisableAllControlActions(2)
      Citizen.Wait(0)
    end
    focus_lock_running = false
  end)
end

local function setAdminCapability(active)
  active = active == true
  local revoked = S.is_admin and not active
  S.is_admin = active
  if revoked then
    VHubAdmin.closePanel()
    TriggerEvent(E.CLEANUP_EFFECTS)
  end
end

-- Exibe notificacao local sem usar a NUI como fonte de verdade.
function VHubAdmin.notify(message)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(message or ''))
  EndTextCommandThefeedPostTicker(false, true)
end

-- Envia estado visual apenas quando o painel esta aberto.
function VHubAdmin.syncUi(data)
  if S.panel_open then SendNUIMessage({ action = UI.STATE_SYNC, data = data or {} }) end
end

RegisterNetEvent(E.NOTIFY)
AddEventHandler(E.NOTIFY, function(message, kind)
  VHubAdmin.notify(message)
  if S.panel_open then SendNUIMessage({ action = UI.TOAST, data = { text = message, kind = kind } }) end
end)

RegisterNetEvent(E.SETUP)
AddEventHandler(E.SETUP, function(setup)
  if type(setup) ~= 'table' then return end
  S.hotkey = type(setup.hotkey) == 'string' and setup.hotkey or 'F6'
  S.actions = type(setup.actions) == 'table' and setup.actions or {}
  S.selectors = type(setup.selectors) == 'table' and setup.selectors or {}
  setAdminCapability(setup.is_admin)
  S.ready = true
  if setup.open == true and S.is_admin then VHubAdmin.openPanel() end
end)

-- Atalho fixo registrado pelo FiveM; o servidor continua sendo a fronteira de permissao.
RegisterCommand('admin', function()
  if S.panel_open then return VHubAdmin.closePanel() end
  TriggerServerEvent(E.OPEN_PANEL)
end, false)
RegisterKeyMapping('admin', 'Abrir painel administrativo vHub', 'keyboard', 'F6')

-- Abre a NUI somente apos receber capacidade do servidor.
function VHubAdmin.openPanel()
  if not S.is_admin or S.panel_open then return end
  S.panel_open = true
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
  lockPanelControls()
  SendNUIMessage({
    action = UI.OPEN,
    data = {
      actions = S.actions,
      selectors = S.selectors,
      flags = {
        noclip = S.noclip,
        god = S.god,
        freeze = S.freeze,
        invis = S.invis,
        stamina = S.stamina,
        jump = S.jump,
      },
    },
  })
end

-- Fecha foco e libera o runtime visual.
function VHubAdmin.closePanel()
  if not S.panel_open then return end
  S.panel_open = false
  SetNuiFocusKeepInput(false)
  SetNuiFocus(false, false)
  SendNUIMessage({ action = UI.CLOSE })
end

RegisterNUICallback('close', function(_, cb)
  VHubAdmin.closePanel()
  cb({ ok = true })
end)

-- State Bag replica apenas a capacidade; toda acao continua validada no servidor.
AddStateBagChangeHandler('vhub_is_admin', nil, function(bagName, _, value)
  if bagName ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
  setAdminCapability(value)
end)

Citizen.CreateThread(function()
  Citizen.Wait(0)
  setAdminCapability(LocalPlayer.state.vhub_is_admin)
end)

AddEventHandler(VHubHSS.E.SPAWNED, function()
  TriggerEvent(E.CLEANUP_EFFECTS)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  VHubAdmin.closePanel()
  TriggerEvent(E.CLEANUP_EFFECTS)
end)
