-- server/exports.lua — vhub_money (Fleeca Camell)
-- API publica. Mutacoes sao protegidas por _invoker_allowed().
-- Mantem compatibilidade com nomes do vhub_money v1 (getWallet/getBank/giveWallet/etc).

local Cfg  = VHubMoneyCfg
local Core = VHubMoneyCore
local SQL  = VHubMoneySQL
local A    = VHubMoneyATM
local T    = VHubMoneyTransfer

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return true end   -- chamada local
  local trusted = Cfg.TRUSTED_RESOURCES
  if type(trusted) ~= 'table' or next(trusted) == nil then return false end
  return trusted[caller] == true
end

local PAYMENT_SAGA_CALLERS = {
  vhub_sims   = { reason_prefix = 'sims:', digest_operation = true },
  vhub_custom = { reason_prefix = 'custom.', operation_prefix = 'vc:', request_conflict = true },
}

local function _payment_saga_scope()
  local caller = GetInvokingResource()
  if caller == nil then return {} end
  return PAYMENT_SAGA_CALLERS[caller]
end

local function _payment_contract(scope, operation_id, reason)
  if not scope or type(operation_id) ~= 'string' or type(reason) ~= 'string' then return false end
  if scope.reason_prefix and reason:sub(1, #scope.reason_prefix) ~= scope.reason_prefix then return false end
  if scope.operation_prefix and operation_id:sub(1, #scope.operation_prefix) ~= scope.operation_prefix then
    return false
  end
  if scope.digest_operation and (#operation_id ~= 64 or not operation_id:match('^[%x]+$')) then return false end
  if scope.request_conflict then
    local suffix = operation_id:match(':([%x]+)$')
    if not suffix or #suffix ~= 8 then return false end
  end
  return true
end

local function _request_conflict_key(scope, operation_id)
  if not scope.request_conflict then return nil end
  return operation_id:sub(1, -10)
end

-- ── Read-only (publicos) ────────────────────────────────────────────────────

exports('getWallet', function(src)
  return Core.get_wallet(tonumber(src) or 0)
end)

exports('getBank', function(src)
  return Core.get_bank(tonumber(src) or 0)
end)

exports('getBalance', function(src)
  return Core.get_balance(tonumber(src) or 0)
end)

exports('isOwner', function(src)
  local e = Core.by_src(tonumber(src) or 0)
  return e and e.owner == true or false
end)

-- ── try* (publicos — usados por outros resources como vhub_garage) ──────────

exports('tryPayment', function(src, valor, dry)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.try_payment(tonumber(src) or 0, valor, dry == true, 'export_payment')
end)

exports('tryWithdraw', function(src, valor, dry)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.try_withdraw(tonumber(src) or 0, valor, dry == true, 'export_withdraw')
end)

exports('tryDeposit', function(src, valor, dry)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.try_deposit(tonumber(src) or 0, valor, dry == true, 'export_deposit')
end)

exports('tryFullPayment', function(src, valor, dry)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.try_full_payment(tonumber(src) or 0, valor, dry == true, 'export_full_payment')
end)

-- Debita uma operação identificada; replay devolve o mesmo resultado.
exports('commitPayment', function(src, amount, operation_id, reason)
  local scope = _payment_saga_scope()
  if not _payment_contract(scope, operation_id, reason) then return { ok = false, err = 'forbidden' } end
  return Core.commit_payment(tonumber(src) or 0, amount, operation_id, reason,
    _request_conflict_key(scope, operation_id))
end)

-- Estorna offline o split original; somente sagas explicitamente autorizadas compensam.
exports('refundPayment', function(operation_id)
  local scope = _payment_saga_scope()
  if not scope or type(operation_id) ~= 'string'
      or (scope.operation_prefix and operation_id:sub(1, #scope.operation_prefix) ~= scope.operation_prefix)
      or (scope.digest_operation and (#operation_id ~= 64 or not operation_id:match('^[%x]+$')))
      or (scope.request_conflict and not (operation_id:match(':([%x]+)$') or ''):match('^........$')) then
    return { ok = false, err = 'forbidden' }
  end
  return Core.refund_payment(operation_id, scope.reason_prefix)
end)

-- ── Mutacoes TRUSTED (admin/job/payout) ─────────────────────────────────────

exports('giveWallet', function(src, valor, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.give_wallet(tonumber(src) or 0, valor, reason or 'export_give_wallet')
end)

exports('giveBank', function(src, valor, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.give_bank(tonumber(src) or 0, valor, reason or 'export_give_bank')
end)

-- credita o BANCO por char_id, online OU offline (payout/refund de leilao seguro)
exports('giveBankChar', function(char_id, valor, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.give_bank_char(tonumber(char_id) or 0, valor, reason or 'export_give_bank_char')
end)

exports('setWallet', function(src, valor, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.set_wallet(tonumber(src) or 0, valor, reason or 'export_set_wallet')
end)

exports('setBank', function(src, valor, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  return Core.set_bank(tonumber(src) or 0, valor, reason or 'export_set_bank')
end)

-- ── Transferencia P2P ───────────────────────────────────────────────────────

exports('tryTransfer', function(actor_src, target_raw, valor, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  return T.try_transfer(actor_src, target_raw, valor, reason or 'export_transfer')
end)

exports('tryGive', function(actor_src, target_src, valor, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  return T.try_give(actor_src, target_src, valor, reason or 'export_give')
end)

-- ── ATM helpers (para futuros resources de pacotes/multas) ──────────────────

exports('atmWithdraw', function(src, valor)
  if not _invoker_allowed() then return false, 'forbidden' end
  return A.atm_withdraw(src, valor)
end)

exports('atmDeposit', function(src, valor)
  if not _invoker_allowed() then return false, 'forbidden' end
  return A.atm_deposit(src, valor)
end)

-- ── Auditoria (read TRUSTED) ────────────────────────────────────────────────

exports('getTransactions', function(src_or_char, limit)
  if not _invoker_allowed() then return {} end
  local n = tonumber(src_or_char) or 0
  local entry = Core.by_src(n) or Core.by_char(n)
  local char_id = entry and entry.char_id or n
  return SQL.tx_fetch(char_id, limit or Cfg.AUDIT.LIMIT_DEFAULT)
end)

-- ── Status ──────────────────────────────────────────────────────────────────

exports('Status', function()
  local sessions = 0
  for _ in pairs(Core._by_char) do sessions = sessions + 1 end
  return {
    ready    = Core.is_ready(),
    sql_ready = SQL.ready,
    sessions = sessions,
    metrics  = Core.metrics,
  }
end)
