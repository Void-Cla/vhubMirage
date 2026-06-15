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
  return S.execute([[
    UPDATE vh_money_accounts
    SET wallet = ?, bank = ?, total_in = ?, total_out = ?
    WHERE char_id = ?
  ]], { wallet, bank, total_in, total_out, char_id })
end

-- Save em batch (para shutdown emergencia). Usa multi-row update via INSERT ... ON DUPLICATE
function S.save_accounts_batch(rows)
  if type(rows) ~= 'table' or #rows == 0 then return 0 end
  local placeholders = {}
  local params = {}
  for _, r in ipairs(rows) do
    placeholders[#placeholders + 1] = '(?, ?, ?, ?, ?)'
    params[#params + 1] = r.char_id
    params[#params + 1] = r.wallet
    params[#params + 1] = r.bank
    params[#params + 1] = r.total_in
    params[#params + 1] = r.total_out
  end
  return S.execute([[
    INSERT INTO vh_money_accounts (char_id, wallet, bank, total_in, total_out)
    VALUES ]] .. table.concat(placeholders, ',') .. [[
    ON DUPLICATE KEY UPDATE
      wallet    = VALUES(wallet),
      bank      = VALUES(bank),
      total_in  = VALUES(total_in),
      total_out = VALUES(total_out)
  ]], params)
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

function S.apply_schema()
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if type(schema) ~= 'string' or schema == '' then
    return false, 'schema_file_missing'
  end
  S.execute_raw(schema)
  S.ready = true
  return true
end
