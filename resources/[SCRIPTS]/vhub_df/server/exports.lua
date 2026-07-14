-- server/exports.lua — superfície pública do vhub_df (export-first, gated default-deny)
--
-- CONSUMO (de outro resource TRUSTED, sempre server-side):
--
--   -- 1. registra o entregador da família 'coins' (uma vez, no boot do consumidor)
--   exports.vhub_df:registerHandler('coins', function(charId, orderId, meta, done)
--       -- creditar aqui… done(true, 'ok') / done(false, 'motivo p/ retry')
--   end)
--
--   -- 2. cria a cobrança (o CONSUMIDOR mapeia pacote→preço; nunca o cliente)
--   exports.vhub_df:createPayment(src, {
--       amountBRL   = 19.90,
--       productKey  = 'coins:100',          -- prefixo decide o handler
--       productDesc = '100 Moedas vHub',
--       metadata    = { pack = 1 },         -- opcional, ≤ 512B em JSON
--       openNui     = true,                 -- false = consumidor mostra o QR na própria UI
--   }, function(ok, result) ... end)        -- result: txid, qrBase64, copiaECola, expiresAt

local Core     = VHubDF.Core
local Payments = VHubDF.Payments


-- ============================================================
-- GATE — default-deny via convar vhub_trusted_resources
-- ============================================================

-- retorna o nome do invoker se autorizado; nil caso contrário
local function _invoker_allowed()
    local inv = GetInvokingResource()
    if not inv then return nil end   -- console/runtime direto: negado

    local trusted = GetConvar('vhub_trusted_resources', '')
    for name in trusted:gmatch('[^,%s]+') do
        if name == inv then return inv end
    end

    Core.logErr(('exports: resource "%s" NEGADO (fora de vhub_trusted_resources)'):format(inv))
    return nil
end


-- ============================================================
-- EXPORTS
-- ============================================================

-- true quando o gateway está apto a criar cobranças (enabled + token carregado)
exports('isReady', function()
    if not _invoker_allowed() then return false end
    return VHubDF.cfg.enabled and VHubDF.MP.isReady()
end)

-- cria cobrança Pix para um jogador ONLINE; cb(ok, result) é opcional
exports('createPayment', function(src, params, cb)
    if not _invoker_allowed() then
        if cb then pcall(cb, false, { code = 'denied', message = 'Resource não autorizado.' }) end
        return false
    end

    src = tonumber(src)
    if not src or not GetPlayerName(src) then
        if cb then pcall(cb, false, { code = 'offline', message = 'Jogador offline.' }) end
        return false
    end
    if type(params) ~= 'table' then
        if cb then pcall(cb, false, { code = 'params', message = 'params deve ser table.' }) end
        return false
    end

    Citizen.CreateThread(function()
        Payments.createOrder(src, params, function(ok, result)
            if ok and params.openNui ~= false then
                Payments.pushNui(src, result)
            end
            if cb then pcall(cb, ok, result) end
        end)
    end)
    return true
end)

-- registra o callback de entrega de uma família de product_key ('coins', 'vip', …)
local _handlerOwner = {}

exports('registerHandler', function(prefix, fn)
    local inv = _invoker_allowed()
    if not inv then return false end

    if type(prefix) ~= 'string' or prefix == '' or prefix:find(':') then
        Core.logErr(('exports.registerHandler: prefix inválido de "%s"'):format(inv))
        return false
    end
    -- função cross-resource chega como TABLE chamável (funcref msgpack com __call) —
    -- aceitar ambos; a invocação real já é protegida por pcall no Payments.deliver
    local fnType = type(fn)
    if fnType ~= 'function' and fnType ~= 'table' then
        Core.logErr(('exports.registerHandler: fn de "%s" chegou como %s — esperado function/funcref'):format(
            inv, fnType))
        return false
    end

    Payments.registerHandler(prefix, fn)
    _handlerOwner[prefix] = inv
    return true
end)

-- handler de resource parado é função morta → desregistra (entrega volta a re-tentar)
AddEventHandler('onResourceStop', function(res)
    for prefix, owner in pairs(_handlerOwner) do
        if owner == res then
            Payments.unregisterHandler(prefix)
            _handlerOwner[prefix] = nil
        end
    end
end)

-- lista cobranças pendentes de um jogador; cb(rows)
exports('getPlayerPending', function(src, cb)
    if not _invoker_allowed() then
        if cb then pcall(cb, {}) end
        return false
    end
    Citizen.CreateThread(function()
        local rows = Payments.getPlayerPending(tonumber(src) or 0)
        if cb then pcall(cb, rows) end
    end)
    return true
end)

-- status LOCAL de uma order pelo txid (não consulta o MP); cb(row|nil)
exports('getOrderStatus', function(txid, cb)
    if not _invoker_allowed() then
        if cb then pcall(cb, nil) end
        return false
    end
    Citizen.CreateThread(function()
        local rows = SQL.query(
            [[SELECT id, txid, char_id, product_key, amount_brl, status,
                     UNIX_TIMESTAMP(created_at) AS created_at,
                     UNIX_TIMESTAMP(paid_at)    AS paid_at
              FROM vhub_df_orders WHERE txid = ? LIMIT 1]],
            { tostring(txid or '') })
        if cb then pcall(cb, rows and rows[1] or nil) end
    end)
    return true
end)

-- cancela cobrança pending de um jogador (mesmas regras do fluxo do próprio jogador)
exports('cancelPayment', function(src, txid, cb)
    if not _invoker_allowed() then
        if cb then pcall(cb, false, 'Resource não autorizado.') end
        return false
    end
    Citizen.CreateThread(function()
        Payments.cancel(tonumber(src) or 0, tostring(txid or ''), function(ok, msg)
            if cb then pcall(cb, ok, msg) end
        end)
    end)
    return true
end)
