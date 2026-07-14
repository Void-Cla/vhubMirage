-- server/queue.lua — fila de verificação periódica + recuperação pós-restart
--
-- Responsabilidade:
--   • track/untrack de pedidos pendentes em memória (txid → contador de checks)
--   • loop de polling (cfg.polling.intervalMs) → Payments.verifyAndSettle por pedido
--   • recuperação no boot: recarrega TODOS os pending do SQL e retoma o polling —
--     inclusive os já vencidos (o jogador pode ter PAGO enquanto o servidor caiu;
--     verifyAndSettle entrega se aprovado, e só expira se o MP confirmar pendente)
--
-- ORÇAMENTO (L-18): 1 ciclo a cada intervalMs (5s); custo O(n_pendentes) por ciclo,
-- limitado por maxPendingPerPlayer; yield a cada batchYield pedidos; fila vazia = só Wait.

VHubDF = VHubDF or {}
local Queue = {}
VHubDF.Queue = Queue

local Core     = VHubDF.Core
local Payments = VHubDF.Payments


-- ============================================================
-- REGISTRO EM MEMÓRIA
-- ============================================================

local _watch = {}   -- txid → { orderId, checks }
local _count = 0

-- adiciona um pedido pendente à fila de verificação (idempotente)
function Queue.track(txid, orderId)
    if not txid or txid == '' or _watch[txid] then return end
    _watch[txid] = { orderId = orderId, checks = 0 }
    _count = _count + 1
    Core.log(('Queue: rastreando txid=%s (%d na fila)'):format(txid, _count))
end

-- remove um pedido da fila (liquidado, cancelado ou expirado)
function Queue.untrack(txid)
    if _watch[txid] then
        _watch[txid] = nil
        _count = _count - 1
    end
end

-- quantidade de pedidos na fila (debug/status)
function Queue.size() return _count end


-- ============================================================
-- CICLO DE POLLING — verdade sempre re-consultada no MP
-- ============================================================

-- executa um ciclo de verificação sobre um snapshot da fila
local function pollCycle()
    local cfg = VHubDF.cfg.polling

    -- snapshot: verifyAndSettle pode track/untrack durante a iteração
    local list = {}
    for txid in pairs(_watch) do list[#list + 1] = txid end

    for i = 1, #list do
        local txid = list[i]
        local w    = _watch[txid]

        if w then
            w.checks = w.checks + 1

            local outcome = nil
            Payments.verifyAndSettle(txid, 'polling', function(o) outcome = o end)
            -- verifyAndSettle usa Await interno → nesta thread, outcome já resolveu aqui

            if outcome and outcome ~= 'pending' and outcome ~= 'error' then
                Queue.untrack(txid)
            elseif w.checks >= cfg.maxChecks then
                -- teto de tentativas: NÃO expira às cegas — o pedido pode estar PAGO
                -- e apenas sem handler/erro transitório. Sai da fila; segue pending no
                -- banco e a recuperação do próximo boot re-tenta. (expiração legítima
                -- já acontece antes, via verifyAndSettle quando o MP confirma pendente)
                Core.logErr(('Queue: txid=%s atingiu %d checks — fora da fila; segue pending no banco p/ recuperação'):format(
                    txid, cfg.maxChecks))
                Queue.untrack(txid)
            end
        end

        if i % cfg.batchYield == 0 then Citizen.Wait(0) end
    end
end

-- loop principal — sai quando o resource para (condição de saída explícita)
local _alive = true

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then _alive = false end
end)

Citizen.CreateThread(function()
    while _alive do
        Citizen.Wait(VHubDF.cfg.polling.intervalMs)
        if _count > 0 and VHubDF.cfg.enabled then
            local ok, err = pcall(pollCycle)
            if not ok then Core.logErr('Queue: ciclo falhou — ' .. tostring(err)) end
        end
    end
end)


-- ============================================================
-- RECUPERAÇÃO PÓS-RESTART — nenhum Pix pago se perde (L-17)
-- ============================================================

local _recovered = false

-- recarrega todos os pedidos pending do banco e retoma o polling (replay-guard)
function Queue.recover()
    if _recovered then return end
    _recovered = true

    local rows = SQL.query(
        "SELECT id, txid FROM vhub_df_orders WHERE status = 'pending'")
    if not rows or #rows == 0 then
        Core.log('Queue: nenhum pedido pendente para recuperar')
        return
    end

    for i = 1, #rows do
        Queue.track(rows[i].txid, rows[i].id)
    end
    Core.log(('Queue: %d pedidos pendentes recuperados pós-restart'):format(#rows))
end
