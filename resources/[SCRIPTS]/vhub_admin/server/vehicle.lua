-- server/vehicle.lua - painel de frota delegado ao owner vhub_garage
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E
local U = VHubAdmin.U

local statusAllowed = {}
for _, entry in ipairs(CFG.selectors.vehicle_statuses) do statusAllowed[entry.value] = true end

local function garageCall(fn)
  local ok, first, second = pcall(fn)
  return ok, first, second
end

local function plateOrNotify(src, raw)
  local plate = U.plate(raw)
  if not plate then Core:notify(src, 'Placa invalida.', 'erro') end
  return plate
end

local function manage(src)
  return Core:guard(src, 'vehicle_manage', 'vehicle')
end

local function auditQueued(src, action, payload)
  Core:audit(src, action .. '_requested', nil, payload)
end


-- ============================================================
-- LEITURA DA FROTA
-- ============================================================

local function fleetFilter(raw)
  raw = type(raw) == 'table' and raw or {}
  local filter = {}

  local status = U.identifier(raw.status, 24)
  if status and statusAllowed[status] then filter.status = status end
  local vtype = U.identifier(raw.vtype, 24)
  if vtype then filter.vtype = vtype end
  local charId = U.number(raw.char_id, 1, 2147483647)
  if charId and charId % 1 == 0 then filter.char_id = math.floor(charId) end
  local search = U.safeText(raw.search, 32):gsub('[%%_]', '')
  if search ~= '' then filter.search = search end
  return filter
end

RegisterNetEvent(E.REQ_FLEET)
AddEventHandler(E.REQ_FLEET, function(rawFilter, rawOffset)
  local src = source
  if not Core:guard(src, 'vehicle_view', 'fleet') then return end

  local offset = U.number(rawOffset, 0, 100000)
  if offset and offset % 1 ~= 0 then offset = nil end
  if not offset then return Core:notify(src, 'Pagina invalida.', 'erro') end
  local filter = fleetFilter(rawFilter)

  Citizen.CreateThread(function()
    local ok, rows = garageCall(function()
      return exports.vhub_garage:adminListVehicles(filter, CFG.limits.fleet_page, math.floor(offset))
    end)
    TriggerClientEvent(E.FLEET_LIST, src, ok and type(rows) == 'table' and rows or {})
  end)
end)

RegisterNetEvent(E.REQ_FLEET_DETAIL)
AddEventHandler(E.REQ_FLEET_DETAIL, function(rawPlate)
  local src = source
  if not Core:guard(src, 'vehicle_view', 'fleet_detail') then return end
  local plate = plateOrNotify(src, rawPlate)
  if not plate then return end

  Citizen.CreateThread(function()
    local ok, detail = garageCall(function() return exports.vhub_garage:adminGetVehicle(plate) end)
    TriggerClientEvent(E.FLEET_DETAIL, src, ok and detail or nil)
  end)
end)


-- ============================================================
-- MUTACOES PERSISTENTES
-- ============================================================

RegisterNetEvent(E.ACT_FLEET_GIVE)
AddEventHandler(E.ACT_FLEET_GIVE, function(rawTarget, rawModel, rawPlate)
  local src = source
  if not manage(src) then return end

  local target = Core:onlineTarget(rawTarget)
  local charId = target and Core:getCharId(target) or nil
  local model = U.identifier(rawModel, 64)
  local plate = nil
  if rawPlate ~= nil and rawPlate ~= '' then plate = U.plate(rawPlate) end
  if not target or not charId or not model or (rawPlate ~= nil and rawPlate ~= '' and not plate) then
    return Core:notify(src, 'Alvo, modelo ou placa invalidos.', 'erro')
  end

  Citizen.CreateThread(function()
    local ok, generatedPlate = garageCall(function()
      return exports.vhub_garage:adminGiveVehicle(charId, model, plate, src)
    end)
    if not ok or type(generatedPlate) ~= 'string' then
      return Core:notify(src, 'Concessao recusada pela garagem.', 'erro')
    end
    Core:audit(src, 'fleet_give', target, { char_id = charId, model = model, plate = generatedPlate })
    Core:notify(src, ('Veiculo persistente concedido: %s.'):format(generatedPlate), 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_TRANSFER)
AddEventHandler(E.ACT_FLEET_TRANSFER, function(rawPlate, rawTarget)
  local src = source
  if not manage(src) then return end

  local plate = plateOrNotify(src, rawPlate)
  local target = Core:onlineTarget(rawTarget)
  local charId = target and Core:getCharId(target) or nil
  if not plate or not target or not charId then return end

  Citizen.CreateThread(function()
    local ok, accepted = garageCall(function() return exports.vhub_garage:adminTransfer(plate, charId, src) end)
    if not ok or accepted ~= true then return Core:notify(src, 'Transferencia recusada.', 'erro') end
    auditQueued(src, 'fleet_transfer', { plate = plate, char_id = charId })
    Core:notify(src, 'Transferencia encaminhada para a garagem.', 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_DELETE)
AddEventHandler(E.ACT_FLEET_DELETE, function(rawPlate)
  local src = source
  if not manage(src) then return end
  local plate = plateOrNotify(src, rawPlate)
  if not plate then return end

  Citizen.CreateThread(function()
    local ok, accepted = garageCall(function() return exports.vhub_garage:adminDelete(plate, src) end)
    if not ok or accepted ~= true then return Core:notify(src, 'Exclusao recusada.', 'erro') end
    auditQueued(src, 'fleet_delete', { plate = plate })
    Core:notify(src, 'Exclusao encaminhada para a garagem.', 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_STATUS)
AddEventHandler(E.ACT_FLEET_STATUS, function(rawPlate, rawStatus)
  local src = source
  if not manage(src) then return end
  local plate = plateOrNotify(src, rawPlate)
  local status = U.identifier(rawStatus, 24)
  if not plate or not status or not statusAllowed[status] then
    return Core:notify(src, 'Placa ou status invalido.', 'erro')
  end

  Citizen.CreateThread(function()
    local ok, accepted = garageCall(function() return exports.vhub_garage:adminSetStatus(plate, status, src) end)
    if not ok or accepted ~= true then return Core:notify(src, 'Status recusado.', 'erro') end
    auditQueued(src, 'fleet_status', { plate = plate, status = status })
    Core:notify(src, 'Status encaminhado para a garagem.', 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_IPVA)
AddEventHandler(E.ACT_FLEET_IPVA, function(rawPlate, rawDays)
  local src = source
  if not manage(src) then return end
  local plate = plateOrNotify(src, rawPlate)
  local days = U.number(rawDays, 1, 3650)
  if not plate or not days or days % 1 ~= 0 then return Core:notify(src, 'Placa ou dias invalidos.', 'erro') end

  Citizen.CreateThread(function()
    local ok, accepted = garageCall(function()
      return exports.vhub_garage:adminRenewIpva(plate, math.floor(days), src)
    end)
    if not ok or accepted ~= true then return Core:notify(src, 'Renovacao recusada.', 'erro') end
    auditQueued(src, 'fleet_ipva', { plate = plate, days = days })
    Core:notify(src, 'IPVA encaminhado para a garagem.', 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_RELEASE)
AddEventHandler(E.ACT_FLEET_RELEASE, function(rawPlate)
  local src = source
  if not manage(src) then return end
  local plate = plateOrNotify(src, rawPlate)
  if not plate then return end

  Citizen.CreateThread(function()
    local ok, accepted = garageCall(function() return exports.vhub_garage:adminReleaseImpound(plate, src) end)
    if not ok or accepted ~= true then return Core:notify(src, 'Liberacao recusada.', 'erro') end
    auditQueued(src, 'fleet_release', { plate = plate })
    Core:notify(src, 'Liberacao encaminhada para a garagem.', 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_GRANT_KEY)
AddEventHandler(E.ACT_FLEET_GRANT_KEY, function(rawPlate, rawTarget, rawDays)
  local src = source
  if not manage(src) then return end
  local plate = plateOrNotify(src, rawPlate)
  local target = Core:onlineTarget(rawTarget)
  local charId = target and Core:getCharId(target) or nil
  local days = nil
  if rawDays ~= nil and rawDays ~= '' then days = U.number(rawDays, 1, 3650) end
  if not plate or not target or not charId or (rawDays ~= nil and rawDays ~= '' and (not days or days % 1 ~= 0)) then
    return Core:notify(src, 'Placa, alvo ou prazo invalido.', 'erro')
  end

  Citizen.CreateThread(function()
    local ok, accepted = garageCall(function()
      return exports.vhub_garage:adminGrantKey(plate, charId, 'shared', days and math.floor(days) or nil, src)
    end)
    if not ok or accepted ~= true then return Core:notify(src, 'Chave recusada.', 'erro') end
    auditQueued(src, 'fleet_grant_key', { plate = plate, char_id = charId, days = days })
    Core:notify(src, 'Chave encaminhada para a garagem.', 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_REVOKE_KEY)
AddEventHandler(E.ACT_FLEET_REVOKE_KEY, function(rawPlate, rawTarget)
  local src = source
  if not manage(src) then return end
  local plate = plateOrNotify(src, rawPlate)
  local target = Core:onlineTarget(rawTarget)
  local charId = target and Core:getCharId(target) or nil
  if not plate or not target or not charId then return end

  Citizen.CreateThread(function()
    local ok, accepted = garageCall(function() return exports.vhub_garage:adminRevokeKey(plate, charId, src) end)
    if not ok or accepted ~= true then return Core:notify(src, 'Revogacao recusada.', 'erro') end
    auditQueued(src, 'fleet_revoke_key', { plate = plate, char_id = charId })
    Core:notify(src, 'Chave encaminhada para a garagem.', 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_DESPAWN)
AddEventHandler(E.ACT_FLEET_DESPAWN, function(rawPlate)
  local src = source
  if not manage(src) then return end
  local plate = plateOrNotify(src, rawPlate)
  if not plate then return end

  Citizen.CreateThread(function()
    local ok, accepted = garageCall(function() return exports.vhub_garage:adminDespawn(plate, src) end)
    if not ok or accepted ~= true then return Core:notify(src, 'Recolhimento recusado.', 'erro') end
    auditQueued(src, 'fleet_despawn', { plate = plate })
    Core:notify(src, 'Recolhimento encaminhado para a garagem.', 'sucesso')
  end)
end)


-- ============================================================
-- MANUTENCAO
-- ============================================================

RegisterNetEvent(E.ACT_FLEET_PURGE_KEYS)
AddEventHandler(E.ACT_FLEET_PURGE_KEYS, function()
  local src = source
  if not manage(src) then return end
  Citizen.CreateThread(function()
    local ok, count = garageCall(function() return exports.vhub_garage:adminPurgeExpiredKeys(src) end)
    if not ok then return Core:notify(src, 'Limpeza de chaves recusada.', 'erro') end
    count = math.max(0, math.floor(tonumber(count) or 0))
    Core:audit(src, 'fleet_purge_keys', nil, { count = count })
    Core:notify(src, ('%d chaves vencidas removidas.'):format(count), 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_PURGE_LOGS)
AddEventHandler(E.ACT_FLEET_PURGE_LOGS, function(rawDays)
  local src = source
  if not manage(src) then return end
  local days = U.number(rawDays, 7, 3650)
  if not days or days % 1 ~= 0 then return Core:notify(src, 'Retencao invalida.', 'erro') end

  Citizen.CreateThread(function()
    local ok, count = garageCall(function()
      return exports.vhub_garage:adminPurgeOldLogs(math.floor(days), src)
    end)
    if not ok then return Core:notify(src, 'Limpeza de logs recusada.', 'erro') end
    count = math.max(0, math.floor(tonumber(count) or 0))
    Core:audit(src, 'fleet_purge_logs', nil, { days = days, count = count })
    Core:notify(src, ('%d logs removidos.'):format(count), 'sucesso')
  end)
end)

RegisterNetEvent(E.ACT_FLEET_FINALIZE)
AddEventHandler(E.ACT_FLEET_FINALIZE, function()
  local src = source
  if not manage(src) then return end
  Citizen.CreateThread(function()
    local ok, count = garageCall(function() return exports.vhub_garage:adminFinalizeStaleAuctions(src) end)
    if not ok then return Core:notify(src, 'Finalizacao recusada.', 'erro') end
    count = math.max(0, math.floor(tonumber(count) or 0))
    Core:audit(src, 'fleet_finalize_auctions', nil, { count = count })
    Core:notify(src, ('%d leiloes processados.'):format(count), 'sucesso')
  end)
end)


-- ============================================================
-- AÇÕES DE VEÍCULO (server valida perm → repassa DO_ ao cliente)
-- ============================================================

RegisterNetEvent(E.ACT_SPAWNCAR)
AddEventHandler(E.ACT_SPAWNCAR, function(rawModel)
  local src = source
  if not Core:guard(src, 'vehicle_spawn', 'veh') then return end
  local model = type(rawModel) == 'string' and rawModel:match('^[%w_]+$') and rawModel:lower()
  if not model then return Core:notify(src, 'Modelo invalido.', 'erro') end
  Core:audit(src, 'spawncar', nil, { model = model })
  TriggerClientEvent(E.DO_SPAWNCAR, src, model)
end)

RegisterNetEvent(E.ACT_DELVEH)
AddEventHandler(E.ACT_DELVEH, function()
  local src = source
  if not Core:guard(src, 'vehicle_delete', 'veh') then return end
  Core:audit(src, 'delveh', nil, {})
  TriggerClientEvent(E.DO_DELVEH, src)
end)

RegisterNetEvent(E.ACT_FIX)
AddEventHandler(E.ACT_FIX, function()
  local src = source
  if not Core:guard(src, 'vehicle_fix', 'veh') then return end
  Core:audit(src, 'fixveh', nil, {})
  TriggerClientEvent(E.DO_FIX, src)
end)

RegisterNetEvent(E.ACT_BOOST)
AddEventHandler(E.ACT_BOOST, function()
  local src = source
  if not Core:guard(src, 'vehicle_boost', 'veh') then return end
  local mult = tonumber(CFG.vehicle_boost and CFG.vehicle_boost.multiplier) or 2.5
  local dur  = tonumber(CFG.vehicle_boost and CFG.vehicle_boost.duration_ms) or 15000
  Core:audit(src, 'boost', nil, { mult = mult, duration_ms = dur })
  TriggerClientEvent(E.DO_BOOST, src, mult, dur)
end)

RegisterNetEvent(E.ACT_FLIP)
AddEventHandler(E.ACT_FLIP, function()
  local src = source
  if not Core:guard(src, 'vehicle_fix', 'veh') then return end
  Core:audit(src, 'flipveh', nil, {})
  TriggerClientEvent(E.DO_FLIP, src)
end)

RegisterNetEvent(E.ACT_TUNING)
AddEventHandler(E.ACT_TUNING, function()
  local src = source
  if not Core:guard(src, 'vehicle_fix', 'veh') then return end
  Core:audit(src, 'tuning', nil, {})
  TriggerClientEvent(E.DO_TUNING, src)
end)

RegisterNetEvent(E.ACT_CARCOLOR)
AddEventHandler(E.ACT_CARCOLOR, function(rawR, rawG, rawB)
  local src = source
  if not Core:guard(src, 'vehicle_fix', 'veh') then return end
  local r = math.floor(math.max(0, math.min(255, tonumber(rawR) or 0)))
  local g = math.floor(math.max(0, math.min(255, tonumber(rawG) or 0)))
  local b = math.floor(math.max(0, math.min(255, tonumber(rawB) or 0)))
  Core:audit(src, 'carcolor', nil, { r = r, g = g, b = b })
  TriggerClientEvent(E.DO_CARCOLOR, src, r, g, b)
end)
