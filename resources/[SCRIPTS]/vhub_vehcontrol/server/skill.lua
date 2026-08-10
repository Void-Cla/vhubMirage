-- server/skill.lua — escritor único e serializado da distribuição de handling
---@diagnostic disable: undefined-global, lowercase-global

local TR = VHubVeh.TR
local E  = VHubVeh.E

local TOOLBOX_ITEM   = 'caixadeferramentas'
local RATE_WINDOW_MS = 5000
local RESERVATION_TTL_MS = 30000
local _rate          = {}
local _locks         = {}
local _lockBySrc     = {}
local _reservations  = {}
local _lockSequence  = 0

local function logCritical(message, meta)
  pcall(function() exports.vhub:log('error', 'vhub_vehcontrol', message, meta) end)
end

local function rateOK(src)
  local now = GetGameTimer()
  if _rate[src] and (now - _rate[src]) < RATE_WINDOW_MS then return false end
  _rate[src] = now
  return true
end

local function normalizePlate(value)
  if type(value) ~= 'string' then return nil end
  local plate = value:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  if not plate or #plate < 2 or #plate > 8
      or not plate:match('^[A-Z0-9][A-Z0-9 ]*[A-Z0-9]$') then return nil end
  return plate
end

local function unsignedHash(value)
  local number = tonumber(value) or 0
  return number < 0 and number + 4294967296 or number
end

local function canOperate(src, plate)
  local ok, allowed = pcall(function() return exports.vhub_conce:canOperate(src, plate) end)
  return ok and allowed == true
end

local function resolveToolboxVehicle(src, netId, plate)
  local entity, normalized = VHubVeh.resolveAccessibleVehicle(src, netId, plate,
    tonumber(Config.distance) or 5.0)
  if not entity or not normalized then return nil end
  local ok, row = pcall(function() return exports.vhub_conce:getVehicle(normalized) end)
  if not ok or type(row) ~= 'table' or row.status ~= 'out' or type(row.model) ~= 'string' then return nil end
  local expected = unsignedHash(GetHashKey(row.model))
  if expected == 0 or unsignedHash(GetEntityModel(entity)) ~= expected then return nil end
  return normalized
end

local function consumeToolbox(src)
  local ok, has = pcall(function() return exports.vhub_inventory:hasItem(src, TOOLBOX_ITEM, 1) end)
  if not ok or has ~= true then return false end
  local took, result = pcall(function() return exports.vhub_inventory:takeItem(src, TOOLBOX_ITEM, 1) end)
  return took and result == true
end

local function refundToolbox(src)
  local ok, result = pcall(function() return exports.vhub_inventory:giveItem(src, TOOLBOX_ITEM, 1) end)
  return ok and result == true
end

local function copyAlloc(alloc)
  local out = {}
  for _, axis in ipairs(TR.AXES) do out[axis] = alloc[axis] end
  return out
end

local function sameAlloc(a, b)
  if type(a) ~= 'table' then return false end
  for _, axis in ipairs(TR.AXES) do
    if tonumber(a[axis]) ~= tonumber(b[axis]) then return false end
  end
  return true
end

local function acquireLock(src, plate)
  if _locks[plate] or _lockBySrc[src] then return nil end
  _lockSequence = (_lockSequence + 1) % 0x1000000
  local token = ('%08x:%06x'):format(math.abs(GetGameTimer()) % 0xffffffff, _lockSequence)
  _locks[plate] = { src = src, token = token, cancelled = false }
  _lockBySrc[src] = plate
  return token
end

local function lockValid(src, plate, token)
  local lock = _locks[plate]
  return lock ~= nil and lock.src == src and lock.token == token and lock.cancelled ~= true
end

local function releaseLock(src, plate, token)
  local lock = _locks[plate]
  if lock and lock.src == src and lock.token == token then
    _locks[plate] = nil
    if _lockBySrc[src] == plate then _lockBySrc[src] = nil end
  end
end

local function runLocked(src, plate, operation)
  local token = acquireLock(src, plate)
  if not token then return { ok = false, err = 'busy', msg = 'Veículo em outra operação.' } end
  local called, result = pcall(operation, token)
  releaseLock(src, plate, token)
  if not called then
    logCritical('Recalibracao interrompida.', { src = src, plate = plate })
    return { ok = false, err = 'internal', msg = 'Falha interna na calibração.' }
  end
  return type(result) == 'table' and result
    or { ok = false, err = 'internal', msg = 'Falha interna na calibração.' }
end

-- valida identidade, autorização, budget e invariantes; não cobra nem persiste
local function prepare(src, plate, alloc)
  src = tonumber(src)
  local normalized = normalizePlate(plate)
  if not src or src <= 0 or not normalized or type(alloc) ~= 'table' then
    return nil, 'invalid', 'Dados inválidos.'
  end
  if not canOperate(src, normalized) then
    return nil, 'forbidden', 'Sem autorização para este veículo.'
  end
  local base = VHubVeh.p1Byplate(normalized)
  if not base then return nil, 'unsupported', 'Este veículo não suporta calibração.' end

  local state
  pcall(function() state = exports.vhub_conce:getVehicleState(normalized) end)
  local customization = state and type(state.customization) == 'table' and state.customization or {}
  local budget = TR.budgetOf(base, customization.mods, customization.turbo)
  if not budget then return nil, 'budget', 'Falha ao calcular o limite de pontos.' end

  local clean = copyAlloc(alloc)
  local valid, why = TR.validateAlloc(clean, budget)
  if not valid then
    return nil, 'allocation', 'Distribuição inválida (' .. tostring(why) .. ').'
  end
  return {
    src = src, plate = normalized, alloc = clean,
    before = type(customization.handling) == 'table' and copyAlloc(customization.handling) or nil,
    replayed = sameAlloc(customization.handling, clean),
  }
end

local function persist(prepared)
  if prepared.replayed then
    return { ok = true, replayed = true, sheet = VHubVeh.sheetOf(prepared.plate) }
  end
  local ok, saved = pcall(function()
    return exports.vhub_conce:saveVehicleState(prepared.plate,
      { customization = { handling = prepared.alloc } }, 'handling')
  end)
  if not ok or saved ~= true then
    return { ok = false, err = 'storage', msg = 'Erro ao salvar a calibração.' }
  end
  return { ok = true, replayed = false, sheet = VHubVeh.sheetOf(prepared.plate) }
end

-- reserva o lock antes da cobrança; commit/cancel encerram a reserva
function VHubVeh.reserveWorkshopRecalibration(src, plate, alloc)
  src = tonumber(src)
  local normalized = normalizePlate(plate)
  if not normalized then return { ok = false, err = 'invalid', msg = 'Dados inválidos.' } end
  local token = acquireLock(src, normalized)
  if not token then return { ok = false, err = 'busy', msg = 'Veículo em outra operação.' } end
  local called, prepared, err, msg = pcall(prepare, src, normalized, alloc)
  if not called or not prepared or not lockValid(src, normalized, token) then
    releaseLock(src, normalized, token)
    return { ok = false, err = called and (err or 'cancelled') or 'internal',
      msg = called and (msg or 'Sessão encerrada.') or 'Falha interna na calibração.' }
  end
  local reservation = { src = src, plate = normalized, prepared = prepared, state = 'reserved' }
  _reservations[token] = reservation
  SetTimeout(RESERVATION_TTL_MS, function()
    if _reservations[token] == reservation and reservation.state == 'reserved' then
      _reservations[token] = nil
      releaseLock(src, normalized, token)
    end
  end)
  return { ok = true, token = token, replayed = prepared.replayed,
    before = prepared.before, alloc = prepared.alloc }
end

function VHubVeh.commitWorkshopRecalibration(src, token)
  src = tonumber(src)
  local reservation = type(token) == 'string' and _reservations[token] or nil
  if not reservation or reservation.src ~= src then return { ok = false, err = 'reservation' } end
  reservation.state = 'committing'
  local valid = lockValid(src, reservation.plate, token)
  if valid then valid = canOperate(src, reservation.plate) end
  if valid then valid = lockValid(src, reservation.plate, token) end
  local called, result = true, nil
  if valid then called, result = pcall(persist, reservation.prepared) end
  _reservations[token] = nil
  releaseLock(src, reservation.plate, token)
  if not valid then return { ok = false, err = 'cancelled', msg = 'Sessão encerrada.' } end
  return called and result or { ok = false, err = 'internal', msg = 'Falha interna na calibração.' }
end

function VHubVeh.cancelWorkshopRecalibration(src, token)
  src = tonumber(src)
  local reservation = type(token) == 'string' and _reservations[token] or nil
  if not reservation or reservation.src ~= src then return false end
  _reservations[token] = nil
  releaseLock(src, reservation.plate, token)
  return true
end

-- porta pública de rede: caixa de ferramentas com prova física completa
RegisterNetEvent(E.RECALIBRATE)
AddEventHandler(E.RECALIBRATE, function(netId, plate, alloc)
  local src = source
  local function reply(result)
    TriggerClientEvent(E.RECAL_DONE, src, result.ok == true, result.msg or '',
      result.ok and 'success' or 'error', result.ok and result.sheet or nil)
  end

  if not rateOK(src) then return reply({ ok = false, msg = 'Aguarde um instante.' }) end
  local normalized = resolveToolboxVehicle(src, netId, plate)
  if not normalized then return reply({ ok = false, err = 'vehicle', msg = 'Veículo inválido ou distante.' }) end

  local toolboxConsumed = false
  local result = runLocked(src, normalized, function(token)
    local prepared, err, msg = prepare(src, normalized, alloc)
    if not prepared then return { ok = false, err = err, msg = msg } end
    if prepared.replayed then return persist(prepared) end
    if not consumeToolbox(src) then
      return { ok = false, err = 'item', msg = 'Você precisa de uma Caixa de Ferramentas.' }
    end
    toolboxConsumed = true

    local physicalPlate = resolveToolboxVehicle(src, netId, normalized)
    if not lockValid(src, normalized, token) or physicalPlate ~= normalized
        or not lockValid(src, normalized, token) then
      local refunded = refundToolbox(src)
      if refunded then toolboxConsumed = false end
      if not refunded then
        logCritical('Estorno da caixa de ferramentas falhou.', { src = src, plate = normalized })
      end
      return { ok = false, err = 'cancelled', msg = refunded and 'Operação cancelada; item devolvido.'
        or 'Falha crítica no estorno do item.' }
    end

    local persisted = persist(prepared)
    if not persisted.ok then
      local refunded = refundToolbox(src)
      if refunded then toolboxConsumed = false end
      if not refunded then
        logCritical('Estorno da caixa de ferramentas falhou.', { src = src, plate = normalized })
      end
      return persisted
    end
    persisted.msg = 'Veículo recalibrado!'
    return persisted
  end)
  if result.err == 'internal' and toolboxConsumed then
    if not refundToolbox(src) then
      logCritical('Estorno da caixa falhou apos excecao.', { src = src, plate = normalized })
    end
  end
  reply(result)
end)

-- ============================================================
-- REFRESH SHEET — push live da ficha ao motorista após mudança na placa
-- ============================================================
-- Chamado pelo WORKER que persistiu (vhub_custom: bennys/oficina) DEPOIS de saveVehicleState.
-- Gated default-deny (só vhub_custom). Reenvia a ficha recomposta SÓ para o src indicado
-- (o dono que fez a operação); o client filtra por placa e só aplica se dirige aquela placa.
-- Nunca -1 (R5). Se o alvo não está dirigindo, o BECAME_DRIVER reaplica quando ele entrar.
exports('refreshSheet', function(plate, targetSrc)
  if GetInvokingResource() ~= 'vhub_custom' then return false end
  local p   = normalizePlate(plate)
  local tgt = tonumber(targetSrc)
  if not p or not tgt or tgt <= 0 then return false end
  local nm; pcall(function() nm = GetPlayerName(tgt) end)
  if not nm or nm == '' then return false end          -- alvo desconectado
  local sheet = VHubVeh.sheetOf(p)
  if type(sheet) ~= 'table' then return false end       -- carro sem p1 → nada a aplicar
  TriggerClientEvent(E.SHEET_UPDATED, tgt, p, sheet)
  return true
end)


AddEventHandler('playerDropped', function()
  local src = source
  local plate = _lockBySrc[src]
  local lock = plate and _locks[plate] or nil
  local reservation = lock and _reservations[lock.token] or nil
  if reservation and reservation.state == 'reserved' then
    _reservations[lock.token] = nil
    releaseLock(src, plate, lock.token)
  elseif lock and lock.src == src then
    lock.cancelled = true
  end
  _lockBySrc[src], _rate[src] = nil, nil
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= 'vhub_custom' then return end
  for token, reservation in pairs(_reservations) do
    _reservations[token] = nil
    releaseLock(reservation.src, reservation.plate, token)
  end
end)
