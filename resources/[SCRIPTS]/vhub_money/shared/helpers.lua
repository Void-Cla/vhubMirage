-- shared/helpers.lua — vhub_money (Fleeca Camell)
-- Helpers puros (sem side-effects). Disponivel server + client.

VHubMoneyH = {}
local H = VHubMoneyH

-- Sanitiza inteiro positivo (>= 0). Retorna 0 em invalido.
function H.amount(v)
  local n = math.floor(tonumber(v) or 0)
  if n < 0 then return 0 end
  return n
end

-- Sanitiza amount com max opcional
function H.amount_clamp(v, max_value)
  local n = H.amount(v)
  if max_value and max_value > 0 and n > max_value then return max_value end
  return n
end

-- Formata R$ 1.234.567 (separador de milhares = ponto, padrao BR)
function H.fmt(n, prefix, sep)
  prefix = prefix or 'R$ '
  sep    = sep or '.'
  local s, res, c = tostring(H.amount(n)), '', 0
  for i = #s, 1, -1 do
    res = s:sub(i, i) .. res
    c = c + 1
    if c % 3 == 0 and i > 1 then res = sep .. res end
  end
  return prefix .. res
end

-- Calcula taxa de transferencia (percent + fixo)
function H.transfer_fee(amount, percent, fixed)
  local pct  = tonumber(percent) or 0
  local fix  = tonumber(fixed)   or 0
  local fee  = math.floor((H.amount(amount) * pct) / 100) + fix
  if fee < 0 then return 0 end
  return fee
end

-- Detecta tipo de identificador de transferencia.
-- char_id puro (numero), registration (regex DDDDLL ou 6 chars), phone (DDD-DDDD)
function H.detect_target_kind(raw)
  if type(raw) ~= 'string' or raw == '' then
    if type(raw) == 'number' then return 'char_id' end
    return nil
  end
  local clean = raw:gsub('%s+', '')
  -- char_id pure numeric
  if clean:match('^%d+$') then return 'char_id', tonumber(clean) end
  -- phone: contains hyphen
  if clean:find('-', 1, true) then return 'phone', clean end
  -- registration: alphanumeric mixed
  return 'registration', clean
end

-- Pretty-print kind de transacao para UI
local KIND_LABELS = {
  deposit        = 'Deposito',
  withdraw       = 'Saque',
  atm_withdraw   = 'Saque ATM',
  atm_deposit    = 'Deposito ATM',
  transfer_out   = 'Transferencia enviada',
  transfer_in    = 'Transferencia recebida',
  give           = 'Doacao em mao',
  payment        = 'Pagamento',
  admin_set      = 'Ajuste admin',
  admin_give     = 'Bonificacao admin',
  admin_take     = 'Penalidade admin',
  death_loss     = 'Perda por morte',
  initial        = 'Saldo inicial',
}
function H.kind_label(kind)
  return KIND_LABELS[tostring(kind or '')] or tostring(kind or '?')
end

-- Constantes de origem/destino de saldo
H.ACCOUNT = { WALLET = 'wallet', BANK = 'bank', NONE = 'none' }

-- Constantes de kind canonicos (server usa, NUI exibe via kind_label)
H.KIND = {
  DEPOSIT      = 'deposit',
  WITHDRAW     = 'withdraw',
  ATM_WITHDRAW = 'atm_withdraw',
  ATM_DEPOSIT  = 'atm_deposit',
  TRANSFER_OUT = 'transfer_out',
  TRANSFER_IN  = 'transfer_in',
  GIVE         = 'give',
  PAYMENT      = 'payment',
  ADMIN_SET    = 'admin_set',
  ADMIN_GIVE   = 'admin_give',
  ADMIN_TAKE   = 'admin_take',
  DEATH_LOSS   = 'death_loss',
  INITIAL      = 'initial',
}
