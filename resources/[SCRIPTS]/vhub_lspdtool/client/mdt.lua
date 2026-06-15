---@diagnostic disable: undefined-global, lowercase-global

-- mdt.lua — MDT / Central de Despacho no cliente (camada L2/HAL). NUI INTERATIVA (com foco).
-- Não decide verdade: PEDE dados ao servidor (que valida policial) e ENCAMINHA ações (criar/remover
-- BOLO) que o servidor revalida por permissão. Único overlay com NuiFocus (os demais são passivos).

local cfg = VHubLspd.cfg
local E   = VHubLspd.E
local UI  = VHubLspd.UI

local open = false


-- fecha o MDT e devolve o foco ao jogo
local function closeMdt()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = UI.MDT_CLOSE })
end


-- ============================================================
-- DADOS DO SERVIDOR (abre / refresca)
-- ============================================================

-- servidor autorizou (é policial) e enviou o snapshot → abre, ou refresca se já aberto
RegisterNetEvent(E.MDT_DATA, function(data)
    if type(data) ~= 'table' then return end
    if not open then
        open = true
        SetNuiFocus(true, true)
        SendNUIMessage({ type = UI.MDT_OPEN, data = data })
    else
        SendNUIMessage({ type = UI.MDT_DATA, data = data })
    end
end)


-- ============================================================
-- TECLA / COMANDO
-- ============================================================

-- abre (pede ao servidor; só policiais recebem resposta) ou fecha o MDT
RegisterCommand('vhub_lspd_mdt', function()
    if open then closeMdt() else TriggerServerEvent(E.REQ_MDT) end
end, false)
RegisterKeyMapping('vhub_lspd_mdt', 'LSPD: abrir MDT / Central de Despacho', 'keyboard', cfg.mdt.toggleKey or 'F7')


-- ============================================================
-- NUI CALLBACKS (ações do usuário → servidor revalida permissão)
-- ============================================================

RegisterNUICallback('mdtClose',   function(_, cb) closeMdt(); cb('ok') end)
RegisterNUICallback('mdtAddBolo', function(d, cb) TriggerServerEvent(E.MDT_ADD, d); cb('ok') end)
RegisterNUICallback('mdtDelBolo', function(d, cb) TriggerServerEvent(E.MDT_DEL, d); cb('ok') end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if open then SetNuiFocus(false, false) end
end)
