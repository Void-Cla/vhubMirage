-- server/core.lua — autoridade física, sessões, locks e saga financeira do vhub_custom
---@diagnostic disable: undefined-global

local CFG = VHubCustom.cfg
local U   = VHubCustom.U
local SQL = VHubCustom.SQL

VHubCustom.Core = {}
local Core = VHubCustom.Core

local _sessions     = {}
local _rates        = {}
local _leases       = {}
local _locksByPlate = {}
local _locksBySrc   = {}
local _zonesById    = {}
local _operationClaims = {}
local _catalog      = nil
local _tokenSeq     = 0
local _running      = true

local DOMAIN_CODE = { bennys = 'b', mec = 'm', oficina = 'o' }
local ACTION_CODE = {
  cosmetic = 'cos', repair_tyre = 'rty', repair_engine = 'ren', repair_body = 'rbo',
  tow = 'tow', handling = 'hnd', nitro_kit = 'nit', tune = 'tun',
  drift_install = 'dit', drift_remove = 'dre',
}

for _, zone in ipairs(CFG.zones) do _zonesById[zone.id] = zone end

local function nowMs() return GetGameTimer() end

local function expired(entry)
  return not entry or nowMs() > entry.expires_at
end

local function token(prefix)
  _tokenSeq = (_tokenSeq + 1) % 0x10000
  return ('%s%08x%08x%04x'):format(prefix, os.time() % 0xffffffff,
    math.abs(nowMs()) % 0xffffffff, _tokenSeq)
end

local function distSq(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return dx * dx + dy * dy + dz * dz
end

local function unsignedHash(value)
  local n = tonumber(value) or 0
  return n < 0 and n + 4294967296 or n
end

local function zonePos(zone)
  return { x = zone.x, y = zone.y, z = zone.z }
end

local function catalogIndex()
  if _catalog then return _catalog end
  local ok, raw = pcall(function() return exports.vhub_conce:getCatalog() end)
  if not ok or type(raw) ~= 'table' then return {} end
  local out = {}
  for model, entry in pairs(raw) do
    if type(model) == 'string' and type(entry) == 'table' then
      out[model:lower()] = {
        name = tostring(entry.nome or model):sub(1, 100),
        category = tostring(entry.categoria or ''):lower(),
        type = tostring(entry.tipo or ''):lower(),
      }
    end
  end
  if next(out) then _catalog = out end
  return out
end

local function canonical(value, state, depth)
  if depth > 6 or state.nodes >= 256 then return false end
  state.nodes = state.nodes + 1
  local function append(chunk)
    if type(chunk) ~= 'string' or state.bytes + #chunk > 4096 then return false end
    state.parts[#state.parts + 1], state.bytes = chunk, state.bytes + #chunk
    return true
  end
  local kind = type(value)
  if kind == 'nil' then return append('n;')
  elseif kind == 'boolean' then return append(value and 'b1;' or 'b0;')
  elseif kind == 'number' then
    if value ~= value or math.abs(value) == math.huge then return false end
    return append(('d%.17g;'):format(value))
  elseif kind == 'string' then
    if #value > 512 then return false end
    return append(('s%d:%s;'):format(#value, value))
  elseif kind == 'table' then
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    if #keys > 128 or not append(('t%d{'):format(#keys)) then return false end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
      local keyText = tostring(key)
      if #keyText > 128 or not append(('k%d:%s='):format(#keyText, keyText))
          or not canonical(value[key], state, depth + 1) then return false end
    end
    return append('};')
  end
  return false
end

local function digest(value)
  local state = { parts = {}, bytes = 0, nodes = 0 }
  if not canonical(value, state, 0) then return nil end
  local raw = table.concat(state.parts)
  local seeds = { 2166136261, 2654435761, 2246822519, 3266489917,
    668265263, 374761393, 1274126177, 42595009 }
  local chunks = {}
  for index, seed in ipairs(seeds) do
    local hash = seed
    for byteIndex = 1, #raw do
      hash = ((hash ~ raw:byte(byteIndex)) * 16777619) & 0xffffffff
    end
    chunks[index] = ('%08x'):format(hash)
  end
  return table.concat(chunks)
end

AddEventHandler('vHub:characterLoad', function(user)
  if user and tonumber(user.source) and tonumber(user.char_id) then
    _sessions[user.source] = { char_id = user.char_id }
  end
end)

AddEventHandler('playerDropped', function()
  local src = source
  local plate = _locksBySrc[src]
  local lock = plate and _locksByPlate[plate] or nil
  if lock and lock.src == src then lock.cancelled = true end
  _sessions[src], _rates[src], _leases[src], _locksBySrc[src] = nil, nil, nil, nil
end)

-- aplica rate limit antes de qualquer trabalho assíncrono
function Core.rateOK(src, eventName)
  local cfg = CFG.rates[eventName]
  if not cfg then return false end
  local now = nowMs()
  _rates[src] = _rates[src] or {}
  local rate = _rates[src][eventName]
  if not rate or (now - rate.ts) > cfg.window then rate = { ts = now, n = 0 } end
  rate.n = rate.n + 1
  _rates[src][eventName] = rate
  return rate.n <= cfg.max
end

function Core.getCharId(src)
  local session = _sessions[src]
  if session then return session.char_id end
  local ok, charId = pcall(function() return exports.vhub:getCharacterId(src) end)
  charId = ok and tonumber(charId) or nil
  if not charId or charId <= 0 or charId % 1 ~= 0 then return nil end
  _sessions[src] = { char_id = charId }
  return charId
end

function Core.canOperate(src, plate)
  local ok, allowed = pcall(function() return exports.vhub_conce:canOperate(src, plate) end)
  return ok and allowed == true
end

function Core.getVehicleState(plate)
  local ok, state = pcall(function() return exports.vhub_conce:getVehicleState(plate) end)
  return ok and state or nil
end

function Core.saveVehicleState(plate, patch, sourceTag)
  local ok, saved = pcall(function()
    return exports.vhub_conce:saveVehicleState(plate, patch, sourceTag)
  end)
  return ok and saved == true
end

function Core.updatePosition(plate, positionJson)
  local ok, saved = pcall(function() return exports.vhub_conce:updatePosition(plate, positionJson) end)
  local count = type(saved) == 'table' and saved.affectedRows or saved
  return ok and (saved == true or (tonumber(count) or 0) > 0)
end

function Core.vehicleMeta(row)
  local model = row and tostring(row.model or ''):lower() or ''
  local entry = catalogIndex()[model] or {}
  return {
    name = entry.name or model,
    category = tostring(row and row.category or entry.category or ''):lower(),
    type = tostring(row and row.vtype or entry.type or ''):lower(),
  }
end

function Core.stageCap(row, sheet)
  local meta = Core.vehicleMeta(row)
  local typeCap = CFG.stage_cap_by_type[meta.type] or 0
  local categoryCap = CFG.stage_cap_by_category[meta.category]
  if categoryCap == nil then categoryCap = typeCap > 0 and CFG.stage_cap_default or 0 end
  local cap = math.min(typeCap, categoryCap)
  local tier = sheet and (sheet.tier_max or sheet.tier)
  local tierCap = tier and CFG.stage_cap_by_tier[tostring(tier)] or nil
  if tierCap then cap = math.min(cap, tierCap) end
  return cap
end

-- ADR #85 F2.5-A: juízo de compatibilidade de UMA peça. Delega ao módulo PURO VHubCustom.Compat
-- (shared/compat.lua — testável offline em tools/test_compat.lua). `class_budget`/stageCap não
-- bloqueiam (viram hint); o gate real é família/conflito/dependência/item/já-instalada. Usado no
-- install/remove (oficina.lua) e no payload de auth (init.lua) — juízo ÚNICO, sem 2ª verdade.
function Core.resolvePartStatus(part, curParts, cap, hasItem)
  return VHubCustom.Compat.resolve(part, curParts, cap, hasItem)
end

-- monta o mapa STATUS por peça do catálogo (glue O(nº peças) sobre Core.resolvePartStatus — juízo
-- ÚNICO). Usado no payload de auth (init.lua) e no estado fresco pós-install/remove (oficina.lua).
-- `cap` já resolvido pelo chamador (Core.stageCap). Item consultado 1×/item (cache local). Não persiste.
function Core.computePartsStatus(src, cap, curParts)
  local catalog = VHubCustom.PartsCatalog
  if not catalog or type(catalog.PARTS) ~= 'table' then return nil end
  local itemCache = {}
  local function hasItem(it)
    if itemCache[it] == nil then
      local ok, has = pcall(function() return exports.vhub_inventory:hasItem(src, it, 1) == true end)
      itemCache[it] = ok and has == true
    end
    return itemCache[it]
  end
  local out = {}
  for _, p in ipairs(catalog.PARTS) do
    out[p.id] = Core.resolvePartStatus(p, curParts, cap, hasItem)
  end
  return out
end

-- valida zona, réplica, placa, modelo, bucket, distância, velocidade e autorização
function Core.validateVehicle(src, domain, plate, netId, zoneId)
  local cid = Core.getCharId(src)
  if not cid then return nil, 'session' end
  local p = U.normalizePlate(plate)
  local nid = U.integer(netId, 1, 65535)
  local zone = _zonesById[zoneId]
  if not p or not nid or not zone or zone.domain ~= domain then return nil, 'shape' end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, 'ped' end
  local entity = NetworkGetEntityFromNetworkId(nid)
  if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
    return nil, 'entity'
  end

  local playerPos, vehiclePos = GetEntityCoords(ped), GetEntityCoords(entity)
  local zPos = zonePos(zone)
  if distSq(playerPos, zPos) > CFG.max_player_zone_dist ^ 2
      or distSq(vehiclePos, zPos) > CFG.max_vehicle_zone_dist ^ 2
      or distSq(playerPos, vehiclePos) > CFG.max_player_vehicle_dist ^ 2 then
    return nil, 'distance'
  end
  local bucket = GetPlayerRoutingBucket(src)
  if bucket ~= GetEntityRoutingBucket(entity) then return nil, 'bucket' end
  if GetEntitySpeed(entity) > CFG.max_service_speed then return nil, 'moving' end
  if U.normalizePlate(GetVehicleNumberPlateText(entity)) ~= p then return nil, 'plate' end
  local driver = GetPedInVehicleSeat(entity, -1)
  if driver and driver ~= 0 and driver ~= ped then return nil, 'occupied' end
  if not Core.canOperate(src, p) then return nil, 'forbidden' end

  local ok, row = pcall(function() return exports.vhub_conce:getVehicle(p) end)
  if not ok or type(row) ~= 'table' or row.status ~= 'out' then return nil, 'state' end
  local model = row.model and unsignedHash(GetHashKey(tostring(row.model))) or 0
  if model == 0 or unsignedHash(GetEntityModel(entity)) ~= model then return nil, 'model' end

  return {
    src = src, char_id = cid, domain = domain, plate = p, net_id = nid,
    entity = entity, bucket = bucket, zone = zone, vehicle = row,
    model_hash = unsignedHash(GetEntityModel(entity)),
  }
end

function Core.issueLease(context)
  local lease = {
    id = token('l'), src = context.src, char_id = context.char_id,
    domain = context.domain, plate = context.plate, net_id = context.net_id,
    bucket = context.bucket, zone_id = context.zone.id, model_hash = context.model_hash,
    expires_at = nowMs() + CFG.service_lease_ms,
  }
  _leases[context.src] = lease
  return lease
end

local function leaseOf(src, domain, leaseId)
  local lease = _leases[src]
  if expired(lease) then _leases[src] = nil; return nil, 'lease_expired' end
  if type(leaseId) ~= 'string' or lease.id ~= leaseId or lease.domain ~= domain
      or lease.char_id ~= Core.getCharId(src) then return nil, 'lease' end
  return lease
end

function Core.validateLease(src, domain, leaseId)
  local lease, err = leaseOf(src, domain, leaseId)
  if not lease then return nil, err end
  local context, why = Core.validateVehicle(src, lease.domain, lease.plate, lease.net_id, lease.zone_id)
  if not context or context.bucket ~= lease.bucket or context.model_hash ~= lease.model_hash then
    return nil, why or 'vehicle_changed'
  end
  context.lease = lease
  return context
end

local function acquireLock(src, plate)
  local current = _locksByPlate[plate]
  local srcPlate = _locksBySrc[src]
  if current or (srcPlate and srcPlate ~= plate) then return nil end
  local lock = { token = token('k'), src = src, cancelled = false }
  _locksByPlate[plate], _locksBySrc[src] = lock, plate
  return lock.token
end

function Core.releaseLock(src, plate, lockToken)
  local lock = _locksByPlate[plate]
  if lock and lock.src == src and lock.token == lockToken then
    _locksByPlate[plate] = nil
    if _locksBySrc[src] == plate then _locksBySrc[src] = nil end
  end
end

function Core.lockValid(context, lockToken)
  if type(context) ~= 'table' then return false end
  local lock = _locksByPlate[context.plate]
  if not lock or lock.src ~= context.src or lock.token ~= lockToken or lock.cancelled then return false end
  local fresh = Core.validateLease(context.src, context.domain, context.lease.id)
  if not fresh then return false end
  lock = _locksByPlate[context.plate]
  if not lock or lock.src ~= context.src or lock.token ~= lockToken or lock.cancelled then return false end
  if fresh.char_id ~= context.char_id or fresh.plate ~= context.plate
      or fresh.net_id ~= context.net_id or fresh.bucket ~= context.bucket
      or fresh.model_hash ~= context.model_hash then return false end
  context.entity, context.vehicle, context.zone = fresh.entity, fresh.vehicle, fresh.zone
  return true
end

function Core.beginMutation(src, domain, leaseId)
  if not SQL.ready then return nil, nil, 'storage' end
  local lease, err = leaseOf(src, domain, leaseId)
  if not lease then return nil, nil, err end
  local lockToken = acquireLock(src, lease.plate)
  if not lockToken then return nil, nil, 'busy' end
  local context, why = Core.validateLease(src, domain, leaseId)
  if not context then
    Core.releaseLock(src, lease.plate, lockToken)
    return nil, nil, why
  end
  return context, lockToken
end

function Core.requestId(value)
  if type(value) ~= 'string' or #value < 8 or #value > 16 then return nil end
  return value:match('^[%w_-]+$') and value or nil
end

function Core.fingerprint(value)
  return digest(value)
end

local function decoded(value)
  if type(value) ~= 'string' or value == '' then return {} end
  local ok, result = pcall(json.decode, value)
  return ok and type(result) == 'table' and result or {}
end

local function sameSubset(current, expected, depth)
  if type(expected) ~= 'table' then
    if type(expected) == 'number' then return tonumber(current) == expected end
    return current == expected
  end
  if type(current) ~= 'table' or depth >= 6 then return false end
  if next(expected) == nil then return next(current) == nil end
  for key, value in pairs(expected) do
    local actual = current[key]
    if actual == nil then actual = current[tostring(key)] end
    if not sameSubset(actual, value, depth + 1) then return false end
  end
  return true
end

-- compara recursivamente apenas os campos declarados no estado esperado.
function Core.sameSubset(current, expected)
  return sameSubset(current, expected, 0)
end

-- prepara a saga, efetua ou retoma a cobrança e devolve a operação durável.
function Core.commitPayment(context, action, requestId, amount, payload, before, after)
  local request = Core.requestId(requestId)
  local domainCode, actionCode = DOMAIN_CODE[context.domain], ACTION_CODE[action]
  if not request or not domainCode or not actionCode then
    return false, nil, 'invalid_request'
  end
  local semanticDigest = Core.fingerprint({
    char_id = context.char_id, domain = context.domain, plate = context.plate,
    model_hash = context.model_hash, action = action, request_id = request,
    payload = payload,
  })
  if not semanticDigest then return false, nil, 'invalid_payload' end
  local operationId = ('vc:%d:%s:%08x:%s:%s:%s:%s'):format(context.char_id,
    context.plate:gsub(' ', '_'), context.model_hash, domainCode, actionCode, request,
    semanticDigest:sub(1, 8))
  if #operationId > 64 then return false, nil, 'invalid_request' end
  local requestKey = operationId:sub(1, -10)
  local operation, prepareErr = SQL.prepare({
    operation_id = operationId, request_key = requestKey, source_id = context.src,
    char_id = context.char_id,
    plate = context.plate, model_hash = context.model_hash, domain = context.domain,
    action = action, semantic_digest = semanticDigest, amount = math.max(0, math.floor(amount or 0)),
    payload = payload, before = before, after = after,
  })
  if not operation then return false, operationId, prepareErr end
  local persistedAmount = tonumber(operation.amount) or 0
  if operation.state == 'applied' then
    return true, operationId, nil, true, false, operation
  end
  if operation.state == 'refunded' then return false, operationId, 'refunded' end

  local claimToken = token('o')
  if not SQL.claim(operationId, claimToken) then return false, operationId, 'busy' end
  _operationClaims[operationId] = claimToken
  operation.claim_token = claimToken

  if operation.state == 'charged' then
    return true, operationId, nil, false, persistedAmount > 0, operation
  end
  if operation.state ~= 'prepared' then return false, operationId, 'conflict' end

  if persistedAmount <= 0 then
    if not SQL.markCharged(operationId, claimToken) then
      _operationClaims[operationId] = nil
      return false, operationId, 'storage'
    end
    operation.state = 'charged'
    return true, operationId, nil, false, false, operation
  end
  local reason = ('custom.%s:%s'):format(action, semanticDigest)
  local called, result = pcall(function()
    return exports.vhub_money:commitPayment(context.src, persistedAmount, operationId, reason)
  end)
  if not called or type(result) ~= 'table' or result.ok ~= true then
    local paymentError = type(result) == 'table' and result.err or 'storage'
    if paymentError == 'insufficient' then
      SQL.markRefunded(operationId, claimToken)
    else
      SQL.releaseClaim(operationId, claimToken)
    end
    _operationClaims[operationId] = nil
    return false, operationId, paymentError
  end
  if not SQL.markCharged(operationId, claimToken) then
    _operationClaims[operationId] = nil
    return false, operationId, 'storage'
  end
  operation.state = 'charged'
  return true, operationId, nil, false, true, operation
end

-- estorna exatamente o débito registrado, com retry curto e limitado.
function Core.refundPayment(operationId)
  if not operationId then return true end
  local lastError = 'storage'
  for attempt = 1, 3 do
    local called, result = pcall(function() return exports.vhub_money:refundPayment(operationId) end)
    if called and type(result) == 'table' and result.ok == true then return true end
    if called and type(result) == 'table' then lastError = result.err or lastError end
    if attempt < 3 then Citizen.Wait(attempt * 100) end
  end
  VHubCustom.log('[CRITICAL] refund falhou | operation_id=' .. tostring(operationId))
  return false, lastError
end

-- compensa a etapa financeira e fecha a saga como refunded.
function Core.compensatePayment(operationId, replayed, charged)
  local claimToken = _operationClaims[operationId]
  if not claimToken then return false, 'claim_lost' end
  if not SQL.claim(operationId, claimToken) then return false, 'claim_lost' end
  if charged ~= true then
    local closed = SQL.markRefunded(operationId, claimToken)
    if closed then _operationClaims[operationId] = nil end
    return closed, closed and 'no_charge' or 'ledger_failed'
  end
  if replayed == true then return false, 'replay_charge_preserved' end
  local refunded = Core.refundPayment(operationId)
  if refunded and SQL.markRefunded(operationId, claimToken) then
    _operationClaims[operationId] = nil
    return true, 'refunded'
  end
  return false, refunded and 'ledger_failed' or 'refund_failed'
end

-- renova e confirma o claim antes de qualquer mutação externa.
function Core.refreshOperation(operationId)
  local claimToken = _operationClaims[operationId]
  return claimToken ~= nil and SQL.claim(operationId, claimToken) == true
end

-- fecha como applied uma mutação já confirmada no dono do estado.
function Core.completeOperation(operationId)
  local claimToken = _operationClaims[operationId]
  if not claimToken then return false end
  if not SQL.claim(operationId, claimToken) then return false end
  for attempt = 1, 3 do
    local called, completed = pcall(SQL.markApplied, operationId, claimToken)
    if called and completed == true then
      _operationClaims[operationId] = nil
      return true
    end
    if attempt < 3 then Citizen.Wait(attempt * 100) end
  end
  VHubCustom.log('[CRITICAL] saga aplicada sem fechamento | operation_id=' .. tostring(operationId))
  return false
end

function Core.auditVehicle(context, action, operationId, before, after, result)
  local payload = {
    operation_id = operationId, before = before, after = after, result = result,
  }
  local called, saved = pcall(function()
    return exports.vhub_conce:appendVehicleAudit(context.src, context.char_id, context.plate,
      'custom.' .. action, payload)
  end)
  if not called or saved ~= true then
    VHubCustom.log(('[CRITICAL] auditoria falhou | plate=%s | action=%s | operation_id=%s')
      :format(tostring(context.plate), tostring(action), tostring(operationId)))
    return false
  end
  return true
end

local function operationApplied(row)
  local after = decoded(row.after_json)
  if row.action == 'nitro_kit' then
    local state = VHubCustom.nitroGetInternal(row.plate)
    return type(state) == 'table' and state.kit == true
  end
  if row.action == 'tow' then
    local ok, vehicle = pcall(function() return exports.vhub_conce:getVehicle(row.plate) end)
    local position = ok and type(vehicle) == 'table' and decoded(vehicle.position) or nil
    if type(position) ~= 'table' then return false end
    local dx = (tonumber(position.x) or math.huge) - (tonumber(after.x) or 0)
    local dy = (tonumber(position.y) or math.huge) - (tonumber(after.y) or 0)
    local dz = (tonumber(position.z) or math.huge) - (tonumber(after.z) or 0)
    return dx * dx + dy * dy + dz * dz <= 4.0
  end
  local state = Core.getVehicleState(row.plate)
  return type(state) == 'table' and sameSubset(state, after, 0)
end

-- confirma se o estado autoritativo já contém o resultado persistido da saga.
function Core.operationApplied(row)
  return type(row) == 'table' and operationApplied(row) or false
end

local function auditRecovery(row, result)
  Core.auditVehicle({ src = 0, char_id = tonumber(row.char_id), plate = row.plate },
    row.action, row.operation_id, decoded(row.before_json), decoded(row.after_json), result)
end

local function recoverOperation(row)
  local claimToken = token('r')
  if not SQL.claim(row.operation_id, claimToken) then return end
  if row.state == 'charged' and operationApplied(row) then
    if SQL.markApplied(row.operation_id, claimToken) then auditRecovery(row, 'recovered_applied') end
    return
  end

  local amount = tonumber(row.amount) or 0
  if amount > 0 then
    local called, result = pcall(function()
      return exports.vhub_money:refundPayment(row.operation_id)
    end)
    if not called or type(result) ~= 'table'
        or (result.ok ~= true and result.err ~= 'not_found') then
      SQL.releaseClaim(row.operation_id, claimToken)
      return
    end
  end
  if SQL.markRefunded(row.operation_id, claimToken) then auditRecovery(row, 'recovered_refunded') end
end

-- inicia recovery limitado: 20/30s; claim ativo por 300s nunca é disputado.
function Core.startRecovery()
  Citizen.CreateThread(function()
    while _running do
      local called, rows = pcall(SQL.recoverable, os.time() - 90, 20)
      if called and type(rows) == 'table' then
        for _, row in ipairs(rows) do
          if not _running then break end
          pcall(recoverOperation, row)
        end
      end
      Citizen.Wait(30000)
    end
  end)
end

-- encerra o worker de reconciliação no stop do resource.
function Core.stop()
  _running = false
end

function Core.vehicleHasOccupants(entity)
  local seats = 32
  local ok, modelSeats = pcall(GetVehicleModelNumberOfSeats, GetEntityModel(entity))
  if ok and tonumber(modelSeats) then seats = math.min(32, math.max(1, math.floor(modelSeats))) end
  for seat = -1, seats - 2 do
    local read, ped = pcall(GetPedInVehicleSeat, entity, seat)
    if read and ped and ped ~= 0 then return true end
  end
  return false
end

function Core.notify(src, message, kind)
  TriggerClientEvent(VHubCustom.E.NOTIFY, src, tostring(message or ''), kind or 'info')
end

function Core.dbg(src, message)
  if not CFG.debug then return end
  Core.notify(src, '[DEBUG] ' .. tostring(message), 'info')
end

function Core.log(plate, action, charId, extra)
  local parts = { ('%s | plate=%s | cid=%s'):format(action, tostring(plate), tostring(charId)) }
  if type(extra) == 'table' then
    for key, value in pairs(extra) do parts[#parts + 1] = key .. '=' .. tostring(value) end
  end
  VHubCustom.log(table.concat(parts, ' | '))
end
