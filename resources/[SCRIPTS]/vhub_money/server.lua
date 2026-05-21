-- vhub_money/server.lua
-- Carteira e banco do personagem — servidor autoritativo.
-- user.data.wallet / user.data.bank: salvos pelo autosave do vHub (ref viva).
-- O cliente NUNCA altera valores financeiros.

local _sessions = {}   -- src → live user ref

-- ── Configuração ──────────────────────────────────────────────────────────────

local CFG = {
  carteira_inicial          = 150,
  banco_inicial             = 1000,
  perder_carteira_ao_morrer = true,
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getCarteira(user)
  return math.max(0, math.floor(tonumber(user.data.wallet) or 0))
end

local function getBanco(user)
  return math.max(0, math.floor(tonumber(user.data.bank) or 0))
end

-- ── Sessões (referências vivas) ───────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  _sessions[user.source] = user
  if user.data.wallet == nil then user.data.wallet = CFG.carteira_inicial end
  if user.data.bank   == nil then user.data.bank   = CFG.banco_inicial    end
end)

AddEventHandler("vHub:playerSpawn", function(user)
  _sessions[user.source] = user
  TriggerClientEvent("vhub_money:hud", user.source,
    { carteira = getCarteira(user), banco = getBanco(user) })
end)

AddEventHandler("playerDropped", function()
  _sessions[source] = nil
end)

local function getUser(src)
  return _sessions[tonumber(src)]
end

local function setCarteira(user, valor)
  valor = math.max(0, math.floor(tonumber(valor) or 0))
  user.data.wallet = valor
  TriggerClientEvent("vhub_money:hud", user.source,
    { carteira = valor, banco = getBanco(user) })
end

local function setBanco(user, valor)
  valor = math.max(0, math.floor(tonumber(valor) or 0))
  user.data.bank = valor
  TriggerClientEvent("vhub_money:hud", user.source,
    { carteira = getCarteira(user), banco = valor })
end

-- dry=true → verifica apenas, não modifica
local function tryPayment(user, valor, dry)
  valor = math.floor(tonumber(valor) or 0)
  if valor < 0 then return false end
  if getCarteira(user) < valor then return false end
  if not dry then setCarteira(user, getCarteira(user) - valor) end
  return true
end

-- ── Eventos vHub ─────────────────────────────────────────────────────────────

AddEventHandler("vHub:playerDeath", function(user)
  if not user then return end
  if CFG.perder_carteira_ao_morrer then setCarteira(user, 0) end
end)

-- ── Net events ────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_money:give")
AddEventHandler("vhub_money:give", function(target_src, valor)
  local src   = source
  local user  = getUser(src)
  local tuser = getUser(tonumber(target_src))
  if not user or not tuser then return end

  valor = math.floor(math.abs(tonumber(valor) or 0))
  if valor <= 0 then return end

  if tryPayment(user, valor) then
    setCarteira(tuser, getCarteira(tuser) + valor)
    TriggerClientEvent("vhub_money:notify", src,
      ("Você deu R$ %d para %s"):format(valor, tuser.name or "?"))
    TriggerClientEvent("vhub_money:notify", target_src,
      ("Você recebeu R$ %d de %s"):format(valor, user.name or "?"))
  else
    TriggerClientEvent("vhub_money:notify", src, "Dinheiro insuficiente.")
  end
end)

RegisterNetEvent("vhub_money:withdraw")
AddEventHandler("vhub_money:withdraw", function(valor)
  local src  = source
  local user = getUser(src)
  if not user then return end
  valor = math.floor(math.abs(tonumber(valor) or 0))
  if valor <= 0 then return end
  local saldo = getBanco(user)
  if saldo >= valor then
    setBanco(user,    saldo - valor)
    setCarteira(user, getCarteira(user) + valor)
    TriggerClientEvent("vhub_money:notify", src,
      ("Sacou R$ %d do banco."):format(valor))
  else
    TriggerClientEvent("vhub_money:notify", src, "Saldo insuficiente no banco.")
  end
end)

RegisterNetEvent("vhub_money:deposit")
AddEventHandler("vhub_money:deposit", function(valor)
  local src  = source
  local user = getUser(src)
  if not user then return end
  valor = math.floor(math.abs(tonumber(valor) or 0))
  if valor <= 0 then return end
  if tryPayment(user, valor) then
    setBanco(user, getBanco(user) + valor)
    TriggerClientEvent("vhub_money:notify", src,
      ("Depositou R$ %d no banco."):format(valor))
  else
    TriggerClientEvent("vhub_money:notify", src, "Dinheiro insuficiente na carteira.")
  end
end)

-- ── Exports públicos ──────────────────────────────────────────────────────────

exports("getWallet", function(src)
  local u = getUser(src); return u and getCarteira(u) or 0
end)

exports("getBank", function(src)
  local u = getUser(src); return u and getBanco(u) or 0
end)

exports("giveWallet", function(src, valor)
  local u = getUser(src); if not u then return false end
  setCarteira(u, getCarteira(u) + math.abs(math.floor(tonumber(valor) or 0)))
  return true
end)

exports("giveBank", function(src, valor)
  local u = getUser(src); if not u then return false end
  setBanco(u, getBanco(u) + math.abs(math.floor(tonumber(valor) or 0)))
  return true
end)

exports("tryPayment", function(src, valor, dry)
  local u = getUser(src); return u and tryPayment(u, valor, dry) or false
end)

exports("tryWithdraw", function(src, valor, dry)
  local u = getUser(src); if not u then return false end
  valor = math.floor(tonumber(valor) or 0)
  if valor < 0 or getBanco(u) < valor then return false end
  if not dry then
    setBanco(u,    getBanco(u) - valor)
    setCarteira(u, getCarteira(u) + valor)
  end
  return true
end)

exports("tryDeposit", function(src, valor, dry)
  local u = getUser(src); if not u then return false end
  valor = math.floor(math.abs(tonumber(valor) or 0))
  if getCarteira(u) < valor then return false end
  if not dry then
    setCarteira(u, getCarteira(u) - valor)
    setBanco(u, getBanco(u) + valor)
  end
  return true
end)

exports("tryFullPayment", function(src, valor, dry)
  local u = getUser(src); if not u then return false end
  valor = math.floor(tonumber(valor) or 0)
  if valor < 0 then return false end
  local cart  = getCarteira(u)
  local banco = getBanco(u)
  if cart + banco < valor then return false end
  if not dry then
    if cart >= valor then
      setCarteira(u, cart - valor)
    else
      setCarteira(u, 0)
      setBanco(u, banco - (valor - cart))
    end
  end
  return true
end)

exports("setWallet", function(src, valor)
  local u = getUser(src); if not u then return false end
  setCarteira(u, valor); return true
end)

exports("setBank", function(src, valor)
  local u = getUser(src); if not u then return false end
  setBanco(u, valor); return true
end)
