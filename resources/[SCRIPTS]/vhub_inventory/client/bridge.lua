---@diagnostic disable: undefined-global, lowercase-global

-- client/bridge.lua — ponte Lua <-> NUI (L2 HAL).
-- So foco, abertura/fechamento e relay de INTENCAO. Nao decide nada de critico.

local E = VHubInvE

local _open = false


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- pede snapshot ao servidor; o foco e a UI sobem quando o OPEN chega (sem cursor preso)
local function openBackpack()
  if _open then return end
  TriggerServerEvent(E.REQUEST_SYNC)
end

-- fecha foco e avisa a NUI
local function closeBackpack()
  if not _open then return end
  _open = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
end


-- ============================================================
-- SERVIDOR -> NUI
-- ============================================================

-- snapshot completo (abre a mochila)
RegisterNetEvent(E.OPEN)
AddEventHandler(E.OPEN, function(snap)
  _open = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', snap = snap })
end)

-- diff incremental de slots (mochila/baú)
RegisterNetEvent(E.DELTA)
AddEventHandler(E.DELTA, function(delta)
  SendNUIMessage({ action = 'delta', delta = delta })
end)

-- rollback: estado autoritativo dos slots tocados + razao
RegisterNetEvent(E.ROLLBACK)
AddEventHandler(E.ROLLBACK, function(data)
  SendNUIMessage({ action = 'rollback', data = data })
end)

-- notificacao PT-BR
RegisterNetEvent(E.NOTIFY)
AddEventHandler(E.NOTIFY, function(msg)
  SendNUIMessage({ action = 'notify', msg = msg })
end)


-- ============================================================
-- NUI -> SERVIDOR (intencao) / handshake
-- ============================================================

-- handshake: NUI pronta -> recebe catalogo + CDN + dimensoes (uma vez)
RegisterNUICallback('nui_ready', function(_, cb)
  cb({
    catalog = Inventory.Items,
    cdn     = Inventory.CDN,
    size    = Inventory.Backpack.slots,
    max     = Inventory.Backpack.max_weight,
    hotbar  = Inventory.Hotbar.slots,
  })
  TriggerEvent('vhub_inventory:hud_refresh')   -- empurra o HUD assim que a NUI existe
end)

RegisterNUICallback('close', function(_, cb)
  closeBackpack()
  cb('ok')
end)

RegisterNUICallback('use', function(d, cb)
  TriggerServerEvent(E.USE, { slot = d.slot, id = d.id })
  cb('ok')
end)

RegisterNUICallback('move', function(d, cb)
  TriggerServerEvent(E.MOVE, { from = d.from, to = d.to, qty = d.qty })
  cb('ok')
end)


-- ============================================================
-- HOTBAR (atalhos 1-5)
-- ============================================================

-- binds vindos do servidor -> NUI
RegisterNetEvent(E.HOTBAR)
AddEventHandler(E.HOTBAR, function(binds)
  SendNUIMessage({ action = 'hotbar', binds = binds })
end)

-- NUI pede vincular/limpar um slot da hotbar (arrastar item p/ a barra)
RegisterNUICallback('set_bind', function(d, cb)
  TriggerServerEvent(E.SET_BIND, { slot = d.slot, id = d.id })
  cb('ok')
end)

-- teclas configuraveis: usar item da hotbar (nao enquanto ha NUI no foco)
for i = 1, (Inventory.Hotbar.slots or 5) do
  RegisterCommand('vhub_hb' .. i, function()
    if IsNuiFocused() then return end
    TriggerServerEvent(E.USE_HOTBAR, { slot = i })
  end, false)
  RegisterKeyMapping('vhub_hb' .. i, 'Inventario: atalho ' .. i, 'keyboard',
    (Inventory.Hotbar.keys and Inventory.Hotbar.keys[i]) or tostring(i))
end


-- ============================================================
-- TECLA / CLEANUP
-- ============================================================

-- A tecla unificada 'I' vive em client/containers.lua: ela decide baú vs mochila e
-- dispara este evento quando o player NAO esta no range de nenhum baú.
AddEventHandler('vhub_inventory:open_backpack', function()
  if not IsNuiFocused() then openBackpack() end
end)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() and _open then SetNuiFocus(false, false) end
end)
