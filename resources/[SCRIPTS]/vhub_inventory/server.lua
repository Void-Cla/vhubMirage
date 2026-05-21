-- vhub_inventory/server.lua
-- Inventário do personagem — servidor autoritativo.
-- user.data.inventory: { [fullid] = amount }
-- Modificações em user.data são salvas pelo autosave do vHub (referência viva via TriggerEvent).

local _sessions = {}   -- src → live user ref (vHub:characterLoad)

-- ── Configuração ──────────────────────────────────────────────────────────────

local CFG = {
  peso_maximo_padrao = 15.0,
  perder_ao_morrer   = true,

  itens = {
    ["repairkit"]    = { nome="Kit de Reparo",   desc="Repara veículo.",        peso=1.0, stack=1   },
    ["water_bottle"] = { nome="Garrafa d'Água",  desc="Reduz a sede.",          peso=0.5, stack=10  },
    ["sandwich"]     = { nome="Sanduíche",        desc="Reduz a fome.",         peso=0.3, stack=10  },
    ["bandage"]      = { nome="Bandagem",         desc="Restaura 10 HP.",       peso=0.2, stack=20  },
    ["medkit"]       = { nome="Kit Médico",       desc="Restaura 50 HP.",       peso=1.5, stack=5   },
    ["handcuffs"]    = { nome="Algemas",          desc="Prende suspeitos.",     peso=0.3, stack=3   },
    ["lockpick"]     = { nome="Gazua",            desc="Abre travas simples.",  peso=0.1, stack=5   },
    ["phone"]        = { nome="Celular",          desc="Comunicação.",          peso=0.2, stack=1   },
    ["radio"]        = { nome="Rádio",            desc="Comunicação policial.", peso=0.5, stack=1   },
    ["id_card"]      = { nome="Carteira de ID",   desc="Documento de ID.",      peso=0.1, stack=1   },
    ["veh_key"]      = { nome="Chave de Veículo", desc="Chave para um veículo.",peso=0.1, stack=1   },
  },

  -- Itens não perdidos na morte
  itens_preservados = { "id_card", "veh_key" },
  callbacks_uso     = {},
}

-- ── Sessões (referências vivas) ───────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  _sessions[user.source] = user
  if not user.data.inventory then user.data.inventory = {} end
end)

AddEventHandler("vHub:playerSpawn", function(user)
  _sessions[user.source] = user
  TriggerClientEvent("vhub_inventory:update", user.source, user.data.inventory or {})
end)

AddEventHandler("playerDropped", function()
  _sessions[source] = nil
end)

local function getUser(src)
  return _sessions[tonumber(src)]
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getItemDef(fullid)
  return CFG.itens[fullid:match("^([^|]+)")]
end

local function getItemNome(fullid)
  local def  = getItemDef(fullid)
  local args = fullid:match("|(.+)$")
  if not def then return fullid end
  return args and (def.nome .. " [" .. args .. "]") or def.nome
end

local function getBag(user)
  if not user.data.inventory then user.data.inventory = {} end
  return user.data.inventory
end

local function calcPeso(bag)
  local w = 0
  for fid, n in pairs(bag) do
    local def = getItemDef(fid)
    w = w + (def and def.peso or 0) * n
  end
  return w
end

-- ── darItem / tirarItem ───────────────────────────────────────────────────────
-- dry=true  → verifica apenas, não modifica
-- silent=true → sem notificação (só aplicável com dry=false)

local function darItem(user, fullid, amount, dry, silent)
  amount = math.floor(tonumber(amount) or 1)
  if amount <= 0 then return false end
  local def = getItemDef(fullid)
  if not def then return false end
  local bag = getBag(user)
  if calcPeso(bag) + def.peso * amount > CFG.peso_maximo_padrao then
    if not dry and not silent then
      TriggerClientEvent("vhub_inventory:notify", user.source,
        ("Inventário cheio! Máx: %.1f kg"):format(CFG.peso_maximo_padrao))
    end
    return false
  end
  if not dry then
    bag[fullid] = (bag[fullid] or 0) + amount
    if not silent then
      TriggerClientEvent("vhub_inventory:notify", user.source,
        ("+ %dx %s"):format(amount, getItemNome(fullid)))
    end
    TriggerClientEvent("vhub_inventory:update", user.source, bag)
  end
  return true
end

local function tirarItem(user, fullid, amount, dry, silent)
  amount = math.floor(tonumber(amount) or 1)
  if amount <= 0 then return false end
  local bag = getBag(user)
  if (bag[fullid] or 0) < amount then
    if not dry and not silent then
      TriggerClientEvent("vhub_inventory:notify", user.source,
        ("Você não tem %dx %s"):format(amount, getItemNome(fullid)))
    end
    return false
  end
  if not dry then
    local n = (bag[fullid] or 0) - amount
    bag[fullid] = n > 0 and n or nil
    if not silent then
      TriggerClientEvent("vhub_inventory:notify", user.source,
        ("- %dx %s"):format(amount, getItemNome(fullid)))
    end
    TriggerClientEvent("vhub_inventory:update", user.source, bag)
  end
  return true
end

local function temItem(user, fullid, amount)
  return (getBag(user)[fullid] or 0) >= (amount or 1)
end

-- ── Baús (in-memory; redefina via oxmysql para persistência) ─────────────────

local _baus = {}

local function bau(id)
  if not _baus[id] then _baus[id] = {} end
  return _baus[id]
end

-- ── Exports ───────────────────────────────────────────────────────────────────

exports("giveItem", function(src, fullid, amount)
  local u = getUser(src); return u and darItem(u, fullid, amount) or false
end)

exports("takeItem", function(src, fullid, amount)
  local u = getUser(src); return u and tirarItem(u, fullid, amount) or false
end)

exports("hasItem", function(src, fullid, amount)
  local u = getUser(src); return u and temItem(u, fullid, amount) or false
end)

exports("getItemAmount", function(src, fullid)
  local u = getUser(src); return u and (getBag(u)[fullid] or 0) or 0
end)

exports("getInventory", function(src)
  local u = getUser(src); return u and getBag(u) or {}
end)

exports("getInventoryWeight", function(src)
  local u = getUser(src); return u and calcPeso(getBag(u)) or 0
end)

exports("giveVehicleKey", function(src, plate)
  local u = getUser(src); return u and darItem(u, "veh_key|"..plate, 1) or false
end)

exports("takeVehicleKey", function(src, plate)
  local u = getUser(src); return u and tirarItem(u, "veh_key|"..plate, 1) or false
end)

exports("hasVehicleKey", function(src, plate)
  local u = getUser(src); return u and temItem(u, "veh_key|"..plate) or false
end)

exports("getVehicleKeys", function(src)
  local u = getUser(src)
  if not u then return {} end
  local keys = {}
  for fid in pairs(getBag(u)) do
    local p = fid:match("^veh_key|(.+)$")
    if p then keys[#keys+1] = p end
  end
  return keys
end)

exports("openChest", function(src, bau_id, peso_max)
  local b = bau(bau_id)
  TriggerClientEvent("vhub_inventory:open_chest", src, bau_id, b, peso_max or 100)
  return b
end)

exports("registerItemUse", function(fullid, cb)
  CFG.callbacks_uso[fullid] = cb
end)

exports("getItemDef",  function(fullid) return getItemDef(fullid)  end)
exports("getItemName", function(fullid) return getItemNome(fullid) end)

-- ── Net events ────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_inventory:use")
AddEventHandler("vhub_inventory:use", function(fullid)
  local src = source
  local u   = getUser(src)
  if not u or not temItem(u, fullid) then return end
  local cb = CFG.callbacks_uso[fullid] or CFG.callbacks_uso[fullid:match("^([^|]+)")]
  if cb then
    local ok, consumed = pcall(cb, u, fullid, 1)
    if ok and consumed then tirarItem(u, fullid, 1) end
  end
end)

RegisterNetEvent("vhub_inventory:give_item")
AddEventHandler("vhub_inventory:give_item", function(target_src, fullid, amount)
  local src  = source
  local u    = getUser(src)
  local tu   = getUser(tonumber(target_src))
  if not u or not tu then return end
  amount = math.floor(math.abs(tonumber(amount) or 1))
  -- verifica dry run em ambos antes de modificar
  if darItem(tu, fullid, amount, true, true) and tirarItem(u, fullid, amount, true, true) then
    tirarItem(u,  fullid, amount)
    darItem(tu,   fullid, amount)
  else
    TriggerClientEvent("vhub_inventory:notify", src,
      "Inventário cheio ou itens insuficientes.")
  end
end)

RegisterNetEvent("vhub_inventory:trash")
AddEventHandler("vhub_inventory:trash", function(fullid, amount)
  local u = getUser(source)
  if u then tirarItem(u, fullid, math.floor(math.abs(tonumber(amount) or 1))) end
end)

RegisterNetEvent("vhub_inventory:chest_take")
AddEventHandler("vhub_inventory:chest_take", function(bau_id, fullid, amount)
  local u = getUser(source)
  if not u then return end
  amount = math.floor(math.abs(tonumber(amount) or 1))
  local b    = bau(bau_id)
  local curr = b[fullid] or 0
  if curr < amount then return end
  if darItem(u, fullid, amount, true, true) then
    darItem(u, fullid, amount)
    local novo = curr - amount
    b[fullid]  = novo > 0 and novo or nil
    TriggerClientEvent("vhub_inventory:chest_sync", source, bau_id, b)
  else
    TriggerClientEvent("vhub_inventory:notify", source, "Inventário cheio.")
  end
end)

RegisterNetEvent("vhub_inventory:chest_put")
AddEventHandler("vhub_inventory:chest_put", function(bau_id, fullid, amount)
  local u = getUser(source)
  if not u then return end
  amount = math.floor(math.abs(tonumber(amount) or 1))
  if tirarItem(u, fullid, amount, true, true) then
    tirarItem(u, fullid, amount)
    local b   = bau(bau_id)
    b[fullid] = (b[fullid] or 0) + amount
    TriggerClientEvent("vhub_inventory:chest_sync", source, bau_id, b)
  end
end)

-- ── Eventos vHub ─────────────────────────────────────────────────────────────

AddEventHandler("vHub:playerDeath", function(user)
  if not user or not CFG.perder_ao_morrer then return end
  local bag  = getBag(user)
  local keep = {}
  for fid, n in pairs(bag) do
    for _, p in ipairs(CFG.itens_preservados) do
      if fid == p or fid:match("^" .. p .. "|") then
        keep[fid] = n; break
      end
    end
  end
  user.data.inventory = keep
  TriggerClientEvent("vhub_inventory:update", user.source, keep)
end)

-- ── Callbacks padrão de uso ───────────────────────────────────────────────────

CFG.callbacks_uso["water_bottle"] = function(user)
  pcall(function() exports.vhub_survival:varyVital(user.source, "agua", 0.3) end)
  return true
end

CFG.callbacks_uso["sandwich"] = function(user)
  pcall(function() exports.vhub_survival:varyVital(user.source, "comida", 0.35) end)
  return true
end

CFG.callbacks_uso["bandage"] = function(user)
  local hp = user.data.state and user.data.state.health or 150
  TriggerClientEvent("vhub_player_state:set_health", user.source, math.min(200, hp + 10))
  return true
end

CFG.callbacks_uso["medkit"] = function(user)
  TriggerClientEvent("vhub_player_state:set_health", user.source, 200)
  TriggerClientEvent("vhub_player_state:set_armour", user.source, 50)
  return true
end
