-- server.lua — sessão de abastecimento server-authoritative
---@diagnostic disable: undefined-global

local C = VHubFuel.Config
local E = VHubFuel.E

local sessions = {}
local locks = {}
local pending = {}
local lastAction = {}
local generation = 0
local workerRunning = false
local migrationReady = false


-- ============================================================
-- HELPERS
-- ============================================================

local function notify(src, kind, message)
  TriggerClientEvent('vHub:notify', src, kind, message)
end

local function rate(src, key, interval)
  local now = GetGameTimer()
  local bucket = lastAction[src] or {}
  if now - (bucket[key] or -interval) < interval then return false end
  bucket[key] = now
  lastAction[src] = bucket
  return true
end

local function normalizePlate(value)
  local plate = tostring(value or ''):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  if not plate or plate == '' or #plate > 10 then return nil end
  if not plate:match('^[A-Z0-9]+[A-Z0-9 ]*[A-Z0-9]$') then return nil end
  return plate
end

local function finite(value, minimum, maximum)
  if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then return nil end
  return math.max(minimum, math.min(maximum, value))
end

local function nearestStation(coords, electric)
  local stations = electric and C.ElectricStations or C.GasStations
  for index = 1, #stations do
    if #(coords - stations[index]) <= C.StationRadius then return index end
  end
  return nil
end

local function isNearAnyStation(coords)
  return nearestStation(coords, false) ~= nil or nearestStation(coords, true) ~= nil
end

local function hasVehicleKey(src, plate)
  local ok, allowed = pcall(function()
    return exports.vhub_inventory:hasVehicleKey(src, plate)
  end)
  return ok and allowed == true
end

local function giveItem(src, item, amount, meta)
  local ok, result = pcall(function()
    return exports.vhub_inventory:giveItem(src, item, amount, meta)
  end)
  return ok and result == true
end

local function takeFuelCan(src)
  local ok, snapshot = pcall(function() return exports.vhub_inventory:getInventory(src) end)
  if not ok or type(snapshot) ~= 'table' or type(snapshot.slots) ~= 'table' then return nil end

  for slot, entry in pairs(snapshot.slots) do
    if type(entry) == 'table' and entry.id == C.JerryCanItem then
      local meta = type(entry.meta) == 'table' and entry.meta or nil
      local stored = meta and meta.fuel ~= nil and tonumber(meta.fuel) or C.JerryCanFuel
      if stored and stored == stored and math.abs(stored) ~= math.huge
          and stored > 0.01 and stored <= C.JerryCanFuel then
        local takenOk, taken = pcall(function()
          return exports.vhub_inventory:takeItemFromSlot(src, tonumber(slot), 1)
        end)
        if takenOk and taken == true then
          local preserved = {}
          if meta then for key, value in pairs(meta) do preserved[key] = value end end
          return stored, preserved
        end
      end
    end
  end
  return nil
end

local function tryPayment(src, amount)
  local ok, result = pcall(function() return exports.vhub_money:tryPayment(src, amount, false) end)
  return ok and result == true
end

local function refundPayment(src, amount, reason)
  local ok, result = pcall(function()
    return exports.vhub_money:giveWallet(src, amount, reason or 'fuel_refund')
  end)
  return ok and result == true
end

local function coreState(plate)
  local ok, state = pcall(function() return exports.vhub:getVehicleState(plate) end)
  return ok and type(state) == 'table' and state or nil
end

local function commitFuel(plate, fuel, sourceTag)
  local ok, accepted = pcall(function()
    return exports.vhub:commitVehicleState(plate, { fuel = fuel }, sourceTag)
  end)
  return ok and accepted == true
end

local function setHoseState(src, session)
  pcall(function()
    local state = Player(src).state
    if not session then
      state:set('vh_fuel_hose', nil, true)
      return
    end
    state:set('vh_fuel_hose', {
      station_id = session.stationId,
      vehicle_net_id = session.netId,
      electric = session.electric,
      generation = session.generation,
      mode = session.mode,
      pump = session.pump,
    }, true)
  end)
end

local function validatePump(src, resolved, payload)
  if type(payload) ~= 'table' then return nil end
  local model = tonumber(payload.model)
  local cfg = model and C.PumpModels[model]
  if not cfg or (cfg.electric == true) ~= resolved.electric then return nil end

  local x = finite(tonumber(payload.x), -10000.0, 10000.0)
  local y = finite(tonumber(payload.y), -10000.0, 10000.0)
  local z = finite(tonumber(payload.z), -1000.0, 3000.0)
  if not x or not y or not z then return nil end
  local coords = vec3(x, y, z)
  local stations = resolved.electric and C.ElectricStations or C.GasStations
  local station = stations[resolved.stationId]
  if not station or #(coords - station) > C.StationRadius then return nil end
  if #(coords - GetEntityCoords(resolved.entity)) > C.RopeMaxLength then return nil end
  if #(coords - GetEntityCoords(GetPlayerPed(src))) > C.RopeMaxLength then return nil end

  return { model = model, x = x, y = y, z = z }
end

local function resolveVehicle(src, netId, mode)
  netId = tonumber(netId)
  if not netId or netId <= 0 then return nil, 'Veículo inválido.' end

  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 or GetEntityType(entity) ~= 2 then
    return nil, 'Veículo indisponível.'
  end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil, 'Jogador indisponível.' end
  if GetEntityHealth(ped) <= 0 then return nil, 'Jogador incapacitado.' end
  if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > C.PlayerVehicleDistance then
    return nil, 'Aproxime-se do veículo.'
  end
  if GetEntitySpeed(entity) > 1.0 then return nil, 'Pare o veículo.' end
  if GetPedInVehicleSeat(entity, -1) ~= 0 then return nil, 'O veículo precisa estar vazio.' end

  local plate = normalizePlate(GetVehicleNumberPlateText(entity))
  if not plate or not hasVehicleKey(src, plate) then return nil, 'Chave do veículo exigida.' end

  local electric = C.ElectricModels[GetEntityModel(entity)] == true
  local stationId
  if mode == 'pump' then
    stationId = nearestStation(GetEntityCoords(entity), electric)
    if not stationId then return nil, 'Veículo fora de um posto compatível.' end
  end

  return {
    entity = entity,
    netId = netId,
    plate = plate,
    electric = electric,
    stationId = stationId,
  }
end

local function endSession(src, reason)
  local session = sessions[src]
  if not session then return end

  sessions[src] = nil
  if locks[session.plate] == src then locks[session.plate] = nil end
  if session.mode == 'can' and session.itemConsumed and session.remaining > 0.01 then
    local meta = session.canMeta or {}
    meta.fuel = session.remaining
    local restored = giveItem(src, C.JerryCanItem, 1, meta)
    if not restored and GetPlayerName(src) then
      notify(src, 'erro', 'Falha ao devolver o saldo restante do galão.')
    end
    session.itemConsumed = false
  end
  setHoseState(src, nil)
  TriggerClientEvent(E.ENDED, src, reason or 'cancelled', session.generation)
end

local function emitProgress(src, session, fuel)
  TriggerClientEvent(E.PROGRESS, src, {
    generation = session.generation,
    fuel = fuel,
    dispensed = session.dispensed,
    cost = session.totalCost,
    mode = session.mode,
    electric = session.electric,
    remaining = session.mode == 'can' and session.remaining or nil,
  })
end


-- ============================================================
-- SESSION WORKER — 1 HZ, SOMENTE ENQUANTO HÁ SESSÕES
-- ============================================================

local function tickSession(src, session)
  if GetGameTimer() - session.startedAt > C.SessionTimeoutMs then
    return endSession(src, 'timeout')
  end

  local resolved = resolveVehicle(src, session.netId, session.mode)
  if not resolved or resolved.plate ~= session.plate then return endSession(src, 'invalid') end
  if session.mode == 'pump' then
    local pumpCoords = vec3(session.pump.x, session.pump.y, session.pump.z)
    local pedCoords = GetEntityCoords(GetPlayerPed(src))
    if #(pumpCoords - GetEntityCoords(resolved.entity)) > C.RopeMaxLength
        or #(pumpCoords - pedCoords) > C.RopeMaxLength then
      return endSession(src, 'hose_distance')
    end
  end

  local state = coreState(session.plate)
  local current = state and finite(state.fuel, 0.0, 100.0)
  if not current then return endSession(src, 'state_error') end
  if current >= 100.0 then return endSession(src, 'full') end

  local delta = session.electric and C.ChargePerTick or C.FuelPerTick
  if session.mode == 'can' then
    delta = math.min(delta, session.remaining)
    if delta <= 0 then return endSession(src, 'empty_can') end
  end
  delta = math.min(delta, 100.0 - current)
  local nextFuel = current + delta

  if session.mode == 'pump' then
    local unitPrice = session.electric and C.ElectricPricePerPercent or C.PricePerPercent
    local price = math.max(1, math.floor(delta * unitPrice + 0.5))
    if not tryPayment(src, price) then
      return endSession(src, 'no_money')
    end
    if not commitFuel(session.plate, nextFuel, 'pump') then
      refundPayment(src, price, 'fuel_commit_refund')
      return endSession(src, 'commit_error')
    end
    session.totalCost = session.totalCost + price
  else
    if not commitFuel(session.plate, nextFuel, 'fuel_can') then
      return endSession(src, 'commit_error')
    end
    session.remaining = session.remaining - delta
  end
  session.dispensed = nextFuel - session.startFuel
  emitProgress(src, session, nextFuel)
end

local function startWorker()
  if workerRunning then return end
  workerRunning = true
  Citizen.CreateThread(function()
    while next(sessions) do
      Citizen.Wait(C.TickMs)
      for src, session in pairs(sessions) do tickSession(src, session) end
    end
    workerRunning = false
    if next(sessions) then startWorker() end
  end)
end

local function releasePendingLock(src)
  local plate = pending[src]
  if type(plate) == 'string' and not sessions[src] and locks[plate] == src then
    locks[plate] = nil
  end
end

local function beginSession(src, netId, mode, pumpPayload)
  if sessions[src] then endSession(src, 'restarted') end
  local resolved, errorMessage = resolveVehicle(src, netId, mode)
  if not resolved then return notify(src, 'negado', errorMessage) end
  if locks[resolved.plate] then
    return notify(src, 'negado', 'Veículo já está sendo abastecido.')
  end
  if mode == 'can' and resolved.electric then
    return notify(src, 'negado', 'Galão não recarrega veículo elétrico.')
  end

  local pump
  if mode == 'pump' then
    pump = validatePump(src, resolved, pumpPayload)
    if not pump then return notify(src, 'negado', 'Bomba de combustível inválida.') end
  end

  locks[resolved.plate] = src
  pending[src] = resolved.plate
  local state = coreState(resolved.plate)
  if not GetPlayerName(src) then return end
  local initialFuel = state and finite(state.fuel, 0.0, 100.0)
  if not initialFuel then
    return notify(src, 'erro', 'Estado de combustível indisponível.')
  end
  if initialFuel >= 100.0 then return notify(src, 'info', 'Tanque cheio.') end

  local canFuel = C.JerryCanFuel
  local canMeta
  if mode == 'can' then
    canFuel, canMeta = takeFuelCan(src)
    if not canFuel then return notify(src, 'negado', 'Galão vazio ou indisponível.') end
  end

  generation = generation + 1
  local session = {
    plate = resolved.plate,
    netId = resolved.netId,
    electric = resolved.electric,
    stationId = resolved.stationId,
    pump = pump,
    mode = mode,
    generation = generation,
    startedAt = GetGameTimer(),
    remaining = canFuel,
    dispensed = 0.0,
    startFuel = initialFuel,
    totalCost = 0,
    itemConsumed = mode == 'can',
    canMeta = canMeta,
  }
  sessions[src] = session
  setHoseState(src, session)
  TriggerClientEvent(E.STARTED, src, {
    mode = mode,
    generation = generation,
    vehicle_net_id = resolved.netId,
    electric = resolved.electric,
    fuel = initialFuel,
    dispensed = 0.0,
    cost = 0,
    pump = pump,
    remaining = mode == 'can' and canFuel or nil,
  })
  startWorker()
end


-- ============================================================
-- NETWORK BOUNDARY
-- ============================================================

RegisterNetEvent(E.START)
AddEventHandler(E.START, function(netId, mode, pumpPayload)
  local src = source
  if not migrationReady or not rate(src, 'start', C.RateStartMs) then return end
  if mode ~= 'pump' and mode ~= 'can' then return end
  if pending[src] then return end

  pending[src] = true
  Citizen.CreateThread(function()
    local ok = pcall(beginSession, src, netId, mode, pumpPayload)
    releasePendingLock(src)
    pending[src] = nil
    if not ok and GetPlayerName(src) then
      notify(src, 'erro', 'Falha interna ao iniciar abastecimento.')
    end
  end)
end)

RegisterNetEvent(E.STOP)
AddEventHandler(E.STOP, function()
  if rate(source, 'stop', 250) then endSession(source, 'cancelled') end
end)

RegisterNetEvent(E.BUY_CAN)
AddEventHandler(E.BUY_CAN, function()
  local src = source
  if not rate(src, 'buy_can', 1000) then return end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 or not isNearAnyStation(GetEntityCoords(ped)) then return end

  if not tryPayment(src, C.JerryCanCost) then
    return notify(src, 'negado', 'Dinheiro insuficiente.')
  end
  if not giveItem(src, C.JerryCanItem, 1, { fuel = C.JerryCanFuel }) then
    refundPayment(src, C.JerryCanCost, 'fuel_can_refund')
    return notify(src, 'erro', 'Inventário sem espaço.')
  end
  notify(src, 'sucesso', 'Galão comprado por $' .. C.JerryCanCost .. '.')
end)

local function isAdmin(src)
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  if not ok or not uid then return false end
  if uid == 1 or IsPlayerAceAllowed(src, 'vhub.fuel.admin') then return true end
  local allowed = false
  pcall(function() allowed = exports.vhub:hasPerm(uid, 'panel') == true end)
  return allowed
end

RegisterNetEvent(E.ADMIN_SET)
AddEventHandler(E.ADMIN_SET, function(netId, amount)
  local src = source
  if not isAdmin(src) or not rate(src, 'admin', 500) then return end
  amount = finite(tonumber(amount), 0.0, 100.0)
  local entity = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
  if not amount or not entity or entity == 0 or GetEntityType(entity) ~= 2 then return end
  local plate = normalizePlate(GetVehicleNumberPlateText(entity))
  if not plate then return end

  Citizen.CreateThread(function()
    if commitFuel(plate, amount, 'fuel_admin') then
      notify(src, 'sucesso', ('Combustível: %.1f%%.'):format(amount))
    else
      notify(src, 'erro', 'Falha ao persistir combustível.')
    end
  end)
end)


-- ============================================================
-- EXPORTS
-- ============================================================

-- Retorna cópia da sessão ativa do jogador.
exports('getSession', function(src)
  local session = sessions[tonumber(src)]
  if not session then return nil end
  local copy = {}; for key, value in pairs(session) do copy[key] = value end
  return copy
end)

-- Cancela sessão por chamada administrativa autorizada.
exports('cancelSession', function(src)
  if GetInvokingResource() ~= 'vhub_admin' then return false end
  src = tonumber(src)
  if not src or not sessions[src] then return false end
  endSession(src, 'admin_cancel')
  return true
end)


-- ============================================================
-- LIFECYCLE / MIGRATION
-- ============================================================

AddEventHandler('playerDropped', function()
  endSession(source, 'dropped')
  releasePendingLock(source)
  lastAction[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  for src in pairs(sessions) do endSession(src, 'resource_stop') end
end)

Citizen.CreateThread(function()
  local markerKey = 'vhub_fuel:adr61:migrated'
  local okMarker, marker = pcall(function() return exports.vhub:getGData(markerKey) end)
  if okMarker and marker == true then
    migrationReady = true
    GlobalState.vh_fuel_migration = { status = 'done' }
    return
  end

  local ok, result = pcall(function() return exports.vhub_conce:migrateFuelToCore() end)
  if not ok or type(result) ~= 'table' or (result.failed or 1) > 0 then
    GlobalState.vh_fuel_migration = { status = 'failed', failed = result and result.failed or -1 }
    return
  end

  pcall(function() exports.vhub:setGData(markerKey, true) end)
  GlobalState.vh_fuel_migration = {
    status = 'queued', total = result.total, migrated = result.migrated,
  }
  migrationReady = true
end)
