-- server/core.lua — vhub_money (Fleeca Camell)
-- Logica central: carteira/banco, get/set, try*, autosave throttle.
-- VRAM-first: estado em _cache[char_id]. SQL grava de tempos em tempos (dirty flag).

VHubMoneyCore = {}
local Core = VHubMoneyCore
local Cfg  = VHubMoneyCfg
local H    = VHubMoneyH
local SQL  = VHubMoneySQL

local _vHub  = nil
local _ready = false

-- VRAM cache (source of truth runtime)
-- _by_char[char_id] = {
--   src, char_id, wallet, bank, total_in, total_out,
--   dirty, owner, last_save_ms
-- }
-- _by_src[src] = entry (mesmo objeto)
Core._by_char = {}
Core._by_src  = {}
Core._loading = {}   -- [char_id]=true durante load_entry (guard p/ crédito offline concorrente)
Core.metrics  = { loads = 0, saves = 0, save_skipped = 0, transactions = 0 }

local function ms() return GetGameTimer() end

-- ── Boot helpers ────────────────────────────────────────────────────────────

function Core.set_vhub(vh)   _vHub = vh end
function Core.get_vhub()     return _vHub end
function Core.is_ready()     return _ready end
function Core.mark_ready()   _ready = true end

-- ── Identity helpers ────────────────────────────────────────────────────────

function Core.char_id_of(src)
  if not _vHub or not _vHub.Auth then return nil end
  local user = _vHub.Auth:getUser(tonumber(src) or 0)
  return user and user.char_id or nil
end

function Core.src_of_char(char_id)
  local e = Core._by_char[char_id]
  return e and e.src or nil
end

-- ── Cache lifecycle ─────────────────────────────────────────────────────────

local function new_entry(src, char_id, row)
  return {
    src          = src,
    char_id      = char_id,
    wallet       = tonumber(row.wallet)    or 0,
    bank         = tonumber(row.bank)      or 0,
    total_in     = tonumber(row.total_in)  or 0,
    total_out    = tonumber(row.total_out) or 0,
    owner        = (char_id == Cfg.OWNER_CHAR_ID),
    dirty        = false,
    last_save_ms = ms(),
  }
end

-- Carrega conta do banco e popula VRAM
function Core.load_entry(src, char_id)
  if not char_id or char_id <= 0 then return nil end

  Core._loading[char_id] = true   -- guard: cobre a janela SELECT→atribuição (race de crédito offline)
  local row = SQL.load_account(char_id, Cfg.WALLET_INITIAL, Cfg.BANK_INITIAL)
  local entry = new_entry(src, char_id, row)
  Core._by_char[char_id] = entry
  Core._by_src[src]      = entry
  Core._loading[char_id] = nil
  Core.metrics.loads = Core.metrics.loads + 1

  -- Se for nova conta, registra a transacao de saldo inicial
  if row.new then
    SQL.tx_insert({
      actor_char_id  = 0,
      target_char_id = char_id,
      kind           = H.KIND.INITIAL,
      amount         = (Cfg.WALLET_INITIAL or 0) + (Cfg.BANK_INITIAL or 0),
      source_account = H.ACCOUNT.NONE,
      target_account = H.ACCOUNT.BANK,
      balance_wallet = entry.wallet,
      balance_bank   = entry.bank,
      reason         = 'first_load',
    })
  end

  Core.sync_state_bag(entry)
  return entry
end

function Core.unregister_src(src)
  local entry = Core._by_src[src]
  if not entry then return end
  -- Persiste se tiver mudancas pendentes
  if entry.dirty and Cfg.SAVE_ON_DROP then
    Core.flush_one(entry)
  end
  Core._by_src[src] = nil
  if entry.char_id then Core._by_char[entry.char_id] = nil end
end

function Core.by_src(src)   return Core._by_src[src] end
function Core.by_char(cid)  return Core._by_char[cid] end

-- ── State Bag (HUD live) ────────────────────────────────────────────────────

-- Servidor escreve; cliente le. Replicado por sync nativo (sem rede custom).
function Core.sync_state_bag(entry)
  if not entry or not entry.src or entry.src <= 0 then return end
  Player(entry.src).state:set('vhub_money', {
    wallet = entry.wallet,
    bank   = entry.bank,
  }, true)
end

-- ── Mutacao com dirty flag ──────────────────────────────────────────────────

-- Ajusta saldo e marca dirty (autosave grava depois). Recalcula totais agregados.
local function apply_mutation(entry, delta_wallet, delta_bank)
  if not entry then return false end

  local new_wallet = entry.wallet + (delta_wallet or 0)
  local new_bank   = entry.bank   + (delta_bank   or 0)

  if new_wallet < 0 or new_bank < 0 then return false end   -- nunca permite negativo

  -- Total in/out agregado (apenas valores positivos lidos como ganho/perda real)
  if delta_wallet and delta_wallet > 0 then entry.total_in  = entry.total_in  + delta_wallet end
  if delta_bank   and delta_bank   > 0 then entry.total_in  = entry.total_in  + delta_bank   end
  if delta_wallet and delta_wallet < 0 then entry.total_out = entry.total_out + math.abs(delta_wallet) end
  if delta_bank   and delta_bank   < 0 then entry.total_out = entry.total_out + math.abs(delta_bank) end

  entry.wallet = new_wallet
  entry.bank   = new_bank
  entry.dirty  = true

  Core.sync_state_bag(entry)
  return true
end

Core.apply_mutation = apply_mutation

-- ── API publica server-side (usada por outros modulos do mesmo resource) ────

function Core.get_wallet(src_or_char)
  local n = tonumber(src_or_char) or 0
  local e = Core._by_src[n] or Core._by_char[n]
  return e and e.wallet or 0
end

function Core.get_bank(src_or_char)
  local n = tonumber(src_or_char) or 0
  local e = Core._by_src[n] or Core._by_char[n]
  return e and e.bank or 0
end

function Core.get_balance(src_or_char)
  local n = tonumber(src_or_char) or 0
  local e = Core._by_src[n] or Core._by_char[n]
  if not e then return 0, 0, 0 end
  return e.wallet, e.bank, e.wallet + e.bank
end

-- Tenta pagar com carteira. dry=true → so testa.
function Core.try_payment(src, amount, dry, reason)
  local entry = Core._by_src[tonumber(src) or 0]
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  if entry.wallet < n then return false, 'saldo_insuficiente' end
  if dry then return true end

  apply_mutation(entry, -n, 0)
  SQL.tx_insert({
    actor_char_id  = entry.char_id,
    target_char_id = entry.char_id,
    kind           = H.KIND.PAYMENT,
    amount         = n,
    source_account = H.ACCOUNT.WALLET,
    target_account = H.ACCOUNT.NONE,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = tostring(reason or 'payment'),
  })
  Core.metrics.transactions = Core.metrics.transactions + 1
  return true
end

-- Saca do banco para a carteira
function Core.try_withdraw(src, amount, dry, reason, kind)
  local entry = Core._by_src[tonumber(src) or 0]
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  if entry.bank < n then return false, 'saldo_insuficiente' end
  if dry then return true end

  apply_mutation(entry, n, -n)   -- ganha na carteira, perde no banco (sem dupla contagem em totais)
  -- Ajuste: nao queremos contar como "in" porque o dinheiro ja era do char
  entry.total_in  = entry.total_in  - n
  entry.total_out = entry.total_out - n

  SQL.tx_insert({
    actor_char_id  = entry.char_id,
    target_char_id = entry.char_id,
    kind           = kind or H.KIND.WITHDRAW,
    amount         = n,
    source_account = H.ACCOUNT.BANK,
    target_account = H.ACCOUNT.WALLET,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = tostring(reason or 'withdraw'),
  })
  Core.metrics.transactions = Core.metrics.transactions + 1
  return true
end

-- Deposita carteira → banco
function Core.try_deposit(src, amount, dry, reason, kind)
  local entry = Core._by_src[tonumber(src) or 0]
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  if entry.wallet < n then return false, 'saldo_insuficiente' end
  if dry then return true end

  apply_mutation(entry, -n, n)
  entry.total_in  = entry.total_in  - n   -- compensa apply_mutation que contou n no banco
  entry.total_out = entry.total_out - n

  SQL.tx_insert({
    actor_char_id  = entry.char_id,
    target_char_id = entry.char_id,
    kind           = kind or H.KIND.DEPOSIT,
    amount         = n,
    source_account = H.ACCOUNT.WALLET,
    target_account = H.ACCOUNT.BANK,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = tostring(reason or 'deposit'),
  })
  Core.metrics.transactions = Core.metrics.transactions + 1
  return true
end

-- Pagamento full (carteira primeiro, completa do banco se faltar)
function Core.try_full_payment(src, amount, dry, reason)
  local entry = Core._by_src[tonumber(src) or 0]
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end
  if entry.wallet + entry.bank < n then return false, 'saldo_insuficiente' end
  if dry then return true end

  if entry.wallet >= n then
    apply_mutation(entry, -n, 0)
  else
    local from_bank = n - entry.wallet
    apply_mutation(entry, -entry.wallet, -from_bank)
  end
  SQL.tx_insert({
    actor_char_id  = entry.char_id,
    target_char_id = entry.char_id,
    kind           = H.KIND.PAYMENT,
    amount         = n,
    source_account = H.ACCOUNT.WALLET,   -- log conceitual; saiu de wallet+bank
    target_account = H.ACCOUNT.NONE,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = tostring(reason or 'full_payment'),
  })
  Core.metrics.transactions = Core.metrics.transactions + 1
  return true
end

-- TRUSTED: concede dinheiro (admin/job/payout)
function Core.give_wallet(src, amount, reason, actor_char_id, kind)
  local entry = Core._by_src[tonumber(src) or 0]
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end

  apply_mutation(entry, n, 0)
  SQL.tx_insert({
    actor_char_id  = tonumber(actor_char_id) or 0,
    target_char_id = entry.char_id,
    kind           = kind or H.KIND.ADMIN_GIVE,
    amount         = n,
    source_account = H.ACCOUNT.NONE,
    target_account = H.ACCOUNT.WALLET,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = tostring(reason or 'admin_give'),
  })
  Core.metrics.transactions = Core.metrics.transactions + 1
  return true
end

function Core.give_bank(src, amount, reason, actor_char_id, kind)
  local entry = Core._by_src[tonumber(src) or 0]
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  if n <= 0 then return false, 'valor_invalido' end

  apply_mutation(entry, 0, n)
  SQL.tx_insert({
    actor_char_id  = tonumber(actor_char_id) or 0,
    target_char_id = entry.char_id,
    kind           = kind or H.KIND.ADMIN_GIVE,
    amount         = n,
    source_account = H.ACCOUNT.NONE,
    target_account = H.ACCOUNT.BANK,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = tostring(reason or 'admin_give'),
  })
  Core.metrics.transactions = Core.metrics.transactions + 1
  return true
end

-- TRUSTED: credita o BANCO por char_id, ONLINE ou OFFLINE (payout/refund de leilao).
-- Online → crédito vivo (cache + HUD). Offline → incremento atômico no DB + auditoria.
-- Fecha a corrida de login: se o char entrou durante o incremento, recarrega a cache do DB.
function Core.give_bank_char(char_id, amount, reason)
  local cid = tonumber(char_id) or 0
  local n   = H.amount(amount)
  if cid <= 0 or n <= 0 then return false, 'arg_invalido' end

  local entry = Core._by_char[cid]
  if entry then
    return Core.give_bank(entry.src, n, reason, 0, H.KIND.ADMIN_GIVE)   -- online: crédito vivo
  end

  -- offline: incremento atômico no DB (não depende de cache)
  SQL.add_bank_offline(cid, n)
  SQL.tx_insert({
    actor_char_id = 0, target_char_id = cid, kind = H.KIND.ADMIN_GIVE, amount = n,
    source_account = H.ACCOUNT.NONE, target_account = H.ACCOUNT.BANK,
    balance_wallet = 0, balance_bank = 0, reason = tostring(reason or 'offline_credit'),
  })
  -- fecha a corrida de login: se um load está em andamento (guard _loading) espera concluir;
  -- depois, se o char ficou online, recarrega a cache do DB (que já contém o incremento) —
  -- senão a row stale do SELECT do login sobrescreveria o crédito no próximo flush.
  local tries = 0
  while Core._loading[cid] and tries < 50 do Citizen.Wait(10); tries = tries + 1 end
  local now = Core._by_char[cid]
  if now then
    local row = SQL.load_account(cid, Cfg.WALLET_INITIAL, Cfg.BANK_INITIAL)
    now.wallet, now.bank        = row.wallet, row.bank
    now.total_in, now.total_out = row.total_in, row.total_out   -- evita drift de métrica
    now.dirty = false
    Core.sync_state_bag(now)
  end
  return true
end

-- TRUSTED: set absoluto (admin set_wallet/set_bank)
function Core.set_wallet(src, amount, reason, actor_char_id)
  local entry = Core._by_src[tonumber(src) or 0]
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  local diff = n - entry.wallet
  apply_mutation(entry, diff, 0)
  -- Sem somar em total_in/out (set e ajuste, nao fluxo)
  if diff > 0 then entry.total_in  = entry.total_in  - diff end
  if diff < 0 then entry.total_out = entry.total_out - math.abs(diff) end
  SQL.tx_insert({
    actor_char_id  = tonumber(actor_char_id) or 0,
    target_char_id = entry.char_id,
    kind           = H.KIND.ADMIN_SET,
    amount         = math.abs(diff),
    source_account = H.ACCOUNT.NONE,
    target_account = H.ACCOUNT.WALLET,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = tostring(reason or 'admin_set'),
  })
  return true
end

function Core.set_bank(src, amount, reason, actor_char_id)
  local entry = Core._by_src[tonumber(src) or 0]
  if not entry then return false, 'sem_sessao' end
  local n = H.amount(amount)
  local diff = n - entry.bank
  apply_mutation(entry, 0, diff)
  if diff > 0 then entry.total_in  = entry.total_in  - diff end
  if diff < 0 then entry.total_out = entry.total_out - math.abs(diff) end
  SQL.tx_insert({
    actor_char_id  = tonumber(actor_char_id) or 0,
    target_char_id = entry.char_id,
    kind           = H.KIND.ADMIN_SET,
    amount         = math.abs(diff),
    source_account = H.ACCOUNT.NONE,
    target_account = H.ACCOUNT.BANK,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = tostring(reason or 'admin_set'),
  })
  return true
end

-- ── Autosave (throttle por dirty flag + intervalo) ──────────────────────────

-- Persiste UMA conta no banco. Usado em playerDropped e em intervalos.
function Core.flush_one(entry)
  if not entry or not entry.dirty then return false end
  SQL.save_account(entry.char_id, entry.wallet, entry.bank, entry.total_in, entry.total_out)
  entry.dirty = false
  entry.last_save_ms = ms()
  Core.metrics.saves = Core.metrics.saves + 1
  return true
end

-- Flush em batch (eficiente para autosave periodico de muitos chars)
function Core.flush_all()
  local rows = {}
  for _, entry in pairs(Core._by_char) do
    if entry.dirty then
      rows[#rows + 1] = {
        char_id   = entry.char_id,
        wallet    = entry.wallet,
        bank      = entry.bank,
        total_in  = entry.total_in,
        total_out = entry.total_out,
      }
    end
  end
  if #rows == 0 then
    Core.metrics.save_skipped = Core.metrics.save_skipped + 1
    return 0
  end
  SQL.save_accounts_batch(rows)
  for _, r in ipairs(rows) do
    local entry = Core._by_char[r.char_id]
    if entry then
      entry.dirty = false
      entry.last_save_ms = ms()
    end
  end
  Core.metrics.saves = Core.metrics.saves + 1
  return #rows
end

-- ── Death handler ───────────────────────────────────────────────────────────

function Core.on_death(src)
  if not Cfg.LOSE_WALLET_ON_DEATH then return end
  local entry = Core._by_src[src]
  if not entry or entry.wallet <= 0 then return end

  local lost = entry.wallet
  apply_mutation(entry, -lost, 0)
  SQL.tx_insert({
    actor_char_id  = 0,
    target_char_id = entry.char_id,
    kind           = H.KIND.DEATH_LOSS,
    amount         = lost,
    source_account = H.ACCOUNT.WALLET,
    target_account = H.ACCOUNT.NONE,
    balance_wallet = entry.wallet,
    balance_bank   = entry.bank,
    reason         = 'death',
  })
end
