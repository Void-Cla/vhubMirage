-- server/webhook.lua — endpoint HTTP para notificações do MercadoPago
--
-- URL a registrar no painel MP → Suas Integrações → Webhooks:
--   http://SEU_IP:30120/vhub_df/df/webhook/pix?secret=SEU_SEGREDO
-- (o ?secret= deve bater com a convar df_mp_webhook_secret; sem convar = sem checagem)
--
-- SEGURANÇA:
--   • O corpo do webhook NUNCA é fonte de verdade — extraímos apenas o payment_id
--     e re-consultamos a API do MP via Payments.verifyAndSettle (valor conferido lá).
--   • Segredo na query string (default-deny quando configurado).
--   • Responde 200 imediato (MP tem timeout de 22s); processamento é assíncrono.
--   • Debounce por txid — o MP re-tenta em rajada; deliver já é idempotente,
--     o debounce só evita rajada de GETs desnecessários contra a API.

VHubDF = VHubDF or {}

local Core     = VHubDF.Core
local MP       = VHubDF.MP
local Payments = VHubDF.Payments


-- ============================================================
-- DEBOUNCE POR TXID (anti-rajada; O(1) por notificação)
-- ============================================================

local _recent      = {}   -- txid → GetGameTimer() da última verificação disparada
local _recentCount = 0

-- retorna true se este txid pode ser processado agora (e marca o instante)
local function debounce(txid)
    local now = GetGameTimer()
    if _recent[txid] and (now - _recent[txid]) < 2000 then return false end

    -- sweep preguiçoso: nunca deixa a tabela crescer sem limite
    if _recentCount > 256 then
        for k, t in pairs(_recent) do
            if (now - t) > 60000 then _recent[k] = nil; _recentCount = _recentCount - 1 end
        end
    end

    if not _recent[txid] then _recentCount = _recentCount + 1 end
    _recent[txid] = now
    return true
end


-- ============================================================
-- HANDLER HTTP
-- ============================================================

-- responde com status + JSON mínimo
local function respond(res, code, msg)
    res.writeHead(code, { ['Content-Type'] = 'application/json' })
    res.send(json.encode({ ok = code == 200, msg = msg }))
end

SetHttpHandler(function(req, res)
    -- pcall na fronteira externa (R7): request malformado não derruba o handler
    local ok, err = pcall(function()
        local path, query = req.path:match('^([^%?]*)%??(.*)$')

        if path ~= VHubDF.cfg.webhook.path then
            respond(res, 404, 'not_found')
            return
        end
        if req.method ~= 'POST' then
            respond(res, 405, 'method_not_allowed')
            return
        end

        -- segredo na URL (?secret=xxx) quando configurado — default-deny
        local secret = MP.webhookSecret()
        if secret ~= '' then
            local given = (query or ''):match('secret=([^&]*)') or ''
            if given ~= secret then
                Core.logErr('Webhook: segredo inválido — notificação descartada')
                respond(res, 403, 'forbidden')
                return
            end
        end

        req.setDataHandler(function(rawBody)
            -- MP exige 200 imediato; o processamento real é assíncrono
            respond(res, 200, 'ok')

            -- extrai o payment_id do corpo (só dígitos; nada mais é aproveitado)
            local txid = nil
            if rawBody and rawBody ~= '' then
                local jok, body = pcall(json.decode, rawBody)
                if jok and type(body) == 'table' then
                    local raw = (type(body.data) == 'table' and body.data.id) or body.id
                    txid = tostring(raw or ''):match('^(%d+)$')
                end
            end
            if not txid then return end          -- evento sem payment_id (ex: teste do painel)
            if not debounce(txid) then return end

            Citizen.CreateThread(function()
                Payments.verifyAndSettle(txid, 'webhook', function(outcome)
                    Core.log(('Webhook: txid=%s → %s'):format(txid, tostring(outcome)))
                    if outcome ~= 'pending' and outcome ~= 'error' and VHubDF.Queue then
                        VHubDF.Queue.untrack(txid)
                    end
                end)
            end)
        end)
    end)

    if not ok then
        Core.logErr('Webhook: handler explodiu — ' .. tostring(err))
        pcall(respond, res, 500, 'internal_error')
    end
end)
