-- client/init.lua — ponte NUI do vhub_df (L2: só UI; zero decisão de verdade crítica)
--
-- O cliente apenas: abre/fecha a NUI, repassa updates do servidor para a página
-- e encaminha ações da NUI como eventos rate-gated. Nenhum valor/produto nasce aqui.

local _open = false


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- fecha a NUI e devolve o foco ao jogo (idempotente)
local function closeNui()
    if not _open then return end
    _open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- servidor manda abrir com os dados da cobrança (QR base64 + copia-e-cola)
RegisterNetEvent(VHubDF.E.NUI_OPEN, function(data)
    if type(data) ~= 'table' then return end
    _open = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action  = 'open',
        payload = {
            txid       = tostring(data.txid or ''),
            qrBase64   = tostring(data.qrBase64 or ''),
            copiaECola = tostring(data.copiaECola or ''),
            expiresAt  = tonumber(data.expiresAt) or 0,
            amountBRL  = tonumber(data.amountBRL) or 0,
        },
    })
end)

RegisterNetEvent(VHubDF.E.NUI_CLOSE, function()
    closeNui()
end)


-- ============================================================
-- UPDATES DO SERVIDOR → NUI
-- ============================================================

-- status local re-consultado pelo servidor (resposta do CHECK_STATUS)
RegisterNetEvent(VHubDF.E.NUI_UPDATE, function(data)
    if type(data) ~= 'table' then return end
    SendNUIMessage({ action = 'update', payload = data })
end)

-- desfecho final (entrega confirmada) — empurrado pelo servidor
RegisterNetEvent(VHubDF.E.PAYMENT_RESULT, function(data)
    if type(data) ~= 'table' then return end
    SendNUIMessage({ action = 'result', payload = data })
end)


-- ============================================================
-- CALLBACKS DA NUI → SERVIDOR
-- ============================================================

RegisterNUICallback('close', function(_, cb)
    closeNui()
    cb({ ok = true })
end)

RegisterNUICallback('checkStatus', function(req, cb)
    TriggerServerEvent(VHubDF.E.CHECK_STATUS, tostring(req and req.txid or ''))
    cb({ ok = true })
end)

RegisterNUICallback('cancel', function(req, cb)
    TriggerServerEvent(VHubDF.E.CANCEL_PAYMENT, tostring(req and req.txid or ''))
    cb({ ok = true })
end)
