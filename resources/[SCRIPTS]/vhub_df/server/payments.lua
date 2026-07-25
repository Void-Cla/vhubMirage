-- server/payments.lua — fluxo principal de pagamento do vhub_df
--
-- Responsabilidade:
--   • createOrder(src, params, onDone) — valida, persiste, chama MP, retorna QR
--   • deliver(order, actor)            — ÚNICO caminho de entrega (webhook + polling)
--   • expire(txid, actor)              — marca expirado (idempotente)
--   • cancel(src, txid, onDone)        — cancela pedido do próprio jogador
--   • getPlayerPending(src)            — lista pedidos pendentes do jogador
--   • audit(order_id, txid, event, actor, detail) — append ao log de auditoria
--
-- SEGURANÇA:
--   • Entrega SOMENTE após consulta re-verificada na API do MP (nunca confia no cliente)
--   • UPDATE atômico pending→approved como idempotência (idempotência L-14/R14)
--   • Rollback de status se callback de entrega falhar
--   • Limite de cobranças pendentes por jogador (anti-spam)

VHubDF = VHubDF or {}
local Payments = {}
VHubDF.Payments = Payments

local Core = VHubDF.Core
local U    = VHubDF.U
local MP   = VHubDF.MP


-- ============================================================
-- AUDITORIA — append-only (nunca UPDATE nesta tabela)
-- ============================================================

-- registra evento no log imutável (fire-and-forget; falha não impede o fluxo)
function Payments.audit(orderId, txid, event, actor, detail)
    local detailStr = nil
    if detail then
        local ok, enc = pcall(json.encode, detail)
        if ok then detailStr = enc end
    end
    Citizen.CreateThread(function()
        SQL.execute(
            'INSERT INTO vhub_df_audit (order_id, txid, event, actor, detail) VALUES (?, ?, ?, ?, ?)',
            { orderId, txid, event, actor, detailStr }
        )
    end)
end


-- ============================================================
-- CRIAR PEDIDO
-- ============================================================

-- cria um pedido Pix e persiste no banco.
-- params = {
--   amountBRL    : number   — valor em BRL (validado aqui)
--   productKey   : string   — chave opaca do produto (ex: 'coins:100')
--   productDesc  : string   — descrição legível (ex: '100 Moedas vHub')
--   metadata     : table|nil— dados extras livres (serializado como JSON ≤ 512B)
-- }
-- onDone(ok, result)
--   ok=true  → result = { orderId, txid, qrBase64, copiaECola, expiresAt, amountBRL }
--   ok=false → result = { code, message }
function Payments.createOrder(src, params, onDone)

    if not VHubDF.cfg.enabled then
        onDone(false, { code = 'disabled', message = 'Gateway de pagamento desabilitado.' })
        return
    end

    -- 1. validar jogador
    local charId = Core.getCharId(src)
    if not charId then
        onDone(false, { code = 'no_user', message = 'Jogador não autenticado.' })
        return
    end

    -- 2. validar parâmetros
    local amount = U.parseBRL(params.amountBRL)
    if not amount then
        onDone(false, {
            code    = 'amount_invalid',
            message = ('Valor inválido. Mínimo R$ %.2f, máximo R$ %.2f.'):format(
                VHubDF.cfg.minAmountBRL, VHubDF.cfg.maxAmountBRL),
        })
        return
    end

    local productKey = U.sanitizeKey(params.productKey)
    if not productKey then
        onDone(false, { code = 'product_invalid', message = 'Chave de produto inválida.' })
        return
    end

    local productDesc = U.sanitizeDesc(params.productDesc or '')
    local metaStr     = U.sanitizeMetadata(params.metadata)

    -- 3. checar limite de pendentes por jogador (anti-spam)
    local pendingCount = SQL.scalar(
        "SELECT COUNT(*) FROM vhub_df_orders WHERE char_id = ? AND status = 'pending'",
        { charId }
    ) or 0
    if tonumber(pendingCount) >= VHubDF.cfg.maxPendingPerPlayer then
        onDone(false, {
            code    = 'too_many_pending',
            message = ('Você já tem %d cobranças Pix abertas. Cancele ou aguarde.'):format(
                VHubDF.cfg.maxPendingPerPlayer),
        })
        return
    end

    -- 4. criar cobrança no MP (assíncrono)
    local mpParams = {
        amountBRL        = amount,
        description      = productDesc ~= '' and productDesc or productKey,
        payerLabel       = tostring(charId),
        externalRef      = ('vhub_df:%s:%d'):format(tostring(charId), os.time()),
        expiresInMinutes = VHubDF.cfg.mp.expiresInMinutes,
    }

    -- MP.createPix é callback — saímos da thread aqui; promise garante o resume
    local p = promise.new()
    MP.createPix(mpParams, function(ok, result)
        p:resolve({ ok = ok, result = result })
    end)
    local res = Citizen.Await(p)

    if not res.ok then
        onDone(false, res.result)
        return
    end

    local mpResult  = res.result
    local expiresSQL = os.date('%Y-%m-%d %H:%M:%S', mpResult.expiresAt)

    -- 5. persistir (falha aqui = não houve cobrança confirmada; erro claro ao jogador)
    local orderId = SQL.insert(
        [[INSERT INTO vhub_df_orders
            (txid, char_id, src, product_key, product_desc, amount_brl, metadata,
             status, expires_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)]],
        {
            mpResult.txid, charId, src,
            productKey, productDesc,
            amount, metaStr,
            expiresSQL,
        }
    )

    if not orderId or tonumber(orderId) == 0 then
        Core.logErr(('Payments.createOrder: txid=%s criado no MP mas NÃO persistido'):format(mpResult.txid))
        onDone(false, {
            code    = 'persist_failed',
            message = 'Falha ao registrar cobrança. Tente novamente.',
        })
        return
    end

    Payments.audit(orderId, mpResult.txid, 'created', 'server', {
        char_id     = charId,
        amount_brl  = amount,
        product_key = productKey,
    })

    Core.log(('Payments: pedido #%d txid=%s char=%s R$%.2f'):format(
        orderId, mpResult.txid, tostring(charId), amount))

    -- entra na fila de polling (queue.lua carrega depois — referência tardia)
    if VHubDF.Queue then VHubDF.Queue.track(mpResult.txid, orderId) end

    onDone(true, {
        orderId    = orderId,
        txid       = mpResult.txid,
        qrBase64   = mpResult.qrBase64,
        copiaECola = mpResult.copiaECola,
        expiresAt  = mpResult.expiresAt,
        amountBRL  = amount,
    })
end


-- ============================================================
-- ENTREGA — único caminho (chamado por webhook E polling)
-- ============================================================

-- notifica o jogador se ainda estiver online (fire-and-forget)
local function _notifyPlayerIfOnline(order, success)
    local targetSrc = tonumber(order.src)
    if not targetSrc or not GetPlayerName(targetSrc) then return end
    if success then
        Core.notify(targetSrc,
            ('✅ Pix aprovado! Produto "%s" entregue.'):format(order.product_key or ''),
            'success')
        TriggerClientEvent(VHubDF.E.PAYMENT_RESULT, targetSrc, {
            ok      = true,
            txid    = order.txid,
            orderId = order.id,
        })
    else
        Core.notify(targetSrc,
            '❌ Falha na entrega do produto. Contate um administrador.', 'error')
    end
end

-- tabela local de callbacks de entrega registrados por consumidores
-- key = product_key_prefix (ex: 'coins'), value = function(charId, orderId, meta, onDone)
local _handlers = {}

-- prefixos já avisados como "sem handler" (evita spam de log a cada retry da fila)
local _noHandlerWarned = {}

-- registra um callback de entrega para uma família de product_key
-- prefix pode ser 'coins', 'boost', etc. — product_key deve começar com prefix..':'
function Payments.registerHandler(prefix, fn)
    assert(type(prefix) == 'string' and prefix ~= '', 'prefix inválido')
    -- funcref de outro resource é table com __call — tão válido quanto function
    assert(type(fn) == 'function' or type(fn) == 'table', 'handler deve ser chamável')
    _handlers[prefix] = fn
    _noHandlerWarned[prefix] = nil
    print(('[vhub_df] handler de entrega registrado: prefix=%s (por %s)'):format(
        prefix, tostring(GetInvokingResource() or 'local')))
end

-- remove um handler registrado (chamado quando o resource dono para)
function Payments.unregisterHandler(prefix)
    if _handlers[prefix] then
        _handlers[prefix] = nil
        Core.log('Payments: handler removido para prefix=' .. prefix)
    end
end

-- tenta entregar uma order aprovada (idempotente — UPDATE pending→approved como lock)
-- actor = 'webhook' | 'polling' | 'admin'
-- onDone(ok, message) — opcional
function Payments.deliver(order, actor, onDone)
    onDone = onDone or function() end

    -- lock atômico: só processa se ainda pending no banco
    local affected = SQL.execute(
        "UPDATE vhub_df_orders SET status = 'approved', paid_at = NOW() WHERE txid = ? AND status = 'pending'",
        { order.txid }
    )
    if not affected or tonumber(affected) == 0 then
        Core.log('Payments.deliver: ' .. order.txid .. ' já processado (idempotência)')
        onDone(true, 'já_processado')
        return
    end

    -- decodifica metadata para o handler
    local meta = nil
    if order.metadata and order.metadata ~= '' then
        local ok2, dec = pcall(json.decode, order.metadata)
        if ok2 then meta = dec end
    end

    -- descobre o handler pelo prefixo da product_key
    local prefix = (order.product_key or ''):match('^([^:]+)')
    local handler = prefix and _handlers[prefix]

    if not handler then
        -- SEM handler: NÃO consome o pedido pago. Volta a pending e a fila re-tenta
        -- a cada ciclo — quando o consumidor registrar o handler, entrega sozinho.
        -- (antes marcava 'aprovado_sem_handler' e a compra paga se perdia — bug 2026-07-13)
        SQL.execute(
            "UPDATE vhub_df_orders SET status = 'pending', paid_at = NULL WHERE txid = ? AND status = 'approved'",
            { order.txid }
        )
        if not _noHandlerWarned[prefix or '?'] then
            _noHandlerWarned[prefix or '?'] = true
            Payments.audit(order.id, order.txid, 'error', actor, { reason = 'sem_handler', prefix = prefix })
            Core.logErr(('Payments.deliver: SEM handler para prefix=%s (txid=%s) — pedido segue na fila; ' ..
                'o consumidor precisa chamar exports.vhub_df:registerHandler'):format(
                tostring(prefix), order.txid))
        end
        onDone(false, 'sem_handler')
        return
    end

    -- chama o handler (deve ser idempotente — pode receber a mesma order 2x)
    local ok3, err3 = pcall(function()
        handler(order.char_id, order.id, meta, function(delivOk, delivMsg)
            if delivOk then
                SQL.execute(
                    "UPDATE vhub_df_orders SET credited_at = NOW() WHERE txid = ?",
                    { order.txid }
                )
                Payments.audit(order.id, order.txid, 'delivered', actor, { msg = delivMsg })
                Core.log(('Payments: entregue txid=%s char=%s via %s'):format(
                    order.txid, tostring(order.char_id), actor))

                -- notificação Discord de venda confirmada (convar df_discord_webhook)
                local playerName = Core.getPlayerName(tonumber(order.src) or 0)
                Core.discordAudit(
                    '✅ Pix Recebido e Entregue',
                    ('Produto **%s** entregue ao jogador **%s** (char `%s`).'):format(
                        order.product_desc or order.product_key or '?',
                        playerName,
                        tostring(order.char_id)),
                    VHubDF.cfg.discord.colorOk,
                    {
                        { name = 'Produto',  value = '`' .. (order.product_key or '?') .. '`', inline = true },
                        { name = 'Valor',    value = ('R$ %.2f'):format(tonumber(order.amount_brl) or 0), inline = true },
                        { name = 'TXID',     value = '`' .. order.txid .. '`', inline = false },
                        { name = 'Via',      value = actor,                     inline = true },
                    }
                )

                _notifyPlayerIfOnline(order, true)
                onDone(true, delivMsg)
            else
                -- rollback: se o handler falhou, volta para pending para nova tentativa
                SQL.execute(
                    "UPDATE vhub_df_orders SET status = 'pending', paid_at = NULL WHERE txid = ? AND status = 'approved'",
                    { order.txid }
                )
                Payments.audit(order.id, order.txid, 'error', actor, { msg = delivMsg })
                Core.logErr(('Payments.deliver handler falhou txid=%s: %s'):format(
                    order.txid, tostring(delivMsg)))
                onDone(false, delivMsg)
            end
        end)
    end)

    if not ok3 then
        -- rollback em caso de exceção no handler
        SQL.execute(
            "UPDATE vhub_df_orders SET status = 'pending', paid_at = NULL WHERE txid = ? AND status = 'approved'",
            { order.txid }
        )
        Payments.audit(order.id, order.txid, 'error', actor, { exception = tostring(err3) })
        Core.logErr('Payments.deliver: handler explodiu — ' .. tostring(err3))
        onDone(false, 'exception')
    end
end


-- ============================================================
-- VERIFICAÇÃO — re-consulta o MP e liquida (caminho único de verdade)
-- ============================================================

-- re-verifica um txid direto na API do MP e aplica o desfecho no banco.
-- NUNCA usa status vindo de cliente/NUI/corpo de webhook como verdade (L-01).
-- actor = 'polling' | 'webhook' | 'boot' | 'admin'
-- onDone(outcome): 'delivered'|'pending'|'expired'|'rejected'|'cancelled'
--                  |'amount_mismatch'|'unknown'|'error'|<status já liquidado>
function Payments.verifyAndSettle(txid, actor, onDone)
    onDone = onDone or function() end

    -- 1. estado local fresco (a fila em memória pode estar defasada)
    local rows = SQL.query(
        [[SELECT id, txid, char_id, src, product_key, product_desc, amount_brl, metadata,
                 UNIX_TIMESTAMP(expires_at) AS expires_at, status
          FROM vhub_df_orders WHERE txid = ? LIMIT 1]],
        { txid }
    )
    if not rows or #rows == 0 then onDone('unknown') return end

    local order = rows[1]
    if order.status ~= 'pending' then onDone(order.status) return end

    -- 2. a verdade vem da API do MP — re-verificação obrigatória
    local p = promise.new()
    MP.getStatus(txid, function(info) p:resolve(info) end)
    local info = Citizen.Await(p)
    if not info or not U.isStr(info.status) then onDone('error') return end

    -- 3. aprovado: valor pago TEM que bater com o pedido antes de entregar
    if info.status == 'approved' then
        local expected = tonumber(order.amount_brl) or -1
        local paid     = tonumber(info.amount) or -2

        if math.abs(expected - paid) > 0.009 then
            SQL.execute(
                "UPDATE vhub_df_orders SET status = 'rejected' WHERE txid = ? AND status = 'pending'",
                { txid })
            Payments.audit(order.id, txid, 'error', actor,
                { reason = 'amount_mismatch', expected = expected, paid = paid })
            Core.logErr(('Payments: VALOR DIVERGENTE txid=%s pedido=R$%.2f pago=R$%.2f — entrega bloqueada'):format(
                txid, expected, paid))
            Core.discordAudit('⚠️ Pix aprovado com valor divergente',
                ('txid `%s`: pedido R$ %.2f ≠ pago R$ %.2f. Entrega BLOQUEADA — revisar no painel do MP.'):format(
                    txid, expected, paid),
                VHubDF.cfg.discord.colorFail)
            onDone('amount_mismatch')
            return
        end

        Payments.deliver(order, actor, function(ok, _)
            onDone(ok and 'delivered' or 'error')
        end)
        return
    end

    -- 4. desfechos terminais do MP → espelha no banco (idempotente)
    if info.status == 'rejected' or info.status == 'cancelled'
        or info.status == 'refunded' or info.status == 'charged_back' then
        local localStatus = (info.status == 'rejected') and 'rejected' or 'cancelled'
        SQL.execute(
            "UPDATE vhub_df_orders SET status = ? WHERE txid = ? AND status = 'pending'",
            { localStatus, txid })
        Payments.audit(order.id, txid, localStatus, actor, { mp_status = info.status })
        onDone(localStatus)
        return
    end

    -- 5. ainda pendente no MP: expira localmente se passou do prazo (folga de 2 min)
    if os.time() > (tonumber(order.expires_at) or 0) + 120 then
        Payments.expire(txid, order.id, actor)
        onDone('expired')
        return
    end

    onDone('pending')
end


-- ============================================================
-- NUI — envia o QR para o jogador (payload primitivo, L-19)
-- ============================================================

-- abre a NUI do jogador com QR base64 + copia-e-cola (chamado por export e /df_test)
function Payments.pushNui(src, result)
    TriggerClientEvent(VHubDF.E.NUI_OPEN, src, {
        txid       = result.txid,
        orderId    = result.orderId,
        qrBase64   = result.qrBase64,
        copiaECola = result.copiaECola,
        expiresAt  = result.expiresAt,
        amountBRL  = result.amountBRL,
    })
end


-- ============================================================
-- EXPIRAR PEDIDO
-- ============================================================

-- marca um pedido como expirado (idempotente; usado pelo queue e pelo webhook)
-- actor = 'queue' | 'webhook'
function Payments.expire(txid, orderId, actor)
    local affected = SQL.execute(
        "UPDATE vhub_df_orders SET status = 'expired' WHERE txid = ? AND status = 'pending'",
        { txid }
    )
    if affected and tonumber(affected) > 0 then
        Payments.audit(orderId, txid, 'expired', actor, nil)
        Core.log('Payments: expirado txid=' .. txid)
    end
end


-- ============================================================
-- CANCELAR (a pedido do jogador)
-- ============================================================

-- cancela uma cobrança pending do próprio jogador (rate-gated; best-effort no MP)
-- onDone(ok, message)
function Payments.cancel(src, txid, onDone)

    if not U.isStr(txid) or #txid > 64 then
        onDone(false, 'TXID inválido.')
        return
    end

    local charId = Core.getCharId(src)
    if not charId then onDone(false, 'Não autenticado.') return end

    local rows = SQL.query(
        "SELECT id, char_id, status FROM vhub_df_orders WHERE txid = ? LIMIT 1",
        { txid }
    )
    if not rows or #rows == 0 then
        onDone(false, 'Cobrança não encontrada.')
        return
    end

    local order = rows[1]
    if tostring(order.char_id) ~= tostring(charId) then
        Core.logErr(('Payments.cancel: src=%d tentou cancelar order de char=%s'):format(
            src, tostring(order.char_id)))
        onDone(false, 'Sem permissão.')
        return
    end

    if order.status ~= 'pending' then
        onDone(false, ('Cobrança não pode ser cancelada (status: %s).'):format(order.status))
        return
    end

    -- marca cancelled no banco ANTES de chamar o MP (idempotência)
    local affected = SQL.execute(
        "UPDATE vhub_df_orders SET status = 'cancelled' WHERE txid = ? AND status = 'pending'",
        { txid }
    )
    if not affected or tonumber(affected) == 0 then
        onDone(false, 'Cobrança já encerrada.')
        return
    end

    Payments.audit(order.id, txid, 'cancelled', 'player_' .. tostring(src), nil)

    -- sai da fila de polling e tenta cancelar no MP (best-effort)
    if VHubDF.Queue then VHubDF.Queue.untrack(txid) end
    MP.cancel(txid, function(_) end)

    onDone(true, 'Cobrança cancelada.')
end


-- ============================================================
-- CONSULTA — lista de pendentes do jogador (para NUI)
-- ============================================================

-- retorna lista de cobranças pendentes do jogador (máx. 10)
function Payments.getPlayerPending(src)
    local charId = Core.getCharId(src)
    if not charId then return {} end
    local rows = SQL.query(
        [[SELECT id, txid, product_key, product_desc, amount_brl,
                 UNIX_TIMESTAMP(expires_at) AS expires_at,
                 UNIX_TIMESTAMP(created_at) AS created_at,
                 status
          FROM vhub_df_orders
          WHERE char_id = ? AND status = 'pending'
          ORDER BY created_at DESC LIMIT 10]],
        { charId }
    )
    return rows or {}
end
