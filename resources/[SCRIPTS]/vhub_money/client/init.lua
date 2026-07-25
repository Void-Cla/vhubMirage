-- client/init.lua — vhub_money (Fleeca Camell)
-- HUD State Bag listener + notify helper + comandos basicos.

local Cfg = VHubMoneyCfg
local H   = VHubMoneyH

-- ── Estado local ────────────────────────────────────────────────────────────

local _wallet = 0
local _bank   = 0

local function emit_local()
  TriggerEvent('vhub_money:local_update', _wallet, _bank)
end

local function update_local(value)
  if type(value) ~= 'table' then return end
  _wallet = tonumber(value.wallet) or 0
  _bank = tonumber(value.bank) or 0
  emit_local()
end

-- ── State Bag: HUD live (sem polling, sem rede custom) ──────────────────────

AddStateBagChangeHandler('vhub_money',
  ('player:%d'):format(GetPlayerServerId(PlayerId())),
  function(_bag, _key, value)
    update_local(value)
  end)

-- Lê uma vez o snapshot já replicado antes do registro do handler.
update_local(LocalPlayer.state.vhub_money)

-- ── Notify (toast nativo do GTA) ────────────────────────────────────────────

RegisterNetEvent('vhub_money:notify', function(msg, _kind)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg or ''))
  EndTextCommandThefeedPostTicker(false, true)
end)

-- ── Comandos ────────────────────────────────────────────────────────────────

-- /saldo (servidor responde via vhub_money:notify, mas tambem mostra local rapido)
RegisterCommand(Cfg.CMD_BALANCE, function()
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(
    ('Carteira: %s  |  Banco: %s'):format(H.fmt(_wallet), H.fmt(_bank)))
  EndTextCommandThefeedPostTicker(false, true)
end, false)

-- ── API local (para outros resources client-side) ───────────────────────────

exports('getWalletLocal', function() return _wallet end)
exports('getBankLocal',   function() return _bank   end)
exports('getBalanceLocal', function() return _wallet, _bank, _wallet + _bank end)
