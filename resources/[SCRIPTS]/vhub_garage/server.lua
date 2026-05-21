-- vhub_garage/server.lua
-- Spawn e guarda de veículos — servidor autoritativo.
-- Estado do veículo: user.data.vehicles[plate] (autosave vHub, sem getCData/setCData).
-- Somente quem tem a chave no inventário pode spawnar/guardar.

local _sessions = {}   -- src → live user ref

-- ── Configuração ──────────────────────────────────────────────────────────────

local CFG = {
  taxa_force_out = 50,
  raio_guardar   = 15,

  garagens = {
    { label = "Garagem Los Santos",   x = -341.99, y = -167.42, z = 38.73, h = 118.0, raio = 8.0 },
    { label = "Garagem Sandy Shores", x = 1869.34, y = 3691.84, z = 33.58, h = 210.0, raio = 8.0 },
    { label = "Garagem Paleto Bay",   x = -237.25, y = 6328.11, z = 32.64, h = 46.0,  raio = 8.0 },
  },

  spawn_offset = { x = 0.0, y = 5.0, z = 0.0 },
}

-- ── Inicialização (jogadores já online num resource restart) ─────────────────

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  for _, s in ipairs(GetPlayers()) do
    TriggerClientEvent("vhub_garage:setup", tonumber(s), CFG.garagens)
  end
  print("[vhub_garage] Pronto.")
end)

-- ── Sessões (referências vivas) ───────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  _sessions[user.source] = user
  if not user.data.vehicles then user.data.vehicles = {} end
end)

AddEventHandler("vHub:playerSpawn", function(user)
  _sessions[user.source] = user
  TriggerClientEvent("vhub_garage:setup", user.source, CFG.garagens)

  -- Reenvia veículos que estavam fora (reconexão/respawn)
  local veiculos_fora = {}
  if user.data.vehicles then
    for plate, state in pairs(user.data.vehicles) do
      if type(state) == "table" and state.out and state.position then
        veiculos_fora[plate] = {
          customization = state.customization,
          condition     = state.condition,
          fuel          = state.fuel,
          locked        = state.locked,
          position      = state.position,
          rotation      = state.rotation,
        }
      end
    end
  end
  if next(veiculos_fora) then
    TriggerClientEvent("vhub_garage:spawn_out", user.source, veiculos_fora)
  end
end)

AddEventHandler("playerDropped", function()
  _sessions[source] = nil
end)

local function getUser(src)
  return _sessions[tonumber(src)]
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getVehicles(user)
  if not user.data.vehicles then user.data.vehicles = {} end
  return user.data.vehicles
end

local function carregarEstado(user, plate)
  local veh = getVehicles(user)[plate]
  if type(veh) == "table" then return veh end
  return {
    model         = plate,  -- fallback; concessionária garante model correto
    customization = nil,
    condition     = nil,
    fuel          = 100.0,
    locked        = false,
    out           = false,
    position      = nil,
    rotation      = nil,
  }
end

local function salvarEstado(user, plate, state)
  getVehicles(user)[plate] = state
end

local function temChave(src, plate)
  local ok, has = pcall(function()
    return exports.vhub_inventory:hasVehicleKey(src, plate)
  end)
  return ok and has == true
end

-- ── Net events ────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_garage:get_vehicles")
AddEventHandler("vhub_garage:get_vehicles", function()
  local src  = source
  local user = getUser(src)
  if not user or not user.char_id then return end

  local ok_keys, keys = pcall(function()
    return exports.vhub_inventory:getVehicleKeys(src)
  end)
  local chaves = (ok_keys and type(keys) == "table") and keys or {}

  local lista = {}
  for _, plate in ipairs(chaves) do
    local state = carregarEstado(user, plate)
    lista[plate] = {
      na_garagem = not state.out,
      fuel       = state.fuel,
      plate      = plate,
      model      = state.model or (state.customization and state.customization.model),
    }
  end
  TriggerClientEvent("vhub_garage:vehicle_list", src, lista)
end)

RegisterNetEvent("vhub_garage:spawn")
AddEventHandler("vhub_garage:spawn", function(plate, garagem_idx)
  local src  = source
  local user = getUser(src)
  if not user or not user.char_id then
    TriggerClientEvent("vhub_garage:notify", src,
      "Sessão não carregada. Tente novamente em instantes.")
    return
  end

  if not temChave(src, plate) then
    TriggerClientEvent("vhub_garage:notify", src, "Você não tem a chave deste veículo.")
    return
  end

  local state = carregarEstado(user, plate)

  if state.out then
    local ok, pagou = pcall(function()
      return exports.vhub_money:tryPayment(src, CFG.taxa_force_out)
    end)
    if not (ok and pagou) then
      TriggerClientEvent("vhub_garage:notify", src,
        ("Veículo já está fora. Force-out custa R$ %d."):format(CFG.taxa_force_out))
      return
    end
  end

  local garagem = CFG.garagens[garagem_idx] or CFG.garagens[1]
  local pos = {
    x       = garagem.x + CFG.spawn_offset.x,
    y       = garagem.y + CFG.spawn_offset.y,
    z       = garagem.z + CFG.spawn_offset.z,
    heading = garagem.h,
  }

  state.out      = true
  state.position = { x = pos.x, y = pos.y, z = pos.z }
  state.rotation = nil
  salvarEstado(user, plate, state)

  TriggerClientEvent("vhub_garage:do_spawn", src, plate, {
    customization = state.customization,
    condition     = state.condition,
    fuel          = state.fuel,
    locked        = state.locked,
  }, pos)

  print(("[vhub_garage] spawn uid=%d plate=%s garagem=%d"):format(
    user.id, plate, garagem_idx or 1))
end)

RegisterNetEvent("vhub_garage:store")
AddEventHandler("vhub_garage:store", function(plate, state_do_cliente)
  local src  = source
  local user = getUser(src)
  if not user or not user.char_id then return end

  if not temChave(src, plate) then
    TriggerClientEvent("vhub_garage:notify", src, "Você não tem a chave deste veículo.")
    return
  end

  local state = carregarEstado(user, plate)

  if type(state_do_cliente) == "table" then
    if state_do_cliente.customization then
      state.customization = state_do_cliente.customization
    end
    if state_do_cliente.condition then
      state.condition = state_do_cliente.condition
    end
    if type(state_do_cliente.fuel) == "number" then
      state.fuel = math.max(0, math.min(100, state_do_cliente.fuel))
    end
    state.locked = state_do_cliente.locked == true
  end

  state.out      = false
  state.position = nil
  state.rotation = nil
  salvarEstado(user, plate, state)

  TriggerClientEvent("vhub_garage:do_despawn", src, plate)
  TriggerClientEvent("vhub_garage:notify", src,
    ("Veículo %s guardado na garagem."):format(plate))
  print(("[vhub_garage] store uid=%d plate=%s"):format(user.id, plate))
end)

RegisterNetEvent("vhub_garage:update_state")
AddEventHandler("vhub_garage:update_state", function(plate, update)
  local src  = source
  if type(update) ~= "table" then return end
  local user = getUser(src)
  if not user or not user.char_id then return end
  if not temChave(src, plate) then return end

  local state = carregarEstado(user, plate)
  if not state.out then return end  -- só atualiza veículos fora

  if type(update.position) == "table" then
    local x = tonumber(update.position.x)
    local y = tonumber(update.position.y)
    local z = tonumber(update.position.z)
    if x and y and z
       and math.abs(x) < 8000 and math.abs(y) < 8000
       and z > -200 and z < 2000 then
      state.position = { x = x, y = y, z = z }
    end
  end

  if type(update.rotation)      == "table"   then state.rotation      = update.rotation      end
  if type(update.condition)     == "table"   then state.condition      = update.condition     end
  if type(update.customization) == "table"   then state.customization  = update.customization end
  if type(update.fuel)          == "number"  then
    state.fuel = math.max(0, math.min(100, update.fuel))
  end
  if type(update.locked) == "boolean" then state.locked = update.locked end

  salvarEstado(user, plate, state)
end)

RegisterNetEvent("vhub_garage:transfer_key")
AddEventHandler("vhub_garage:transfer_key", function(target_src, plate)
  local src   = source
  local user  = getUser(src)
  local tuser = getUser(tonumber(target_src))
  if not user or not tuser then return end
  if not temChave(src, plate) then
    TriggerClientEvent("vhub_garage:notify", src, "Você não tem esta chave.")
    return
  end

  pcall(function() exports.vhub_inventory:takeVehicleKey(src, plate) end)
  pcall(function() exports.vhub_inventory:giveVehicleKey(target_src, plate) end)

  TriggerClientEvent("vhub_garage:notify", src,
    ("Chave do veículo %s transferida para %s."):format(plate, tuser.name or "?"))
  TriggerClientEvent("vhub_garage:notify", target_src,
    ("Você recebeu a chave do veículo %s de %s."):format(plate, user.name or "?"))
end)

-- ── Exports ───────────────────────────────────────────────────────────────────

exports("getVehicleState", function(src, plate)
  local u = getUser(src)
  return u and carregarEstado(u, plate) or nil
end)

exports("forceStore", function(src, plate, state_client)
  local u = getUser(src)
  if not u then return end
  local state = carregarEstado(u, plate)
  if type(state_client) == "table" then
    if state_client.customization then state.customization = state_client.customization end
    if state_client.condition     then state.condition     = state_client.condition     end
    if type(state_client.fuel) == "number" then
      state.fuel = math.max(0, math.min(100, state_client.fuel))
    end
  end
  state.out      = false
  state.position = nil
  state.rotation = nil
  salvarEstado(u, plate, state)
end)
