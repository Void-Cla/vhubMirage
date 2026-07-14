-- server/mercadopago.lua — cliente HTTP MercadoPago (Pix) para o vhub_df
--
-- Responsabilidade: encapsula TODA comunicação com a API do MP.
-- Não conhece SQL, sessões nem lógica de negócio — só fala HTTP.
--
-- CREDENCIAIS (config/local.cfg — NUNCA versionar):
--   set df_mp_key            "APP_USR-xxxxxxxxxxxx"   ← Access Token da API
--   set df_mp_webhook_secret "xxxxxxxx"               ← assinatura secreta do webhook (recomendado)

VHubDF = VHubDF or {}
local MP = {}
VHubDF.MP = MP

local Core = VHubDF.Core


-- ============================================================
-- BOOTSTRAP — lê credenciais uma vez no boot (não mutável)
-- ============================================================

local _token  = nil   -- Access Token do MP
local _secret = nil   -- segredo do webhook MP (X-Signature)
local _ready  = false

local function ensureInit()
    if _ready then return end
    _ready  = true
    _token  = GetConvar('df_mp_key', '')
    _secret = GetConvar('df_mp_webhook_secret', '')

    if _token == '' then
        Core.logErr('MP: convar df_mp_key vazio — Pix DESABILITADO')
    else
        Core.log(('MP: token carregado (%d chars)'):format(#_token))
    end
end

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        Citizen.SetTimeout(400, ensureInit)
    end
end)

-- retorna true se o token está configurado
function MP.isReady()
    ensureInit()
    return _token ~= ''
end

-- retorna o segredo do webhook (usado pelo webhook.lua para validar assinatura)
function MP.webhookSecret()
    ensureInit()
    return _secret
end


-- ============================================================
-- HTTP — wrapper interno (callback-based, não-blocking)
-- ============================================================

-- faz requisição para a API do MP.
-- onDone(ok, body_table, httpStatus)
--   ok=true  → body_table é a resposta decodificada
--   ok=false → body_table pode ser nil ou ter {error, message}
local function mpHttp(method, path, body, onDone)
    ensureInit()
    if _token == '' then
        onDone(false, { error = 'no_token', message = 'Access Token não configurado.' }, 0)
        return
    end

    local cfg     = VHubDF.cfg.mp
    local url     = cfg.baseUrl .. path
    local headers = {
        ['Content-Type']      = 'application/json',
        ['Authorization']     = 'Bearer ' .. _token,
        -- idempotency key aleatório por chamada — MP usa p/ deduplicar POSTs
        ['X-Idempotency-Key'] = ('%d_%d'):format(os.time(), math.random(100000, 999999)),
    }
    local bodyStr = body and json.encode(body) or ''

    -- pcall na fronteira externa HTTP (R7 — falha isolada)
    local callOk, callErr = pcall(function()
        PerformHttpRequest(url, function(status, respBody, _respHeaders)
            local parsed = nil
            if respBody and respBody ~= '' then
                local jok, jval = pcall(json.decode, respBody)
                if jok then parsed = jval end
            end
            local httpOk = status >= 200 and status < 300
            if not httpOk then
                -- corpo da resposta é essencial p/ diagnóstico (ex: chave Pix inativa)
                local reason = ''
                if type(parsed) == 'table' then
                    reason = tostring(parsed.message or '')
                    if type(parsed.cause) == 'table' and parsed.cause[1] then
                        reason = reason .. ' | cause: ' .. tostring(parsed.cause[1].description
                            or parsed.cause[1].code or '')
                    end
                elseif respBody then
                    reason = tostring(respBody):sub(1, 300)
                end
                Core.logErr(('MP HTTP %s %s → %d — %s'):format(method, path, status, reason))
            end
            onDone(httpOk, parsed, status)
        end, method, bodyStr, headers)
    end)

    if not callOk then
        Core.logErr('MP PerformHttpRequest explodiu: ' .. tostring(callErr))
        onDone(false, { error = 'http_exception', message = tostring(callErr) }, 0)
    end
end


-- ============================================================
-- CRIAR COBRANÇA PIX
-- ============================================================

-- cria uma cobrança Pix no MercadoPago.
-- params = { amountBRL, description, payerLabel, externalRef, expiresInMinutes }
-- onDone(ok, result)
--   ok=true  → result = { txid, qrBase64, copiaECola, expiresAt }
--   ok=false → result = { code, message }
function MP.createPix(params, onDone)
    if not MP.isReady() then
        onDone(false, { code = 'no_token', message = 'Gateway Pix não configurado no servidor.' })
        return
    end

    local cfg       = VHubDF.cfg.mp
    local minutes   = VHubDF.U.clamp(
        tonumber(params.expiresInMinutes) or cfg.expiresInMinutes, 1, 1440)
    local expiresAt = os.time() + minutes * 60
    -- MP exige offset explícito (±HH:MM) — o sufixo 'Z' retorna 400 em contas novas
    local expiresISO = os.date('!%Y-%m-%dT%H:%M:%S.000+00:00', expiresAt)

    -- e-mail fictício obrigatório pelo MP; NUNCA usar dado real do jogador
    local payerEmail = ('payer_%s@%s'):format(
        tostring(params.payerLabel or 'anon'):gsub('[^%w]', '_'):sub(1, 24),
        cfg.payerEmailDomain)

    local body = {
        transaction_amount = params.amountBRL,
        description        = tostring(params.description or 'Pagamento vHub'):sub(1, 60),
        payment_method_id  = 'pix',
        date_of_expiration = expiresISO,
        payer = {
            email      = payerEmail,
            first_name = tostring(params.payerLabel or 'Jogador'):sub(1, 30),
        },
        -- external_reference permite rastrear no painel do MP
        external_reference = tostring(params.externalRef or ''):sub(1, 64),
    }

    mpHttp('POST', '/v1/payments', body, function(ok, resp, status)
        if not ok or type(resp) ~= 'table' then
            onDone(false, {
                code    = 'mp_error',
                message = ('Falha ao criar cobrança Pix (HTTP %d).'):format(status),
            })
            return
        end

        local txid     = tostring(resp.id or '')
        local pixBlock = resp.point_of_interaction
            and resp.point_of_interaction.transaction_data

        if txid == '' or not pixBlock then
            Core.logErr('MP createPix: resposta sem id ou transaction_data (status=' .. tostring(resp.status) .. ')')
            onDone(false, {
                code    = 'mp_sem_qr',
                message = 'MercadoPago não retornou o QR Code. Tente novamente.',
            })
            return
        end

        onDone(true, {
            txid       = txid,
            qrBase64   = tostring(pixBlock.qr_code_base64 or ''),
            copiaECola = tostring(pixBlock.qr_code or ''),
            expiresAt  = expiresAt,
            amountBRL  = params.amountBRL,
        })
    end)
end


-- ============================================================
-- CONSULTAR STATUS (polling — nunca exposto ao cliente)
-- ============================================================

-- consulta o status real de um pagamento no MP.
-- onDone(info | nil) — info = { status, amount }
--   status: 'pending'|'in_process'|'approved'|'rejected'|'cancelled'|'refunded'|'charged_back'
--   amount: transaction_amount aprovado (para conferência pedido × pagamento)
function MP.getStatus(txid, onDone)
    if not MP.isReady() then onDone(nil) return end
    mpHttp('GET', '/v1/payments/' .. tostring(txid), nil, function(ok, resp, _)
        if not ok or type(resp) ~= 'table' then onDone(nil) return end
        onDone({
            status = tostring(resp.status or ''),
            amount = tonumber(resp.transaction_amount),
        })
    end)
end


-- ============================================================
-- CANCELAR COBRANÇA (marca como cancelled no MP)
-- ============================================================

-- tenta cancelar uma cobrança pendente no MP (best-effort; não falha se já expirada)
-- onDone(ok)
function MP.cancel(txid, onDone)
    if not MP.isReady() then onDone(false) return end
    mpHttp('PUT', '/v1/payments/' .. tostring(txid), { status = 'cancelled' }, function(ok, _, _)
        onDone(ok)
    end)
end
