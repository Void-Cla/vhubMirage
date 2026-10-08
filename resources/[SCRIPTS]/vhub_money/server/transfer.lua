-- server/transfer.lua — transferencias P2P atomicas e idempotentes.

VHubMoneyTransfer = {}
local T = VHubMoneyTransfer
local Cfg = VHubMoneyCfg
local H = VHubMoneyH
local Core = VHubMoneyCore
local SQL = VHubMoneySQL

local sequence = 0

local function clean_reason(value, fallback)
  if type(value) ~= 'string' then return fallback end
  local clean = value:gsub('[%c]', ''):sub(1, 180)
  return clean ~= '' and clean or fallback
end

local function operation_id(prefix, actor_char_id, supplied)
  if supplied ~= nil then
    if type(supplied) ~= 'string' or #supplied < 8 or #supplied > 48
        or not supplied:match('^[%w:_%-]+$') then
      return nil
    end
    return ('%s:%d:%s'):format(prefix, actor_char_id, supplied)
  end
  sequence = (sequence + 1) % 1000000
  return ('%s:%d:%d:%d:%d'):format(prefix, actor_char_id, os.time(), GetGameTimer(), sequence)
end

function T.new_operation_id(prefix)
  return operation_id(tostring(prefix or 'operation'), 0, nil)
end

local function lock_pair(actor_char_id, target_char_id, token)
  if Core._operation_locks[actor_char_id] or Core._operation_locks[target_char_id] then return false end
  Core._operation_locks[actor_char_id] = token
  Core._operation_locks[target_char_id] = token
  return true
end

local function unlock_pair(actor_char_id, target_char_id, token)
  if Core._operation_locks[actor_char_id] == token then Core._operation_locks[actor_char_id] = nil end
  if Core._operation_locks[target_char_id] == token then Core._operation_locks[target_char_id] = nil end
end

local function preflush(entry)
  if not entry or not entry.dirty then return true end
  local ok = SQL.save_account(entry.char_id, entry.wallet, entry.bank, entry.total_in, entry.total_out)
  if ok == true then
    entry.dirty = false
    entry.last_save_ms = GetGameTimer()
  end
  return ok == true
end

local function apply_snapshot(entry, snapshot)
  if not entry or not snapshot or Core._by_char[entry.char_id] ~= entry then return end
  entry.wallet = snapshot.wallet
  entry.bank = snapshot.bank
  entry.total_in = snapshot.total_in
  entry.total_out = snapshot.total_out
  entry.dirty = false
  entry.revision = entry.revision + 1
  entry.last_save_ms = GetGameTimer()
  pcall(Core.sync_state_bag, entry)
end

function T.resolve_target_char(raw)
  local kind, value = H.detect_target_kind(raw)
  if not kind then return nil, 'identificador_invalido' end
  if kind == 'char_id' then return tonumber(value), nil end

  local char_id
  if kind == 'phone' and Cfg.TRANSFER.BY_PHONE then
    pcall(function() char_id = exports.vhub_identity:getCharByPhone(value) end)
    return char_id, char_id and nil or 'telefone_nao_encontrado'
  end
  if kind == 'registration' and Cfg.TRANSFER.BY_REGISTRATION then
    pcall(function() char_id = exports.vhub_identity:getCharByRegistration(value) end)
    return char_id, char_id and nil or 'registro_nao_encontrado'
  end
  return nil, 'tipo_de_chave_desabilitado'
end

local function execute(actor_entry, target_entry, target_char_id, amount, fee, kind, reason, request_id)
  local prefix = kind == 'cash_give' and 'give' or 'transfer'
  local op = operation_id(prefix, actor_entry.char_id, request_id)
  if not op then return false, 'conflict' end
  local token = op
  if not lock_pair(actor_entry.char_id, target_char_id, token) then return false, 'busy' end

  local called, outcome = pcall(function()
    if not preflush(actor_entry) or not preflush(target_entry) then return { err = 'storage' } end
    return SQL.transfer_atomic(actor_entry.char_id, target_char_id, amount, fee, kind, op, reason)
  end)

  if called and outcome and outcome.ok then
    apply_snapshot(actor_entry, outcome.actor)
    apply_snapshot(target_entry, outcome.target)
  end
  unlock_pair(actor_entry.char_id, target_char_id, token)

  if not called or not outcome or not outcome.ok then
    return false, outcome and outcome.err or 'storage'
  end
  if outcome.replayed ~= true then
    Core.metrics.transactions = (Core.metrics.transactions or 0) + (fee > 0 and 3 or 2)
  end
  return true, outcome
end

function T.try_transfer(actor_src, target_raw, amount, reason, request_id)
  local cfg = Cfg.TRANSFER
  local actor_entry = Core.by_src(tonumber(actor_src) or 0)
  if not actor_entry then return false, 'sem_sessao' end

  local n = H.amount(amount)
  if n < (cfg.MIN_AMOUNT or 1) then return false, 'valor_abaixo_do_minimo' end
  if cfg.MAX_AMOUNT > 0 and n > cfg.MAX_AMOUNT then return false, 'valor_acima_do_maximo' end

  local target_char_id, err = T.resolve_target_char(target_raw)
  if not target_char_id then return false, err or 'destino_invalido' end
  if target_char_id == actor_entry.char_id then return false, 'autotransferencia' end

  local target_entry = Core.by_char(target_char_id)
  if cfg.REQUIRE_TARGET_ONLINE and not target_entry then return false, 'destinatario_offline' end
  local fee = actor_entry.owner and 0 or H.transfer_fee(n, cfg.FEE_PERCENT, cfg.FEE_FIXED)
  if actor_entry.bank < n + fee then return false, 'saldo_insuficiente' end

  local ok, result = execute(actor_entry, target_entry, target_char_id, n, fee, 'bank_transfer',
    clean_reason(reason, 'transfer_p2p'), request_id)
  if not ok then return false, result end

  if target_entry and target_entry.src and target_entry.src > 0 and result.replayed ~= true then
    TriggerClientEvent('vhub_money:notify', target_entry.src,
      ('Transferencia recebida: %s'):format(H.fmt(n)), 'success')
  end
  return true, {
    amount = n,
    fee = fee,
    new_bank = result.actor.bank,
    target_char = target_char_id,
    replayed = result.replayed == true,
  }
end

function T.try_give(actor_src, target_src, amount, reason, request_id)
  local actor_entry = Core.by_src(tonumber(actor_src) or 0)
  local target_entry = Core.by_src(tonumber(target_src) or 0)
  if not actor_entry then return false, 'sem_sessao' end
  if not target_entry then return false, 'destino_offline' end
  if actor_entry.char_id == target_entry.char_id then return false, 'autotransferencia' end

  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  if actor_entry.wallet < n then return false, 'saldo_insuficiente' end

  local ok, result = execute(actor_entry, target_entry, target_entry.char_id, n, 0, 'cash_give',
    clean_reason(reason, 'cash_give'), request_id)
  if not ok then return false, result end
  return true, { amount = n, target_char = target_entry.char_id, replayed = result.replayed == true }
end
