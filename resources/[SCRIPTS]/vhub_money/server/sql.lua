-- server/sql.lua — vhub_money (Fleeca Camell)
-- Wrapper oxmysql + queries preparadas. Resource externo: NAO usa S:prepare cross-resource.

VHubMoneySQL = { ready = false }
local S = VHubMoneySQL

-- ── Helpers async ────────────────────────────────────────────────────────────

function S.query(sql, params)
  local p = promise.new()
  exports.oxmysql:query(sql, params or {}, function(rows) p:resolve(rows or {}) end)
  return Citizen.Await(p)
end

function S.execute(sql, params)
  local p = promise.new()
  exports.oxmysql:execute(sql, params or {}, function(result) p:resolve(result or 0) end)
  return Citizen.Await(p)
end

function S.execute_raw(sql)
  local p = promise.new()
  exports.oxmysql:execute(sql, {}, function() p:resolve(true) end)
  return Citizen.Await(p)
end

-- ── Accounts ────────────────────────────────────────────────────────────────

-- Carrega conta (ou cria com saldos iniciais)
function S.load_account(char_id, initial_wallet, initial_bank)
  local rows = S.query(
    "SELECT wallet, bank, total_in, total_out FROM vh_money_accounts WHERE char_id = ? LIMIT 1",
    { char_id })

  if rows and rows[1] then
    return {
      wallet    = tonumber(rows[1].wallet)    or 0,
      bank      = tonumber(rows[1].bank)      or 0,
      total_in  = tonumber(rows[1].total_in)  or 0,
      total_out = tonumber(rows[1].total_out) or 0,
      new       = false,
    }
  end

  -- Cria com saldo inicial
  S.execute([[
    INSERT INTO vh_money_accounts (char_id, wallet, bank)
    VALUES (?, ?, ?)
    ON DUPLICATE KEY UPDATE wallet = VALUES(wallet)
  ]], { char_id, initial_wallet or 0, initial_bank or 0 })

  return {
    wallet    = initial_wallet or 0,
    bank      = initial_bank   or 0,
    total_in  = 0,
    total_out = 0,
    new       = true,
  }
end

-- Persiste saldo da conta (chamado pelo autosave do core)
function S.save_account(char_id, wallet, bank, total_in, total_out)
  S.execute([[
    UPDATE vh_money_accounts
    SET wallet = ?, bank = ?, total_in = ?, total_out = ?
    WHERE char_id = ?
  ]], { wallet, bank, total_in, total_out, char_id })
  local rows = S.query([[
    SELECT wallet, bank, total_in, total_out
    FROM vh_money_accounts WHERE char_id = ? LIMIT 1
  ]], { char_id })
  local row = rows and rows[1]
  return row ~= nil
    and tonumber(row.wallet) == tonumber(wallet)
    and tonumber(row.bank) == tonumber(bank)
    and tonumber(row.total_in) == tonumber(total_in)
    and tonumber(row.total_out) == tonumber(total_out)
end

-- Save em batch (para shutdown emergencia). Usa multi-row update via INSERT ... ON DUPLICATE
function S.save_accounts_batch(rows)
  if type(rows) ~= 'table' or #rows == 0 then return 0 end
  local placeholders = {}
  local read_placeholders = {}
  local params = {}
  local expected = {}
  for _, r in ipairs(rows) do
    placeholders[#placeholders + 1] = '(?, ?, ?, ?, ?)'
    read_placeholders[#read_placeholders + 1] = '?'
    params[#params + 1] = r.char_id
    params[#params + 1] = r.wallet
    params[#params + 1] = r.bank
    params[#params + 1] = r.total_in
    params[#params + 1] = r.total_out
    expected[tonumber(r.char_id)] = r
  end
  S.execute([[
    INSERT INTO vh_money_accounts (char_id, wallet, bank, total_in, total_out)
    VALUES ]] .. table.concat(placeholders, ',') .. [[
    ON DUPLICATE KEY UPDATE
      wallet    = VALUES(wallet),
      bank      = VALUES(bank),
      total_in  = VALUES(total_in),
      total_out = VALUES(total_out)
  ]], params)
  local read_params = {}
  for _, r in ipairs(rows) do read_params[#read_params + 1] = r.char_id end
  local stored = S.query(([[
    SELECT char_id, wallet, bank, total_in, total_out
    FROM vh_money_accounts WHERE char_id IN (%s)
  ]]):format(table.concat(read_placeholders, ',')), read_params)
  if not stored or #stored ~= #rows then return false end
  for _, row in ipairs(stored) do
    local target = expected[tonumber(row.char_id)]
    if not target
      or tonumber(row.wallet) ~= tonumber(target.wallet)
      or tonumber(row.bank) ~= tonumber(target.bank)
      or tonumber(row.total_in) ~= tonumber(target.total_in)
      or tonumber(row.total_out) ~= tonumber(target.total_out) then
      return false
    end
  end
  return true
end

-- Credita o BANCO de um char_id OFFLINE de forma atomica no DB (bank += amount).
-- Usado por payout/refund de leilao quando o alvo nao esta online (sem cache VRAM).
function S.add_bank_offline(char_id, amount)
  return S.execute([[
    INSERT INTO vh_money_accounts (char_id, wallet, bank, total_in)
    VALUES (?, 0, ?, ?)
    ON DUPLICATE KEY UPDATE bank = bank + VALUES(bank), total_in = total_in + VALUES(total_in)
  ]], { char_id, amount, amount })
end

-- ── Transactions (log auditavel) ─────────────────────────────────────────────

-- Append-only. Fire-and-forget: nao bloqueia o caller.
function S.tx_insert(tx)
  exports.oxmysql:execute([[
    INSERT INTO vh_money_transactions
      (actor_char_id, target_char_id, kind, amount,
       source_account, target_account, balance_wallet, balance_bank, reason)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    tonumber(tx.actor_char_id)  or 0,
    tonumber(tx.target_char_id) or 0,
    tostring(tx.kind   or 'unknown'),
    tonumber(tx.amount or 0),
    tostring(tx.source_account or 'none'),
    tostring(tx.target_account or 'none'),
    tonumber(tx.balance_wallet or 0),
    tonumber(tx.balance_bank   or 0),
    tostring(tx.reason or ''),
  }, function() end)
end

-- Multi-insert (mais eficiente quando temos varias txs ao mesmo tempo, ex: transferencia)
function S.tx_insert_batch(rows)
  if type(rows) ~= 'table' or #rows == 0 then return end
  local placeholders = {}
  local params = {}
  for _, t in ipairs(rows) do
    placeholders[#placeholders + 1] = '(?, ?, ?, ?, ?, ?, ?, ?, ?)'
    params[#params + 1] = tonumber(t.actor_char_id)  or 0
    params[#params + 1] = tonumber(t.target_char_id) or 0
    params[#params + 1] = tostring(t.kind   or 'unknown')
    params[#params + 1] = tonumber(t.amount or 0)
    params[#params + 1] = tostring(t.source_account or 'none')
    params[#params + 1] = tostring(t.target_account or 'none')
    params[#params + 1] = tonumber(t.balance_wallet or 0)
    params[#params + 1] = tonumber(t.balance_bank   or 0)
    params[#params + 1] = tostring(t.reason or '')
  end
  exports.oxmysql:execute([[
    INSERT INTO vh_money_transactions
      (actor_char_id, target_char_id, kind, amount,
       source_account, target_account, balance_wallet, balance_bank, reason)
    VALUES ]] .. table.concat(placeholders, ','), params, function() end)
end

-- Lista ultimas N transacoes envolvendo o char_id (como actor OU target)
function S.tx_fetch(char_id, limit)
  local lim = math.min(math.max(tonumber(limit) or 50, 1), 200)
  return S.query([[
    SELECT id, actor_char_id, target_char_id, kind, amount,
           source_account, target_account, balance_wallet, balance_bank, reason,
           UNIX_TIMESTAMP(created_at) AS created_unix
    FROM vh_money_transactions
    WHERE actor_char_id = ? OR target_char_id = ?
    ORDER BY id DESC
    LIMIT ?
  ]], { char_id, char_id, lim })
end

-- ── Schema apply ─────────────────────────────────────────────────────────────

-- Localiza a operação monetária sem expor o valor ao caller externo.
function S.find_payment_operation(operation_id)
  local rows = S.query([[
    SELECT operation_id, char_id, amount, wallet_debit, bank_debit, reason, state
    FROM vh_money_operations
    WHERE operation_id = ?
    LIMIT 1
  ]], { operation_id })
  return rows and rows[1] or nil
end

-- Debita carteira+banco e grava o ledger na mesma transação SQL.
function S.commit_payment(char_id, amount, operation_id, reason, request_conflict_key)
  local outcome = { err = 'storage' }
  local canonical = ('v1:%d:%d:%s'):format(char_id, amount, reason)

  local called, committed = pcall(MySQL.startTransaction, function(query)
    local prior
    if type(request_conflict_key) == 'string' and #request_conflict_key >= 8 then
      query([[
        INSERT IGNORE INTO vh_money_payment_requests (char_id, request_key, operation_id)
        VALUES (?, ?, ?)
      ]], { char_id, request_conflict_key, operation_id })
      local requests = query([[
        SELECT operation_id
        FROM vh_money_payment_requests
        WHERE char_id = ? AND request_key = ?
        FOR UPDATE
      ]], { char_id, request_conflict_key })
      local request = requests and requests[1]
      if not request or tostring(request.operation_id) ~= operation_id then
        outcome = { err = 'conflict' }
        return false
      end
      prior = query([[
        SELECT operation_id, char_id, amount, wallet_debit, bank_debit, reason, state
        FROM vh_money_operations
        WHERE operation_id = ?
        FOR UPDATE
      ]], { operation_id })
    else
      prior = query([[
        SELECT operation_id, char_id, amount, wallet_debit, bank_debit, reason, state
        FROM vh_money_operations
        WHERE operation_id = ?
        FOR UPDATE
      ]], { operation_id })
    end
    local row = prior and prior[1]

    if row then
      if tostring(row.operation_id) ~= operation_id
        or tonumber(row.char_id) ~= char_id
        or tonumber(row.amount) ~= amount
        or tostring(row.reason) ~= reason then
        outcome = { err = 'conflict' }
        return false
      end

      if row.state ~= 'charged' then
        outcome = { err = 'conflict' }
        return false
      end

      outcome = {
        ok = true,
        charged = true,
        wallet_debit = tonumber(row.wallet_debit) or 0,
        bank_debit = tonumber(row.bank_debit) or 0,
        replayed = true,
      }
      return true
    end

    local accounts = query([[
      SELECT wallet, bank
      FROM vh_money_accounts
      WHERE char_id = ?
      FOR UPDATE
    ]], { char_id })
    local account = accounts and accounts[1]
    if not account then
      outcome = { err = 'storage' }
      return false
    end

    local wallet = tonumber(account.wallet) or 0
    local bank = tonumber(account.bank) or 0
    if wallet + bank < amount then
      outcome = { err = 'insufficient' }
      return false
    end

    local wallet_debit = math.min(wallet, amount)
    local bank_debit = amount - wallet_debit
    local new_wallet = wallet - wallet_debit
    local new_bank = bank - bank_debit
    local updated = query([[
      UPDATE vh_money_accounts
      SET wallet = ?, bank = ?, total_out = total_out + ?
      WHERE char_id = ? AND wallet = ? AND bank = ?
    ]], { new_wallet, new_bank, amount, char_id, wallet, bank })
    if not updated or tonumber(updated.affectedRows) ~= 1 then
      outcome = { err = 'conflict' }
      return false
    end

    query([[
      INSERT INTO vh_money_operations
        (operation_id, char_id, payload_digest, amount, wallet_debit, bank_debit, reason, state)
      VALUES (?, ?, SHA2(?, 256), ?, ?, ?, ?, 'charged')
    ]], { operation_id, char_id, canonical, amount, wallet_debit, bank_debit, reason })
    query([[
      INSERT INTO vh_money_transactions
        (actor_char_id, target_char_id, kind, amount, source_account, target_account,
         balance_wallet, balance_bank, reason)
      VALUES (?, ?, 'payment', ?, 'wallet', 'none', ?, ?, ?)
    ]], { char_id, char_id, amount, new_wallet, new_bank, reason })

    outcome = {
      ok = true,
      charged = true,
      wallet_debit = wallet_debit,
      bank_debit = bank_debit,
      wallet = new_wallet,
      bank = new_bank,
      replayed = false,
    }
    return true
  end)

  if not called or committed ~= true then return outcome end
  return outcome
end

-- Restaura exatamente o split registrado, inclusive com o personagem offline.
function S.refund_payment(operation_id)
  local outcome = { err = 'storage' }

  local called, committed = pcall(MySQL.startTransaction, function(query)
    local rows = query([[
      SELECT char_id, amount, wallet_debit, bank_debit, reason, state
      FROM vh_money_operations
      WHERE operation_id = ?
      FOR UPDATE
    ]], { operation_id })
    local operation = rows and rows[1]
    if not operation then
      outcome = { err = 'not_found' }
      return false
    end

    local char_id = tonumber(operation.char_id) or 0
    local amount = tonumber(operation.amount) or 0
    local wallet_debit = tonumber(operation.wallet_debit) or 0
    local bank_debit = tonumber(operation.bank_debit) or 0
    local accounts = query([[
      SELECT wallet, bank
      FROM vh_money_accounts
      WHERE char_id = ?
      FOR UPDATE
    ]], { char_id })
    local account = accounts and accounts[1]
    if not account then
      outcome = { err = 'storage' }
      return false
    end

    if operation.state == 'refunded' then
      outcome = {
        ok = true,
        refunded = true,
        char_id = char_id,
        wallet = tonumber(account.wallet) or 0,
        bank = tonumber(account.bank) or 0,
        replayed = true,
      }
      return true
    end

    local new_wallet = (tonumber(account.wallet) or 0) + wallet_debit
    local new_bank = (tonumber(account.bank) or 0) + bank_debit
    local updated = query([[
      UPDATE vh_money_accounts
      SET wallet = ?, bank = ?, total_out = GREATEST(total_out - ?, 0)
      WHERE char_id = ?
    ]], { new_wallet, new_bank, amount, char_id })
    if not updated or tonumber(updated.affectedRows) ~= 1 then
      outcome = { err = 'conflict' }
      return false
    end

    local operation_updated = query([[
      UPDATE vh_money_operations
      SET state = 'refunded'
      WHERE operation_id = ? AND state = 'charged'
    ]], { operation_id })
    if not operation_updated or tonumber(operation_updated.affectedRows) ~= 1 then
      outcome = { err = 'conflict' }
      return false
    end

    query([[
      INSERT INTO vh_money_transactions
        (actor_char_id, target_char_id, kind, amount, source_account, target_account,
         balance_wallet, balance_bank, reason)
      VALUES (0, ?, 'refund', ?, 'none', 'wallet', ?, ?, ?)
    ]], { char_id, amount, new_wallet, new_bank, 'refund:' .. operation_id })
    outcome = {
      ok = true,
      refunded = true,
      char_id = char_id,
      wallet = new_wallet,
      bank = new_bank,
      replayed = false,
    }
    return true
  end)

  if not called or committed ~= true then return outcome end
  return outcome
end

function S.apply_schema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if type(schema) ~= 'string' or schema == '' then
    return false, 'schema_file_missing'
  end
  S.execute_raw(schema)
  S.ready = true
  return true
end
