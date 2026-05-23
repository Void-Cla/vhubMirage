-- server/atm.lua — vhub_money (Fleeca Camell)
-- ATM-specific: cooldown por char e limites por operacao.
-- Bank fisico (agencia) usa nucleo direto sem cooldown nem limite (configuravel em Cfg.BANK).

VHubMoneyATM = {}
local A = VHubMoneyATM
local Cfg  = VHubMoneyCfg
local H    = VHubMoneyH
local Core = VHubMoneyCore

-- Cooldown por char_id (ms timestamp do proximo uso permitido)
A._cooldown = {}   -- [char_id] = ms

local function ms() return GetGameTimer() end

-- Verifica cooldown; retorna (ok, segundos_restantes)
local function check_cooldown(char_id, owner)
  if owner then return true, 0 end   -- char_id 1 bypass
  local until_ms = A._cooldown[char_id]
  if not until_ms then return true, 0 end
  local diff = until_ms - ms()
  if diff <= 0 then return true, 0 end
  return false, math.ceil(diff / 1000)
end

local function set_cooldown(char_id)
  local secs = tonumber(Cfg.ATM.COOLDOWN_SEC) or 30
  if secs <= 0 then return end
  A._cooldown[char_id] = ms() + (secs * 1000)
end

-- ATM: saca (banco → carteira) com limite e cooldown
function A.atm_withdraw(src, amount)
  local entry = Core.by_src(tonumber(src) or 0)
  if not entry then return false, 'sem_sessao' end

  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  local cap = tonumber(Cfg.ATM.WITHDRAW_MAX) or 0
  if cap > 0 and n > cap and not entry.owner then
    return false, ('limite_excedido:%d'):format(cap)
  end

  local ok_cd, rem = check_cooldown(entry.char_id, entry.owner)
  if not ok_cd then return false, ('cooldown:%d'):format(rem) end

  local ok, err = Core.try_withdraw(src, n, false, 'atm', H.KIND.ATM_WITHDRAW)
  if not ok then return false, err end

  set_cooldown(entry.char_id)
  return true, { amount = n, wallet = entry.wallet, bank = entry.bank }
end

-- ATM: deposita (carteira → banco) com limite e cooldown
function A.atm_deposit(src, amount)
  local entry = Core.by_src(tonumber(src) or 0)
  if not entry then return false, 'sem_sessao' end

  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  local cap = tonumber(Cfg.ATM.DEPOSIT_MAX) or 0
  if cap > 0 and n > cap and not entry.owner then
    return false, ('limite_excedido:%d'):format(cap)
  end

  local ok_cd, rem = check_cooldown(entry.char_id, entry.owner)
  if not ok_cd then return false, ('cooldown:%d'):format(rem) end

  local ok, err = Core.try_deposit(src, n, false, 'atm', H.KIND.ATM_DEPOSIT)
  if not ok then return false, err end

  set_cooldown(entry.char_id)
  return true, { amount = n, wallet = entry.wallet, bank = entry.bank }
end

-- BANK fisico: saca sem cooldown (limites do Cfg.BANK)
function A.bank_withdraw(src, amount)
  local entry = Core.by_src(tonumber(src) or 0)
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  local cap = tonumber(Cfg.BANK.WITHDRAW_MAX) or 0
  if cap > 0 and n > cap and not entry.owner then
    return false, ('limite_excedido:%d'):format(cap)
  end
  return Core.try_withdraw(src, n, false, 'bank_counter')
end

function A.bank_deposit(src, amount)
  local entry = Core.by_src(tonumber(src) or 0)
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  local cap = tonumber(Cfg.BANK.DEPOSIT_MAX) or 0
  if cap > 0 and n > cap and not entry.owner then
    return false, ('limite_excedido:%d'):format(cap)
  end
  return Core.try_deposit(src, n, false, 'bank_counter')
end

-- GC do cooldown em playerDropped
function A.clear_cooldown(char_id)
  A._cooldown[char_id] = nil
end
