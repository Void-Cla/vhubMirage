-- server/admin.lua  exports administrativos para vhub_admin
-- Todos os exports validam invoker (s  resources confi veis chamam).
-- Permiss o de jogador (uid=1, grupo, ACE)   responsabilidade do vhub_admin.
-- Aqui apenas executamos e logamos.
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local U    = VHubGarage.U
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

local TRUSTED = {
  ['vhub_admin'] = true,
  ['vhub']       = true,
}

local function invoker_ok()
  local c = GetInvokingResource()
  if not c then return true end   -- chamada interna do pr prio resource
  return TRUSTED[c] == true
end

-- helper p/ rodar SQL dentro de thread (Citizen.Await)  retorna future
local function inThread(fn)
  Citizen.CreateThread(function() pcall(fn) end)
end

-- ============================================================================
-- LEITURA
-- ============================================================================

-- adminStats()  panorama da frota
exports('adminStats', function()
  if not invoker_ok() then return nil end
  local p = promise.new()
  Citizen.CreateThread(function()
    local total = SQL.scalar('SELECT COUNT(*) FROM vhub_vehicles', {}) or 0
    local rows = SQL.query([[
      SELECT status, COUNT(*) AS n FROM vhub_vehicles GROUP BY status
    ]], {}) or {}
    local by_status = {}
    for _, r in ipairs(rows) do by_status[r.status] = r.n end
    rows = SQL.query([[
      SELECT vtype, COUNT(*) AS n FROM vhub_vehicles GROUP BY vtype
    ]], {}) or {}
    local by_type = {}
    for _, r in ipairs(rows) do by_type[r.vtype] = r.n end
    local active_auctions = SQL.scalar(
      'SELECT COUNT(*) FROM vhub_auctions WHERE status = ?', { 'active' }) or 0
    local active_impound = SQL.scalar(
      'SELECT COUNT(*) FROM vhub_impound WHERE released_at IS NULL', {}) or 0
    local active_rental = SQL.scalar(
      'SELECT COUNT(*) FROM vhub_vehicles WHERE status = ?', { 'rental' }) or 0
    p:resolve({
      total = total, by_status = by_status, by_type = by_type,
      active_auctions = active_auctions,
      active_impound  = active_impound,
      active_rental   = active_rental,
    })
  end)
  return Citizen.Await(p)
end)

-- adminListVehicles({ status?, vtype?, char_id?, search? }, limit, offset)
exports('adminListVehicles', function(filter, limit, offset)
  if not invoker_ok() then return {} end
  filter = filter or {}
  limit  = tonumber(limit)  or 100
  offset = tonumber(offset) or 0
  if limit > 500 then limit = 500 end

  local p = promise.new()
  Citizen.CreateThread(function()
    local wheres, args = {}, {}
    if filter.status  then wheres[#wheres+1] = 'status = ?';  args[#args+1] = filter.status  end
    if filter.vtype   then wheres[#wheres+1] = 'vtype = ?';   args[#args+1] = filter.vtype   end
    if filter.char_id then wheres[#wheres+1] = 'char_id = ?'; args[#args+1] = tonumber(filter.char_id) end
    if filter.search then
      wheres[#wheres+1] = '(plate LIKE ? OR model LIKE ?)'
      args[#args+1] = '%' .. filter.search .. '%'
      args[#args+1] = '%' .. filter.search .. '%'
    end
    local clause = #wheres > 0 and (' WHERE ' .. table.concat(wheres, ' AND ')) or ''
    args[#args+1] = limit
    args[#args+1] = offset
    local sql = 'SELECT * FROM vhub_vehicles' .. clause .. ' ORDER BY updated_at DESC LIMIT ? OFFSET ?'
    p:resolve(SQL.query(sql, args) or {})
  end)
  return Citizen.Await(p)
end)

-- adminGetVehicle(plate)  detalhe completo
exports('adminGetVehicle', function(plate)
  if not invoker_ok() then return nil end
  local p = U.normalizePlate(plate); if not p then return nil end
  local promiseObj = promise.new()
  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p)
    if not v then promiseObj:resolve(nil); return end
    promiseObj:resolve({
      vehicle = v,
      keys    = SQL:listKeys(p) or {},
      impound = SQL:impoundGetActive(p),
      auction = SQL:getAuctionByPlate(p),
      logs    = SQL.query(
        'SELECT * FROM vhub_vehicle_log WHERE plate = ? ORDER BY id DESC LIMIT 50',
        { p }) or {},
    })
  end)
  return Citizen.Await(promiseObj)
end)

exports('adminListByOwner', function(char_id)
  if not invoker_ok() then return {} end
  local cid = tonumber(char_id); if not cid then return {} end
  local p = promise.new()
  Citizen.CreateThread(function() p:resolve(SQL:listByOwner(cid) or {}) end)
  return Citizen.Await(p)
end)

exports('adminListAuctions', function(status)
  if not invoker_ok() then return {} end
  local p = promise.new()
  Citizen.CreateThread(function()
    local sql, args = 'SELECT * FROM vhub_auctions', {}
    if status then sql = sql .. ' WHERE status = ?'; args = { status } end
    sql = sql .. ' ORDER BY created_at DESC LIMIT 200'
    p:resolve(SQL.query(sql, args) or {})
  end)
  return Citizen.Await(p)
end)

exports('adminListImpound', function()
  if not invoker_ok() then return {} end
  local p = promise.new()
  Citizen.CreateThread(function() p:resolve(SQL:impoundList() or {}) end)
  return Citizen.Await(p)
end)

exports('adminListLogs', function(plate, limit)
  if not invoker_ok() then return {} end
  limit = tonumber(limit) or 100; if limit > 500 then limit = 500 end
  local p = promise.new()
  Citizen.CreateThread(function()
    local rows
    if plate then
      local pp = U.normalizePlate(plate)
      rows = SQL.query(
        'SELECT * FROM vhub_vehicle_log WHERE plate = ? ORDER BY id DESC LIMIT ?',
        { pp, limit })
    else
      rows = SQL.query(
        'SELECT * FROM vhub_vehicle_log ORDER BY id DESC LIMIT ?', { limit })
    end
    p:resolve(rows or {})
  end)
  return Citizen.Await(p)
end)

-- adminFindOrphans()  ve culos com char_id NULL ou inv lido (sem identity)
exports('adminFindOrphans', function()
  if not invoker_ok() then return {} end
  local p = promise.new()
  Citizen.CreateThread(function()
    p:resolve(SQL.query([[
      SELECT * FROM vhub_vehicles
       WHERE char_id IS NULL
          OR char_id NOT IN (SELECT id FROM vh_characters)
       LIMIT 500
    ]], {}) or {})
  end)
  return Citizen.Await(p)
end)

-- ============================================================================
-- ESCRITA / OPERA  ES
-- ============================================================================

local function actorOf(actor_src)
  return actor_src and Core:getCharId(actor_src) or nil
end

-- Cria ve culo grat  para um char (admin give)
exports('adminGiveVehicle', function(char_id, model, placa_custom, actor_src)
  if not invoker_ok() then return false end
  local cid = tonumber(char_id); if not cid then return false end
  local entry = VHubGarage.catalog[model]; if not entry then return false end
  local p = promise.new()
  Citizen.CreateThread(function()
    local plate = Core:newPlate(placa_custom)
    if not plate then p:resolve(false); return end
    local now = os.time()
    SQL:createVehicle({
      plate = plate, model = model, vtype = entry.tipo,
      category = entry.categoria, char_id = cid, status = 'garage',
      customization = U.jenc({ model = model }), locked = false,
      ipva_paid_until = now + CFG.ipva_dias * 86400,
      purchase_price = 0, purchase_at = now, last_seen_at = now,
    })
    SQL:grantKey(plate, cid, 'owner', cid, nil)
    -- se o dono est  online, entrega chave-item; sen o, fica para pr ximo login
    for src, u in pairs(Core.sessions) do
      if u.char_id == cid then Core.giveKeyItem(src, plate); break end
    end
    Core:log(plate, 'admin_give', actorOf(actor_src),
      { char_id = cid, model = model })
    p:resolve(plate)
  end)
  return Citizen.Await(p)
end)

-- Transfer ncia for ada
exports('adminTransfer', function(plate, new_char_id, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  local cid = tonumber(new_char_id); if not cid then return false end
  inThread(function()
    local v = SQL:getVehicle(pp); if not v then return end
    -- toma chave-item do antigo dono se online
    for src, u in pairs(Core.sessions) do
      if u.char_id == v.char_id then Core.takeKeyItem(src, pp); break end
    end
    exports.vhub_conce:transferOwner(pp, cid)   -- char_id + owner antigo/novo (autoridade unica)
    for src, u in pairs(Core.sessions) do
      if u.char_id == cid then Core.giveKeyItem(src, pp); break end
    end
    Core:log(pp, 'admin_transfer', actorOf(actor_src),
      { from = v.char_id, to = cid })
  end)
  return true
end)

-- Remover ve culo
exports('adminDelete', function(plate, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  inThread(function()
    local v = SQL:getVehicle(pp); if not v then return end
    -- toma chave-item do dono se online
    for src, u in pairs(Core.sessions) do
      if u.char_id == v.char_id then Core.takeKeyItem(src, pp); break end
    end
    -- prontu rio morre junto no deleteVehicle  nada a persistir antes
    SQL:deleteVehicle(pp)
    TriggerClientEvent(E.DO_DESPAWN, -1, pp)
    Core:log(pp, 'admin_delete', actorOf(actor_src), { char_id = v.char_id })
  end)
  return true
end)

-- For ar status (garage/out/impound/auction/rental/sold)
exports('adminSetStatus', function(plate, status, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  if not status then return false end
  inThread(function()
    SQL:updateStatus(pp, status)
    Core:log(pp, 'admin_set_status', actorOf(actor_src), { status = status })
  end)
  return true
end)

-- Reparar grat
exports('adminRepair', function(plate, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  inThread(function()
    -- reparo TRUSTED no prontu rio (a vers o antiga mutava C PIA do CORE = no-op);
    -- broadcast DO_REPAIR: quem tiver a entidade + controle conserta a viva (raro/admin)
    pcall(function() exports.vhub_conce:repairVehicleState(pp) end)
    TriggerClientEvent(E.DO_REPAIR, -1, pp)
    Core:log(pp, 'admin_repair', actorOf(actor_src), {})
  end)
  return true
end)

-- Renovar IPVA gratuito
exports('adminRenewIpva', function(plate, dias, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  local d = tonumber(dias) or CFG.ipva_dias
  inThread(function()
    local v = SQL:getVehicle(pp); if not v then return end
    local base = math.max(os.time(), tonumber(v.ipva_paid_until) or 0)
    SQL:updateIpva(pp, base + d * 86400)
    Core:log(pp, 'admin_ipva', actorOf(actor_src), { dias = d })
  end)
  return true
end)

-- Liberar do p tio (gratuito)
exports('adminReleaseImpound', function(plate, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  inThread(function()
    local imp = SQL:impoundGetActive(pp); if not imp then return end
    SQL:impoundRelease(imp.id, actorOf(actor_src))
    SQL:updateStatus(pp, 'garage')
    Core:log(pp, 'admin_release_impound', actorOf(actor_src),
      { id = imp.id, fee = imp.fee })
  end)
  return true
end)

-- Cancelar leil o (a transacao/escrow/broadcast e do vhub_ferinha desde a FASE 4)
exports('adminCancelAuction', function(auction_id, actor_src)
  if not invoker_ok() then return false end
  local id = tonumber(auction_id); if not id then return false end
  inThread(function()
    exports.vhub_ferinha:cancelAuction(id, actorOf(actor_src))
  end)
  return true
end)

-- Estoque (admin set)
exports('adminSetStock', function(model, qty, custom_price, actor_src)
  if not invoker_ok() then return false end
  if not VHubGarage.catalog[model] then return false end
  inThread(function()
    SQL:stockSet(model, qty, custom_price)
    Core:log('STOCK', 'admin_set_stock', actorOf(actor_src),
      { model = model, qty = qty, custom_price = custom_price })
  end)
  return true
end)

-- Conceder chave (force)
exports('adminGrantKey', function(plate, char_id, kind, days, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  local cid = tonumber(char_id); if not cid then return false end
  local d = tonumber(days)
  local exp = d and (os.time() + d * 86400) or nil
  inThread(function()
    SQL:grantKey(pp, cid, kind or 'shared', actorOf(actor_src), exp)
    -- entrega item se online
    for src, u in pairs(Core.sessions) do
      if u.char_id == cid then Core.giveKeyItem(src, pp); break end
    end
    Core:log(pp, 'admin_grant_key', actorOf(actor_src),
      { char = cid, kind = kind, days = d })
  end)
  return true
end)

-- Revogar chave
exports('adminRevokeKey', function(plate, char_id, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  local cid = tonumber(char_id); if not cid then return false end
  inThread(function()
    SQL:revokeKey(pp, cid)
    for src, u in pairs(Core.sessions) do
      if u.char_id == cid then Core.takeKeyItem(src, pp); break end
    end
    Core:log(pp, 'admin_revoke_key', actorOf(actor_src), { char = cid })
  end)
  return true
end)

-- Spawnar ve culo para um src espec fico (admin)
exports('adminSpawnTo', function(src, plate, pos, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  src = tonumber(src); if not src then return false end
  inThread(function()
    local v = SQL:getVehicle(pp); if not v then return end
    local p = pos or { x = 0, y = 0, z = 50, h = 0 }
    SQL:updateStatus(pp, 'out')
    SQL:updatePosition(pp, U.jenc(p))
    -- PRONTU RIO: fonte  nica do f sico+cosm tico (fallback coluna legada)
    local st
    pcall(function() st = exports.vhub_conce:getVehicleState(pp) end)
    TriggerClientEvent(E.DO_SPAWN, src, {
      plate = pp, model = v.model, vtype = v.vtype,
      customization = (st and st.customization) or U.jdec(v.customization),
      state = st, locked = v.locked == 1,
      surface = VHubGarage.types.surface[v.vtype] or 'ground',
    }, p)
    Core:log(pp, 'admin_spawn_to', actorOf(actor_src), { src = src })
  end)
  return true
end)

-- Despawnar global (todos clientes removem)
exports('adminDespawn', function(plate, actor_src)
  if not invoker_ok() then return false end
  local pp = U.normalizePlate(plate); if not pp then return false end
  TriggerClientEvent(E.DO_DESPAWN, -1, pp)
  inThread(function()
    SQL:updateStatus(pp, 'garage')
    Core:log(pp, 'admin_despawn', actorOf(actor_src), {})
  end)
  return true
end)

-- ============================================================================
-- MANUTEN  O / SA DE
-- ============================================================================

exports('adminPurgeExpiredKeys', function(actor_src)
  if not invoker_ok() then return 0 end
  local p = promise.new()
  Citizen.CreateThread(function()
    local r = SQL:purgeExpiredKeys()
    Core:log('SYS', 'admin_purge_keys', actorOf(actor_src), {})
    p:resolve(r and r.affectedRows or 0)
  end)
  return Citizen.Await(p)
end)

exports('adminPurgeOldLogs', function(days, actor_src)
  if not invoker_ok() then return 0 end
  local d = math.max(7, tonumber(days) or 60)
  local p = promise.new()
  Citizen.CreateThread(function()
    local cutoff = os.time() - d * 86400
    local r = SQL.execute(
      'DELETE FROM vhub_vehicle_log WHERE created_at < ?', { cutoff })
    Core:log('SYS', 'admin_purge_logs', actorOf(actor_src), { days = d })
    p:resolve(r and r.affectedRows or 0)
  end)
  return Citizen.Await(p)
end)

exports('adminFinalizeStaleAuctions', function(actor_src)
  if not invoker_ok() then return 0 end
  local p = promise.new()
  Citizen.CreateThread(function()
    -- finaliza (com escrow/transferOwner) no vhub_ferinha; retorna a contagem
    local n = exports.vhub_ferinha:finalizeExpired() or 0
    Core:log('SYS', 'admin_finalize_auctions', actorOf(actor_src), { count = n })
    p:resolve(n)
  end)
  return Citizen.Await(p)
end)
