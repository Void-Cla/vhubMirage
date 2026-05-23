-- server/init.lua — vhub_money (Fleeca Camell)
-- Bootstrap, lifecycle de personagem, autosave periodico, NUI net events.

local Cfg  = VHubMoneyCfg
local H    = VHubMoneyH
local Core = VHubMoneyCore
local SQL  = VHubMoneySQL
local A    = VHubMoneyATM
local T    = VHubMoneyTransfer

-- ── Boot ────────────────────────────────────────────────────────────────────

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end

  Citizen.CreateThread(function()
    -- Aguarda vhub core
    local vh = nil
    for _ = 1, 60 do
      local ok, ref = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(ref) == 'table' and ref.Auth then vh = ref; break end
      Citizen.Wait(250)
    end
    if not vh then
      print('[vhub_money][ERRO] vhub indisponivel apos 15s — abortando init.')
      return
    end
    Core.set_vhub(vh)

    -- Aplica schema
    local ok, err = SQL.apply_schema()
    if not ok then
      print('[vhub_money][ERRO] falha ao aplicar schema: ' .. tostring(err))
      return
    end

    -- Re-popula cache de sessoes ativas (restart hot)
    if vh.Auth and vh.Auth._sessions then
      for _, user in pairs(vh.Auth._sessions) do
        if user.char_id then
          Core.load_entry(user.source, user.char_id)
        end
      end
    end

    Core.mark_ready()
    print('[vhub_money] Fleeca Camell pronto.')
  end)
end)

-- ── Lifecycle de personagem ─────────────────────────────────────────────────

AddEventHandler('vHub:characterLoad', function(user)
  if not Core.is_ready() then
    -- Retry curto se o boot ainda nao terminou
    Citizen.SetTimeout(1000, function()
      if Core.is_ready() and user and user.char_id then
        Core.load_entry(user.source, user.char_id)
      end
    end)
    return
  end
  if not user or not user.char_id then return end
  Citizen.CreateThread(function()
    Core.load_entry(user.source, user.char_id)
  end)
end)

-- Re-sync state bag ao spawnar
AddEventHandler('vHub:playerSpawn', function(user)
  if not user or not user.source then return end
  local entry = Core.by_src(user.source)
  if entry then Core.sync_state_bag(entry) end
end)

-- Morte: perde carteira (config)
AddEventHandler('vHub:playerDeath', function(user)
  if not user or not user.source then return end
  Core.on_death(user.source)
end)

-- Drop: flush + GC
AddEventHandler('playerDropped', function()
  local src = source
  local entry = Core.by_src(src)
  if entry then
    A.clear_cooldown(entry.char_id)
    Core.unregister_src(src)
  end
end)

-- ── Autosave (throttle por intervalo) ───────────────────────────────────────

Citizen.CreateThread(function()
  local interval = tonumber(Cfg.SAVE_INTERVAL_MS) or 5000
  if interval < 1000 then interval = 1000 end
  while true do
    Citizen.Wait(interval)
    if Core.is_ready() then
      Core.flush_all()
    end
  end
end)

-- Shutdown emergencia: flush sincrono
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  Core.flush_all()
end)

-- ── Net events do NUI ───────────────────────────────────────────────────────

-- O cliente envia { mode = 'atm'|'bank', station_id = ?, station_pos = vec3 }.
-- O servidor revalida: o jogador esta realmente perto de uma estacao do tipo?
local function near_bank(src)
  local ped = GetPlayerPed(src)
  local px, py, pz = table.unpack(GetEntityCoords(ped))
  for _, b in ipairs(VHubMoneyBanks) do
    local dx, dy, dz = px - b.x, py - b.y, pz - b.z
    if (dx * dx + dy * dy + dz * dz) <= (4.0 * 4.0) then return b end
  end
  return nil
end

local function near_atm(src)
  local ped = GetPlayerPed(src)
  local px, py, pz = table.unpack(GetEntityCoords(ped))
  for _, a in ipairs(VHubMoneyATMs) do
    local dx, dy, dz = px - a[1], py - a[2], pz - a[3]
    if (dx * dx + dy * dy + dz * dz) <= (3.0 * 3.0) then return a end
  end
  return nil
end

-- Abre o painel (cliente pediu)
RegisterNetEvent('vhub_money:nui:open', function(payload)
  local src = source
  local entry = Core.by_src(src)
  if not entry then return end

  local mode = (type(payload) == 'table' and payload.mode) or 'atm'
  local station = nil
  if mode == 'bank' then
    station = near_bank(src)
    if not station then return end   -- nao esta em banco
  else
    station = near_atm(src)
    if not station then return end   -- nao esta em ATM
    mode = 'atm'
    station = { id = 'atm', label = 'ATM', x = station[1], y = station[2], z = station[3] }
  end

  local txs = SQL.tx_fetch(entry.char_id, 30)
  TriggerClientEvent('vhub_money:nui:opened', src, {
    mode    = mode,
    station = station,
    wallet  = entry.wallet,
    bank    = entry.bank,
    owner   = entry.owner == true,
    txs     = txs,
    cfg     = {
      brand_name   = Cfg.BRAND_NAME,
      brand_tag    = Cfg.BRAND_TAG,
      brand_slogan = Cfg.BRAND_SLOGAN,
      atm_max_w    = Cfg.ATM.WITHDRAW_MAX,
      atm_max_d    = Cfg.ATM.DEPOSIT_MAX,
      atm_cooldown = Cfg.ATM.COOLDOWN_SEC,
      bank_max_w   = Cfg.BANK.WITHDRAW_MAX,
      bank_max_d   = Cfg.BANK.DEPOSIT_MAX,
      transfer_min = Cfg.TRANSFER.MIN_AMOUNT,
      transfer_max = Cfg.TRANSFER.MAX_AMOUNT,
      fee_percent  = Cfg.TRANSFER.FEE_PERCENT,
      fee_fixed    = Cfg.TRANSFER.FEE_FIXED,
    },
  })
end)

-- Operacoes (server-side: revalida proximidade + executa)
local function op_response(src, ok, payload)
  TriggerClientEvent('vhub_money:nui:result', src, { ok = ok, data = payload })
  local entry = Core.by_src(src)
  if entry then
    local txs = SQL.tx_fetch(entry.char_id, 30)
    TriggerClientEvent('vhub_money:nui:refresh', src, {
      wallet = entry.wallet,
      bank   = entry.bank,
      txs    = txs,
    })
  end
end

RegisterNetEvent('vhub_money:nui:withdraw', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local mode = tostring(payload.mode or 'atm')
  -- Revalida proximidade
  if mode == 'bank' and not near_bank(src) then return end
  if mode == 'atm'  and not near_atm(src)  then return end

  local ok, data_or_err
  if mode == 'bank' then ok, data_or_err = A.bank_withdraw(src, payload.amount)
  else                   ok, data_or_err = A.atm_withdraw(src, payload.amount) end
  op_response(src, ok, ok and data_or_err or { err = data_or_err })
end)

RegisterNetEvent('vhub_money:nui:deposit', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local mode = tostring(payload.mode or 'atm')
  if mode == 'bank' and not near_bank(src) then return end
  if mode == 'atm'  and not near_atm(src)  then return end

  local ok, data_or_err
  if mode == 'bank' then ok, data_or_err = A.bank_deposit(src, payload.amount)
  else                   ok, data_or_err = A.atm_deposit(src, payload.amount) end
  op_response(src, ok, ok and data_or_err or { err = data_or_err })
end)

RegisterNetEvent('vhub_money:nui:transfer', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  -- Transferencia requer estar em banco fisico (mais seguranca / brand)
  if not near_bank(src) then return end

  local ok, data_or_err = T.try_transfer(src, payload.target, payload.amount, payload.reason)
  op_response(src, ok, ok and data_or_err or { err = data_or_err })
end)

-- ── Comandos ────────────────────────────────────────────────────────────────

-- /pagar <id_destino_numerico> <valor>
RegisterCommand(Cfg.CMD_PAY, function(src, args)
  if src <= 0 then return end
  local target_src = tonumber(args[1])
  local valor      = tonumber(args[2])
  if not target_src or not valor or valor <= 0 then
    TriggerClientEvent('vhub_money:notify', src,
      ('Uso: /%s <id_destino> <valor>'):format(Cfg.CMD_PAY), 'info')
    return
  end
  local ok, data_or_err = T.try_give(src, target_src, valor, 'cmd_pagar')
  if not ok then
    TriggerClientEvent('vhub_money:notify', src,
      'Falha: ' .. tostring(data_or_err), 'error')
    return
  end
  TriggerClientEvent('vhub_money:notify', src,
    ('Voce pagou %s para ID %d.'):format(H.fmt(data_or_err.amount), target_src), 'success')
  TriggerClientEvent('vhub_money:notify', target_src,
    ('Voce recebeu %s do ID %d.'):format(H.fmt(data_or_err.amount), src), 'success')
end, false)

-- /dar (alias de /pagar — entrega em mao)
RegisterCommand(Cfg.CMD_GIVE, function(src, args)
  if src <= 0 then return end
  ExecuteCommand(('%s %s %s'):format(Cfg.CMD_PAY, args[1] or '', args[2] or ''))
end, false)

-- /saldo — toast com saldo
RegisterCommand(Cfg.CMD_BALANCE, function(src)
  if src <= 0 then return end
  local entry = Core.by_src(src)
  if not entry then return end
  TriggerClientEvent('vhub_money:notify', src,
    ('Carteira: %s | Banco: %s'):format(H.fmt(entry.wallet), H.fmt(entry.bank)), 'info')
end, false)

-- Console: vhub_money_status
RegisterCommand('vhub_money_status', function(src)
  if src ~= 0 then return end
  local total = 0
  for _ in pairs(Core._by_char) do total = total + 1 end
  print(('[vhub_money] sessions=%d loads=%d saves=%d txs=%d'):format(
    total, Core.metrics.loads, Core.metrics.saves, Core.metrics.transactions))
end, true)
