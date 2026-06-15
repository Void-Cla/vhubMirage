---@diagnostic disable: undefined-global, lowercase-global

-- client/init.lua — HAL do tablet: toggle, NuiFocus e relay NUI↔servidor.
-- Cliente NÃO decide verdade: abre pedindo ao servidor (REQUEST_OPEN), e toda
-- mutação (install/uninstall/pref) é só intenção repassada ao servidor.

local E      = VHubIpadE
local isOpen = false


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- aplica abertura recebida do servidor (payload = catálogo + estado per-char)
local function applyOpen(payload)
  isOpen = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', data = payload })
end

-- fecha o tablet (libera foco + avisa servidor)
local function closeIpad()
  if not isOpen then return end
  isOpen = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
  TriggerServerEvent('vhub_ipad:sv:closed')
end


-- ============================================================
-- EVENTOS DE REDE (servidor → cliente)
-- ============================================================

RegisterNetEvent(E.OPEN, applyOpen)

-- estado per-char atualizado após mutação (instalar/remover app)
RegisterNetEvent(E.STATE, function(data)
  if isOpen then SendNUIMessage({ action = 'state', data = data }) end
end)

-- fechar de fora (export closeIpad / handoff)
RegisterNetEvent(E.FORCE_CLOSE, closeIpad)


-- ============================================================
-- COMANDO / KEYMAP
-- ============================================================

RegisterCommand('ipad', function()
  if isOpen then closeIpad() else TriggerServerEvent(E.REQUEST_OPEN) end
end, false)

RegisterKeyMapping('ipad', 'Abrir / Fechar iPad', 'keyboard', 'F1')


-- ============================================================
-- NUI CALLBACKS (intenção da NUI → servidor)
-- ============================================================

-- fechar pela NUI (botão × ou ESC)
RegisterNUICallback('close', function(_, cb)
  closeIpad()
  cb({ ok = true })
end)

-- instalar app removível (loja)
RegisterNUICallback('install', function(data, cb)
  if data and type(data.id) == 'string' then TriggerServerEvent(E.INSTALL, data.id) end
  cb({ ok = true })
end)

-- remover app removível (loja)
RegisterNUICallback('uninstall', function(data, cb)
  if data and type(data.id) == 'string' then TriggerServerEvent(E.UNINSTALL, data.id) end
  cb({ ok = true })
end)

-- salvar preferência de UI (zoom/wallpaper) — servidor valida e persiste
RegisterNUICallback('setPref', function(data, cb)
  if type(data) == 'table' then TriggerServerEvent(E.SET_PREF, data) end
  cb({ ok = true })
end)

-- NUI sinaliza que está pronta (handshake; sem payload de negócio)
RegisterNUICallback('nui_ready', function(_, cb)
  cb({ ok = true })
end)


-- ============================================================
-- RELAY — app embutido ↔ server do resource dono (broker no servidor do iPad)
-- ============================================================

-- app (NUI) → server: o cliente só repassa a intenção; o servidor autoriza e roteia
RegisterNUICallback('appRelay', function(data, cb)
  if data and type(data.app) == 'string' and type(data.action) == 'string' then
    TriggerServerEvent(E.APP_RELAY, data.app, data.action, data.data)
  end
  cb({ ok = true })
end)

-- server do resource dono → app (NUI): repassa o push para a NUI (só com o tablet aberto)
RegisterNetEvent(E.APP_PUSH, function(payload)
  if isOpen then SendNUIMessage({ action = 'appPush', data = payload }) end
end)
