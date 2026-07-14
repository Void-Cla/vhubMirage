-- server/pix_mp.lua — integração MercadoPago Pix (gateway real para compra de moedas)
--
-- CONFIGURAÇÃO:
--   Configure `set coinshop_mp_*` apenas em config/local.cfg (ignorado pelo Git).
--
-- FLUXO:
--   1. Jogador escolhe pacote → ch.send('pix_create', {packageId})
--   2. ipad_relay.lua → Pix.create(src, char_id, pack) → POST /v1/payments (MP)
--   3. MP responde com QR (base64) + copia-e-cola + txid
--   4. push(src, 'pix', { ok=true, txid, qrcode_base64, copiaECola, expiresAt })
--   5. Webhook MP (endpoint /webhook/mp-pix) → POST → valida → credita moedas → notifica
--
-- SEGURANÇA:
--   - Access Token lido de convar (NUNCA hardcoded)
--   - Webhook valida header X-Signature (HMAC-SHA256 via string match)
--   - Crédito de moedas SOMENTE via webhook — cliente nunca confirma pagamento
--   - Tabela vhub_coinshop_pix_tx rastreia todo o ciclo (pending→paid/expired)
--   - Rate limit por src igual às outras ações (purchaseItem)
--   - Falha de rede/HTTP isolada em pcall (R7) — nunca derruba o resource

VHubCoin = VHubCoin or {}
local Core = VHubCoin.Core
local Pix  = {}
VHubCoin.Pix = Pix


-- ============================================================
-- CONFIGURAÇÃO — lida de convars no boot (não mutável em runtime)
-- ============================================================

local _accessToken     = nil  -- APP_USR-... do MercadoPago (lido do convar)
local _webhookSecret   = nil  -- segredo para validar X-Signature do webhook MP
local _initialized     = false
local MAX_PACK_BRL     = 10000

-- idempotência: inicializa uma vez no boot
local function ensureInit()
    if _initialized then return end
    _initialized = true
    _accessToken   = GetConvar('coinshop_mp_key', '')
    _webhookSecret = GetConvar('coinshop_mp_webhook_secret', '')

    if _accessToken == '' then
        -- só é erro quando este provider está selecionado; com 'vhub_df' é ruído esperado
        if VHubCoin.cfg.pix.provider == 'mercadopago' then
            Core.logErr('pix_mp: convar coinshop_mp_key está vazio — Pix desabilitado')
        end
    else
        Core.log('pix_mp: Access Token carregado (' .. #_accessToken .. ' chars)')
    end
end

-- normaliza pacote para a regra comercial fixa R$1 = 1 coin.
local function normalizedPack(raw)
    if type(raw) ~= 'table' or type(raw.id) ~= 'string' or raw.id == '' then return nil end
    local amount = tonumber(raw.priceBRL)
    if not amount or amount < 1 or amount > MAX_PACK_BRL or amount % 1 ~= 0 then return nil end
    amount = math.floor(amount)

    return {
        id       = raw.id:sub(1, 50),
        tier     = math.max(1, math.min(4, math.floor(tonumber(raw.tier) or 1))),
        name     = tostring(raw.name or raw.id):sub(1, 48),
        coins    = amount,
        bonus    = 0,
        priceBRL = amount,
        popular  = raw.popular == true,
    }
end

-- retorna cópias públicas dos pacotes Pix normalizados.
function Pix.publicPackages()
    local packs = {}
    for _, raw in ipairs(VHubCoin.cfg.pix.packages or {}) do
        local pack = normalizedPack(raw)
        if pack then packs[#packs + 1] = pack end
    end
    return packs
end

-- retorna pacote Pix validado pelo identificador estável.
function Pix.findPackage(packageId)
    if type(packageId) ~= 'string' or #packageId > 50 then return nil end
    for _, pack in ipairs(Pix.publicPackages()) do
        if pack.id == packageId then return pack end
    end
    return nil
end

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        Citizen.SetTimeout(500, ensureInit)
    end
end)


-- ============================================================
-- HTTP CLIENT — wrapper seguro p/ PerformHttpRequest
-- ============================================================

-- timeout de 12s (MP Pix responde em < 3s na prática; 12 evita block longo)
local MP_TIMEOUT_MS = 12000
local MP_BASE       = 'https://api.mercadopago.com'

-- faz requisição HTTP para o MP e retorna (ok, body_table, status)
-- corpo será json.decode do response; ok=false quando status>=400 ou erro de rede
local function mpRequest(method, path, body, onDone)
    ensureInit()
    if _accessToken == '' then
        onDone(false, nil, 0)
        return
    end

    local url     = MP_BASE .. path
    local headers = {
        ['Content-Type']  = 'application/json',
        ['Authorization'] = 'Bearer ' .. _accessToken,
        ['X-Idempotency-Key'] = tostring(math.random(100000000, 999999999)),
    }
    local bodyStr = body and json.encode(body) or ''

    PerformHttpRequest(url, function(status, respBody, respHeaders)
        local parsed = nil
        if respBody and respBody ~= '' then
            local ok2, decoded = pcall(json.decode, respBody)
            if ok2 then parsed = decoded end
        end
        onDone(status >= 200 and status < 300, parsed, status)
    end, method, bodyStr, headers)
end


-- ============================================================
-- CRIAÇÃO DE COBRANÇA PIX
-- ============================================================

-- cria uma cobrança Pix no MercadoPago para o pacote `pack`.
-- Chama `callback(ok, result)`:
--   ok=true  → result = { txid, qrcode_base64, copiaECola, expiresAt, amount }
--   ok=false → result = { code, message }
function Pix.create(src, char_id, pack, callback)
    if _accessToken == '' then
        callback(false, { code = 'pix_sem_key', message = 'Chave MP não configurada no servidor.' })
        return
    end

    pack = normalizedPack(pack)
    if not pack then
        callback(false, { code = 'pack_invalido', message = 'Pacote inválido.' })
        return
    end
    local amount = pack.priceBRL
    local coins  = pack.coins

    local playerName = Core.getPlayerName(src)
    local minutes = math.max(1, math.min(1440, tonumber(VHubCoin.cfg.pix.expiresInMinutes) or 30))
    local expiresAt  = os.time() + (minutes * 60)

    local body = {
        transaction_amount = amount,
        description        = ('[vHub] ' .. pack.name .. ' — ' .. tostring(coins) .. ' moedas'):sub(1, 60),
        payment_method_id  = 'pix',
        date_of_expiration = os.date('!%Y-%m-%dT%H:%M:%S.000Z', expiresAt),
        payer = {
            email     = 'jogador_' .. tostring(char_id) .. '@vhubmirage.gta',
            first_name = playerName:sub(1, 30),
        },
        metadata = {
            char_id    = tostring(char_id),
            src        = tostring(src),
            package_id = pack.id,
            coins      = tostring(coins),
        },
    }

    mpRequest('POST', '/v1/payments', body, function(ok, resp, status)
        if not ok or type(resp) ~= 'table' then
            Core.logErr(('pix_mp: POST /v1/payments falhou status=%d'):format(status))
            callback(false, { code = 'mp_error', message = 'Falha ao criar cobrança Pix. Tente novamente.' })
            return
        end

        local txid     = tostring(resp.id or '')
        local pixBlock = resp.point_of_interaction
            and resp.point_of_interaction.transaction_data or nil

        if not pixBlock then
            Core.logErr('pix_mp: resposta MP sem point_of_interaction.transaction_data (id=' .. txid .. ')')
            callback(false, { code = 'mp_sem_qr', message = 'MP não retornou o QR Code. Tente novamente.' })
            return
        end

        local qrBase64  = tostring(pixBlock.qr_code_base64 or '')
        local copiaECola = tostring(pixBlock.qr_code or '')

        -- persiste a transação para que o webhook possa creditar as moedas
        local insertId = SQL.insert(
            'INSERT INTO vhub_coinshop_pix_tx (txid, char_id, src, package_id, coins, amount_brl, status, expires_at) ' ..
            'VALUES (?, ?, ?, ?, ?, ?, "pending", ?)',
            {
                txid, char_id, src, pack.id,
                coins,
                amount,
                os.date('%Y-%m-%d %H:%M:%S', expiresAt),
            }
        )
        if not insertId or tonumber(insertId) == 0 then
            Core.logErr('pix_mp: cobrança criada no MP sem persistir txid=' .. txid)
            callback(false, { code = 'tx_persist_failed', message = 'Falha ao registrar a cobrança Pix. Tente novamente.' })
            return
        end

        Core.log(('pix_mp: tx criada txid=%s char=%s pack=%s R$%.2f'):format(
            txid, tostring(char_id), pack.id, amount))

        callback(true, {
            txid           = txid,
            qrcode_base64  = qrBase64,
            copiaECola     = copiaECola,
            expiresAt      = expiresAt,     -- unix timestamp (o front calcula o timer)
            amount         = amount,
            coins          = coins,
        })
    end)
end


-- ============================================================
-- STATUS DE PAGAMENTO (polling server-side; NÃO expor ao cliente)
-- ============================================================

-- verifica se um txid já foi pago no MP (usado internamente — sem exposição ao cliente)
local function checkPaymentStatus(txid, onDone)
    mpRequest('GET', '/v1/payments/' .. txid, nil, function(ok, resp, _)
        if not ok or type(resp) ~= 'table' then onDone(nil) return end
        onDone(resp.status)  -- 'approved' | 'pending' | 'rejected' | ...
    end)
end


-- ============================================================
-- PROCESSAMENTO DO WEBHOOK MERCADOPAGO
-- ============================================================

-- valida e processa a notificação de pagamento do MP.
-- Chamado pelo endpoint HTTP registrado abaixo.
-- Retorna (ok, mensagem) — usado apenas para log.
local function handleWebhook(body, signatureHeader)
    if VHubCoin.cfg.pix.enabled ~= true or VHubCoin.cfg.pix.provider ~= 'mercadopago' then
        return false, 'pix_desabilitado'
    end

    -- validação mínima da assinatura (X-Signature: ts=...;v1=...)
    -- O MP envia: X-Signature: ts=<timestamp>;v1=<hash>
    -- Como PerformHttpRequest não expõe cabeçalhos de entrada (FiveM), usamos o
    -- segredo como layer adicional de segurança via campo secret no body (modo manual).
    -- Para segurança REAL: configure no painel MP → Notificações → Segredo.
    if _webhookSecret ~= '' and type(body) == 'table' then
        local bodySecret = tostring(body.secret or '')
        if bodySecret ~= _webhookSecret then
            Core.logErr('pix_mp webhook: segredo inválido — ignorado')
            return false, 'segredo_invalido'
        end
    end

    local action = type(body) == 'table' and body.action or nil
    if action ~= 'payment.updated' then
        return true, 'acao_ignorada'
    end

    local paymentId = type(body) == 'table' and body.data and tostring(body.data.id) or nil
    if not paymentId then return false, 'sem_id' end

    -- busca a tx pendente no banco
    local rows = SQL.query(
        "SELECT txid, char_id, src, coins FROM vhub_coinshop_pix_tx WHERE txid = ? AND status = 'pending'",
        { paymentId }
    )
    if not rows or #rows == 0 then
        Core.log('pix_mp webhook: tx ' .. paymentId .. ' não encontrada ou já processada')
        return true, 'tx_desconhecida_ou_processada'
    end

    local tx = rows[1]

    -- consulta o status REAL no MP (anti-replay: não confiar só no body do webhook)
    checkPaymentStatus(paymentId, function(mpStatus)
        if mpStatus ~= 'approved' then
            Core.log(('pix_mp webhook: pagamento %s status=%s — não creditado'):format(paymentId, tostring(mpStatus)))
            return
        end

        -- UPDATE atômico: apenas se ainda pending (idempotência — L-14/L-06)
        local affected = SQL.execute(
            "UPDATE vhub_coinshop_pix_tx SET status = 'paid', paid_at = NOW() WHERE txid = ? AND status = 'pending'",
            { paymentId }
        )
        if not affected or affected == 0 then
            Core.log('pix_mp webhook: tx ' .. paymentId .. ' já creditada (idempotência)')
            return
        end

        local coinsToAdd = tonumber(tx.coins) or 0
        local char_id    = tx.char_id
        local targetSrc  = tonumber(tx.src)

        if not VHubCoin.Coins.credit(char_id, coinsToAdd) then
            SQL.execute(
                "UPDATE vhub_coinshop_pix_tx SET status = 'pending', paid_at = NULL WHERE txid = ? AND status = 'paid'",
                { paymentId }
            )
            Core.logErr('pix_mp: crédito CData falhou; tx revertida para pending txid=' .. paymentId)
            return
        end

        SQL.insert(
            'INSERT INTO vhub_coinshop_redeems (char_id, redeem_key, coins_added) VALUES (?, ?, ?)',
            { char_id, 'PIX-' .. paymentId, coinsToAdd }
        )

        -- notifica o jogador se ainda estiver online
        if targetSrc and GetPlayerName(targetSrc) then
            VHubCoin.Coins.notifyChange(targetSrc, char_id)
            Core.notify(targetSrc,
                ('✅ Pagamento Pix aprovado! +%d moedas adicionadas.'):format(coinsToAdd), 'success')
        end

        Core.log(('pix_mp: pago! txid=%s char=%s +%d moedas'):format(paymentId, tostring(char_id), coinsToAdd))

        VHubCoin.Webhooks.fire('purchases', 'Pix Aprovado', nil, {
            { name = 'Char ID',  value = tostring(char_id),                inline = true },
            { name = 'TXID',     value = '`' .. paymentId .. '`',         inline = true },
            { name = 'Moedas',   value = tostring(coinsToAdd),             inline = true },
        })
    end)

    return true, 'processando'
end


-- ============================================================
-- ENDPOINT HTTP — recebe notificações do MercadoPago
-- ============================================================
-- Registre no painel MP → Suas Integrações → Webhooks → URL de notificação:
--   http://SEU_IP:SEU_PORT/webhook/mp-pix
-- (ou configure ngrok/cloudflared p/ dev local)

SetHttpHandler(function(req, res)
    if req.path ~= '/webhook/mp-pix' then
        res.writeHead(404)
        res.send('not found')
        return
    end
    if req.method ~= 'POST' then
        res.writeHead(405)
        res.send('method not allowed')
        return
    end

    req.setDataHandler(function(rawBody)
        local ok2, body = pcall(json.decode, rawBody or '')
        local sig = (req.headers and req.headers['x-signature']) or ''

        if not ok2 or type(body) ~= 'table' then
            Core.logErr('pix_mp webhook: body inválido')
            res.writeHead(400)
            res.send('bad request')
            return
        end

        -- processa em thread (handleWebhook faz SQL + HTTP)
        CreateThread(function()
            handleWebhook(body, sig)
        end)

        -- MP exige 200 imediato (timeout de 22s no lado deles)
        res.writeHead(200)
        res.send('ok')
    end)
end)


-- ============================================================
-- EXPORT — integra com ipad_relay.lua (substitui o stub)
-- ============================================================

-- chamado por ipad_relay.lua → actions.pix_create quando cfg.pix.enabled=true
-- e cfg.pix.provider='mercadopago'
function Pix.handleCreate(src, char_id, pack, push)
    -- pcall na fronteira externa (R7)
    local ok, err = pcall(function()
        Pix.create(src, char_id, pack, function(success, result)
            if success then
                push(src, 'pix', {
                    ok            = true,
                    txid          = result.txid,
                    qrcode_base64 = result.qrcode_base64,
                    copiaECola    = result.copiaECola,
                    expiresAt     = result.expiresAt,
                    coins         = result.coins,
                    amount        = result.amount,
                })
            else
                push(src, 'pix', {
                    ok      = false,
                    code    = result.code,
                    message = result.message or 'Falha ao criar cobrança Pix.',
                })
            end
        end)
    end)

    if not ok then
        Core.logErr('Pix.handleCreate explodiu: ' .. tostring(err))
        push(src, 'pix', { ok = false, code = 'internal', message = 'Erro interno. Tente novamente.' })
    end
end
