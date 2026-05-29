---@diagnostic disable: undefined-global, lowercase-global

-- server/rewards.lua — interface unica com vhub_money.
--
-- Modulos chamam Rewards.charge_entry / refund / pay / has_balance.
-- NUNCA chamar exports.vhub_money direto em outros modulos — esse arquivo
-- e a fronteira do dominio "dinheiro do racha".
--
-- Toda chamada e protegida por pcall (vhub_money pode estar carregando
-- ou indisponivel — o racha sobrevive). Em falha, registra erro mas nao
-- crasha o lobby.


VHubRachaRewards = {}
local R = VHubRachaRewards


-- ============================================================
-- CHARGE — cobra fee de entrada do lobby
-- ============================================================

-- Tenta debitar `fee` da carteira+banco. Retorna true se debitou.
-- Em caso de saldo insuficiente ou erro, retorna false + mensagem opcional.
function R.charge_entry(src, fee, reason)
    if (fee or 0) <= 0 then return true end

    local ok, err
    local _ok, _err = pcall(function()
        ok, err = exports.vhub_money:tryFullPayment(src, fee, false)
    end)

    if not _ok then return false, tostring(_err) end
    return ok == true, err
end


-- ============================================================
-- REFUND — devolve fee em caso de cancelamento
-- ============================================================

-- Deposita `amount` no banco do player. Usado em leave/cancel/erro.
function R.refund(src, amount, reason)
    if (amount or 0) <= 0 then return end

    pcall(function()
        exports.vhub_money:giveBank(src, math.floor(amount), reason or 'racha_refund')
    end)
end


-- ============================================================
-- PAY — premio (vai pro banco)
-- ============================================================

-- Deposita `amount` no banco como premio de corrida.
function R.pay(src, amount, reason)
    if (amount or 0) <= 0 then return end

    pcall(function()
        exports.vhub_money:giveBank(src, math.floor(amount), reason or 'racha_payout')
    end)
end


-- ============================================================
-- HAS_BALANCE — dry-run (nao debita)
-- ============================================================

-- Verifica se o player tem `amount` disponivel sem debitar.
-- Util para gating de UI ("voce nao tem saldo para entrar").
function R.has_balance(src, amount)
    if (amount or 0) <= 0 then return true end

    local ok = false
    pcall(function()
        ok = exports.vhub_money:tryFullPayment(src, amount, true) == true
    end)
    return ok
end
