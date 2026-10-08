-- server/init.lua — bootstrap do vhub_df: schema, recuperação pós-restart, net events
--
-- ORDEM (fxmanifest): sql → core → mercadopago → payments → queue → webhook → exports → init

local Core     = VHubDF.Core
local Payments = VHubDF.Payments
local Queue    = VHubDF.Queue


-- ============================================================
-- BOOT — schema idempotente + recuperação da fila (L-17)
-- ============================================================

local _booted = false

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() or _booted then return end
    _booted = true

    Citizen.CreateThread(function()
        Citizen.Wait(1500)   -- oxmysql pronto

        -- aplica schema idempotente em instruções isoladas (ADR #98).
        local raw = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
        if raw then
            local ok, err = VHubSQLScript.aplicar(raw, function(statement)
                MySQL.query.await(statement, {})
            end)
            if not ok then
                Core.logErr('init: falha ao aplicar schema: ' .. tostring(err))
            end
        else
            Core.logErr('init: sql/schema.sql ausente (declarado no files{} do fxmanifest?)')
        end

        -- retoma o polling de tudo que ficou pendente antes do restart
        Queue.recover()

        Core.log(('init: vhub_df pronto (enabled=%s, mp_token=%s, fila=%d)'):format(
            tostring(VHubDF.cfg.enabled), tostring(VHubDF.MP.isReady()), Queue.size()))
    end)

    -- FIN-001/ADR #94: reentrega de orders approved-sem-crédito (gap de crash).
    -- Roda em thread separada com atraso: os handlers dos consumidores (ex.: coinshop
    -- pix_df) registram com retry a cada 2s no próprio boot; esperamos ~8s para dar
    -- tempo do handler existir antes da 1ª passada, senão reentrega volta 'sem_handler'.
    Citizen.CreateThread(function()
        Citizen.Wait(8000)
        pcall(Queue.recoverStuck)
    end)
end)


-- ============================================================
-- NET EVENTS — cliente NUNCA cria cobrança nem escolhe valor;
-- só consulta/cancela a PRÓPRIA cobrança (rate-gated, L-01)
-- ============================================================

-- NUI pergunta o status LOCAL de uma cobrança do próprio jogador (não bate no MP)
RegisterNetEvent(VHubDF.E.CHECK_STATUS, function(txid)
    local src = source
    if type(txid) ~= 'string' or #txid == 0 or #txid > 64 then return end
    if not Core.rate(src, 'check', VHubDF.cfg.rates.checkStatus) then return end

    Citizen.CreateThread(function()
        local charId = Core.getCharId(src)
        if not charId then return end

        local rows = SQL.query(
            'SELECT status FROM vhub_df_orders WHERE txid = ? AND char_id = ? LIMIT 1',
            { txid, charId })
        local status = rows and rows[1] and rows[1].status or 'unknown'
        TriggerClientEvent(VHubDF.E.NUI_UPDATE, src, { txid = txid, status = status })
    end)
end)

-- jogador cancela a própria cobrança pendente
RegisterNetEvent(VHubDF.E.CANCEL_PAYMENT, function(txid)
    local src = source
    if type(txid) ~= 'string' or #txid == 0 or #txid > 64 then return end
    if not Core.rate(src, 'cancel', VHubDF.cfg.rates.cancelPayment) then return end

    Citizen.CreateThread(function()
        Payments.cancel(src, txid, function(ok, msg)
            Core.notify(src, msg, ok and 'success' or 'error')
            if ok then TriggerClientEvent(VHubDF.E.NUI_CLOSE, src) end
        end)
    end)
end)

-- limpa rate-limits do jogador que saiu (sem leak de memória)
AddEventHandler('playerDropped', function()
    Core.clearRates(source)
end)


-- ============================================================
-- COMANDO ADMIN — teste ponta a ponta (/df_test <valor>)
-- ============================================================

-- cria uma cobrança de teste para o próprio admin (perm vhub.df.admin; sem handler
-- registrado a entrega marca 'aprovado_sem_handler' — suficiente p/ validar o fluxo)
RegisterCommand('df_test', function(src, args)
    if src == 0 then return end   -- precisa de NUI → só in-game
    if not Core.hasPerm(src, 'df.admin') then
        Core.notify(src, 'Sem permissão.', 'error')
        return
    end

    local amount = tonumber(args[1]) or 1.00
    Citizen.CreateThread(function()
        Payments.createOrder(src, {
            amountBRL   = amount,
            productKey  = 'test:manual',
            productDesc = 'Cobrança de teste vhub_df',
        }, function(ok, result)
            if not ok then
                Core.notify(src, result.message or 'Falha ao criar cobrança.', 'error')
                return
            end
            Payments.pushNui(src, result)
        end)
    end)
end, false)
