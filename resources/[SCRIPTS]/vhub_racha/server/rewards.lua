-- server/rewards.lua — interface unica com vhub_money.
-- Modulos chamam Rewards.charge/refund/reward, nunca direto exports.vhub_money.

VHubRachaRewards = {}
local R = VHubRachaRewards

-- Cobra taxa de entrada (carteira + banco). Retorna true se debitou.
function R.charge_entry(src, fee, reason)
  if (fee or 0) <= 0 then return true end
  local ok = false
  local err
  local _ok, _err = pcall(function()
    ok, err = exports.vhub_money:tryFullPayment(src, fee, false)
  end)
  if not _ok then return false, tostring(_err) end
  return ok == true, err
end

-- Devolve fee (em caso de cancelamento)
function R.refund(src, amount, reason)
  if (amount or 0) <= 0 then return end
  pcall(function()
    exports.vhub_money:giveBank(src, math.floor(amount), reason or 'racha_refund')
  end)
end

-- Premio (vai pro banco)
function R.pay(src, amount, reason)
  if (amount or 0) <= 0 then return end
  pcall(function()
    exports.vhub_money:giveBank(src, math.floor(amount), reason or 'racha_payout')
  end)
end

-- Tem saldo suficiente? (dry-run, nao debita)
function R.has_balance(src, amount)
  if (amount or 0) <= 0 then return true end
  local ok = false
  pcall(function()
    ok = exports.vhub_money:tryFullPayment(src, amount, true) == true
  end)
  return ok
end
