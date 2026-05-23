-- server/transfer.lua — vhub_money (Fleeca Camell)
-- Transferencia P2P (chave Pix). Aceita identificadores:
--   - char_id direto (numero)
--   - registration (registro civil — via exports.vhub_identity:getCharByRegistration)
--   - phone (telefone — via exports.vhub_identity:getCharByPhone)
--
-- Regras:
--   - server-side total: validacao de saldo, taxa, limites
--   - actor e target podem ser o mesmo char (deposito proprio noop — bloqueado)
--   - target online: atualiza VRAM + state bag
--   - target offline: aplica direto no SQL (UPDATE atomic + INSERT tx)

VHubMoneyTransfer = {}
local T = VHubMoneyTransfer
local Cfg  = VHubMoneyCfg
local H    = VHubMoneyH
local Core = VHubMoneyCore
local SQL  = VHubMoneySQL

-- ── Resolucao de identificador ──────────────────────────────────────────────

-- Resolve char_id a partir de qualquer identificador suportado
function T.resolve_target_char(raw)
  local kind, value = H.detect_target_kind(raw)
  if not kind then return nil, 'identificador_invalido' end

  if kind == 'char_id' then
    return tonumber(value), nil
  end

  if kind == 'phone' and Cfg.TRANSFER.BY_PHONE then
    local cid = nil
    pcall(function() cid = exports.vhub_identity:getCharByPhone(value) end)
    return cid, cid and nil or 'telefone_nao_encontrado'
  end

  if kind == 'registration' and Cfg.TRANSFER.BY_REGISTRATION then
    local cid = nil
    pcall(function() cid = exports.vhub_identity:getCharByRegistration(value) end)
    return cid, cid and nil or 'registro_nao_encontrado'
  end

  return nil, 'tipo_de_chave_desabilitado'
end

-- ── Operacao com target offline ─────────────────────────────────────────────

-- Atualiza saldo de uma conta offline no SQL diretamente. Retorna ok, new_bank.
local function update_offline_bank(char_id, delta)
  -- Carrega conta (cria se nao existir) — VRAM se ja estiver, senao SQL
  local entry = Core.by_char(char_id)
  if entry then
    -- Online: usa caminho de VRAM normal
    Core.apply_mutation(entry, 0, delta)
    return true, entry.bank
  end

  -- Offline: UPDATE atomic com check de saldo
  if delta < 0 then
    -- Saca offline: verifica saldo antes
    local rows = SQL.query("SELECT bank FROM vh_money_accounts WHERE char_id = ?", { char_id })
    if not rows[1] then return false, 'conta_inexistente' end
    local current = tonumber(rows[1].bank) or 0
    if current + delta < 0 then return false, 'saldo_insuficiente_offline' end
  end

  local rows = SQL.query([[
    UPDATE vh_money_accounts
    SET bank = GREATEST(0, bank + ?),
        total_in  = total_in  + IF(? > 0, ?, 0),
        total_out = total_out + IF(? < 0, ABS(?), 0)
    WHERE char_id = ?
  ]], { delta, delta, delta, delta, delta, char_id })

  -- Le saldo atualizado
  local r = SQL.query("SELECT bank FROM vh_money_accounts WHERE char_id = ? LIMIT 1", { char_id })
  return true, r[1] and tonumber(r[1].bank) or 0
end

-- ── Transferencia bank→bank P2P ─────────────────────────────────────────────

-- Transfere `amount` do banco do `actor_src` para o banco de `target_raw`.
-- target_raw pode ser char_id|registration|phone.
-- Retorna ok, payload_or_err
function T.try_transfer(actor_src, target_raw, amount, reason)
  local cfg = Cfg.TRANSFER
  local actor_entry = Core.by_src(tonumber(actor_src) or 0)
  if not actor_entry then return false, 'sem_sessao' end

  local n = H.amount(amount)
  if n < (cfg.MIN_AMOUNT or 1) then return false, 'valor_abaixo_do_minimo' end
  if cfg.MAX_AMOUNT > 0 and n > cfg.MAX_AMOUNT then return false, 'valor_acima_do_maximo' end

  -- Resolve target
  local target_char_id, err = T.resolve_target_char(target_raw)
  if not target_char_id then return false, err or 'destino_invalido' end
  if target_char_id == actor_entry.char_id then return false, 'autotransferencia' end

  -- Calcula taxa
  local fee = H.transfer_fee(n, cfg.FEE_PERCENT, cfg.FEE_FIXED)
  if actor_entry.owner then fee = 0 end   -- owner bypass

  local total_debit = n + fee
  if actor_entry.bank < total_debit then return false, 'saldo_insuficiente' end

  -- Target online?
  local target_entry = Core.by_char(target_char_id)
  if cfg.REQUIRE_TARGET_ONLINE and not target_entry then
    return false, 'destinatario_offline'
  end

  -- Debita actor
  Core.apply_mutation(actor_entry, 0, -total_debit)
  -- Nao conta total_out: foi mudanca interna (entre banco e fee). Vai pra log.
  actor_entry.total_out = actor_entry.total_out - total_debit
  actor_entry.total_in  = actor_entry.total_in  -- nada

  -- Credita target
  local ok_credit, target_balance_or_err
  if target_entry then
    Core.apply_mutation(target_entry, 0, n)
    target_entry.total_in = target_entry.total_in - n   -- compensa apply
    target_balance_or_err = target_entry.bank
    ok_credit = true
  else
    ok_credit, target_balance_or_err = update_offline_bank(target_char_id, n)
    if not ok_credit then
      -- Rollback do actor
      Core.apply_mutation(actor_entry, 0, total_debit)
      actor_entry.total_out = actor_entry.total_out + total_debit
      return false, target_balance_or_err or 'falha_credito_destino'
    end
  end

  -- Log: 2 entradas (saida do actor, entrada do target) + 1 entrada se houver taxa
  local now_entries = {
    {
      actor_char_id  = actor_entry.char_id,
      target_char_id = target_char_id,
      kind           = H.KIND.TRANSFER_OUT,
      amount         = n,
      source_account = H.ACCOUNT.BANK,
      target_account = H.ACCOUNT.BANK,
      balance_wallet = actor_entry.wallet,
      balance_bank   = actor_entry.bank,
      reason         = tostring(reason or 'transfer_p2p'),
    },
    {
      actor_char_id  = actor_entry.char_id,
      target_char_id = target_char_id,
      kind           = H.KIND.TRANSFER_IN,
      amount         = n,
      source_account = H.ACCOUNT.BANK,
      target_account = H.ACCOUNT.BANK,
      balance_wallet = target_entry and target_entry.wallet or 0,
      balance_bank   = target_balance_or_err or 0,
      reason         = tostring(reason or 'transfer_p2p'),
    },
  }
  if fee > 0 then
    now_entries[#now_entries + 1] = {
      actor_char_id  = actor_entry.char_id,
      target_char_id = actor_entry.char_id,
      kind           = H.KIND.PAYMENT,
      amount         = fee,
      source_account = H.ACCOUNT.BANK,
      target_account = H.ACCOUNT.NONE,
      balance_wallet = actor_entry.wallet,
      balance_bank   = actor_entry.bank,
      reason         = 'transfer_fee',
    }
  end
  SQL.tx_insert_batch(now_entries)
  Core.metrics.transactions = (Core.metrics.transactions or 0) + #now_entries

  -- Notifica target online
  if target_entry and target_entry.src and target_entry.src > 0 then
    TriggerClientEvent('vhub_money:notify', target_entry.src,
      ('Transferencia recebida: %s'):format(H.fmt(n)),
      'success')
  end

  return true, {
    amount       = n,
    fee          = fee,
    new_bank     = actor_entry.bank,
    target_char  = target_char_id,
  }
end

-- ── Doacao em mao (carteira → carteira, player perto) ───────────────────────

-- Entrega `amount` da carteira de actor para a carteira de target (online).
function T.try_give(actor_src, target_src, amount, reason)
  local actor_entry  = Core.by_src(tonumber(actor_src) or 0)
  local target_entry = Core.by_src(tonumber(target_src) or 0)
  if not actor_entry  then return false, 'sem_sessao' end
  if not target_entry then return false, 'destino_offline' end
  if actor_entry.char_id == target_entry.char_id then return false, 'autotransferencia' end

  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  if actor_entry.wallet < n then return false, 'saldo_insuficiente' end

  Core.apply_mutation(actor_entry, -n, 0)
  Core.apply_mutation(target_entry, n, 0)
  actor_entry.total_out  = actor_entry.total_out  - n
  target_entry.total_in  = target_entry.total_in  - n

  SQL.tx_insert_batch({
    {
      actor_char_id  = actor_entry.char_id,
      target_char_id = target_entry.char_id,
      kind           = H.KIND.GIVE,
      amount         = n,
      source_account = H.ACCOUNT.WALLET,
      target_account = H.ACCOUNT.WALLET,
      balance_wallet = actor_entry.wallet,
      balance_bank   = actor_entry.bank,
      reason         = tostring(reason or 'cash_give'),
    },
    {
      actor_char_id  = actor_entry.char_id,
      target_char_id = target_entry.char_id,
      kind           = H.KIND.GIVE,
      amount         = n,
      source_account = H.ACCOUNT.WALLET,
      target_account = H.ACCOUNT.WALLET,
      balance_wallet = target_entry.wallet,
      balance_bank   = target_entry.bank,
      reason         = tostring(reason or 'cash_give_received'),
    },
  })

  return true, { amount = n, target_char = target_entry.char_id }
end
