-- server/core.lua - autoridade, validacao e VRAM do dominio de outdoors

VHubOutdoors = VHubOutdoors or {}

local CFG = VHubOutdoors.cfg
local E = VHubOutdoors.E
local Media = VHubOutdoors.Media
local SQL = VHubOutdoors.SQL
local M = {
  ready = false,
  active = {},
  pending = {},
  rates = {},
  revision = 0,
  nonce = 0,
  mutation_busy = false,
  epoch = ('%d:%06d'):format(os.time(), math.random(0, 999999)),
}
VHubOutdoors.Core = M

local COORD_KEYS = { x = true, y = true, z = true }
local DIRECT_KEYS = {
  operation_id = true,
  title = true,
  media_url = true,
  size = true,
  center = true,
  normal = true,
}
local UPDATE_KEYS = {
  media_url = true,
  volume = true,
  geometry = true,
}

local function copy_coord(coord)
  return { x = coord.x, y = coord.y, z = coord.z }
end

local function copy_item(item)
  return {
    id = item.id,
    title = item.title,
    media_type = item.media_type,
    source = item.source,
    size = item.size,
    volume = item.volume,
    top_left = copy_coord(item.top_left),
    bottom_right = copy_coord(item.bottom_right),
  }
end

local function replica_item(item)
  return {
    id = item.id,
    media_type = item.media_type,
    source = item.source,
    size = item.size,
    top_left = copy_coord(item.top_left),
    bottom_right = copy_coord(item.bottom_right),
  }
end

local function active_count()
  local count = 0
  for _ in pairs(M.active) do count = count + 1 end
  return count
end

local function actor_of(src)
  src = tonumber(src)
  if not src or src < 1 or not GetPlayerName(src) then return nil end
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  uid = ok and tonumber(uid) or nil
  if not uid then return nil end
  return { id = uid, name = GetPlayerName(src):sub(1, 64) }
end

local function revalidate_actor(src, expected_id)
  if not M.hasPermission(src) then return nil end
  local actor = actor_of(src)
  return actor and actor.id == expected_id and actor or nil
end

local function coord_of(raw)
  if type(raw) ~= 'table' then return nil end
  for key in pairs(raw) do
    if not COORD_KEYS[key] then return nil end
  end
  local x = VHubOutdoors.finite(raw.x)
  local y = VHubOutdoors.finite(raw.y)
  local z = VHubOutdoors.finite(raw.z)
  local limits = CFG.limits
  if not x or not y or not z
      or math.abs(x) > limits.world_xy
      or math.abs(y) > limits.world_xy
      or z < limits.world_z_min
      or z > limits.world_z_max then
    return nil
  end
  return { x = x, y = y, z = z }
end

local function normal_of(raw)
  if type(raw) ~= 'table' then return nil end
  for key in pairs(raw) do
    if not COORD_KEYS[key] then return nil end
  end
  local x = VHubOutdoors.finite(raw.x)
  local y = VHubOutdoors.finite(raw.y)
  local z = VHubOutdoors.finite(raw.z)
  if not x or not y or not z
      or math.abs(x) > 1.1 or math.abs(y) > 1.1 or math.abs(z) > 1.1 then
    return nil
  end

  local magnitude = math.sqrt(x * x + y * y + z * z)
  local horizontal = math.sqrt(x * x + y * y)
  if magnitude < 0.8 or magnitude > 1.2
      or horizontal < 0.75 or math.abs(z) > CFG.limits.max_surface_tilt then
    return nil
  end
  return { x = x / horizontal, y = y / horizontal, z = 0.0 }
end

local function geometry_of(raw, actor_src)
  if type(raw) ~= 'table' then return nil end
  local top_left = coord_of(raw.top_left)
  local bottom_right = coord_of(raw.bottom_right)
  if not top_left or not bottom_right then return nil end

  local dx = top_left.x - bottom_right.x
  local dy = top_left.y - bottom_right.y
  local width = math.sqrt(dx * dx + dy * dy)
  local height = math.abs(top_left.z - bottom_right.z)
  local area = width * height
  local limits = CFG.limits
  if width < limits.min_width or width > limits.max_width
      or height < limits.min_height or height > limits.max_height
      or area > limits.max_area then
    return nil
  end

  if actor_src then
    local ped = GetPlayerPed(actor_src)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
    local actor_coords = GetEntityCoords(ped)
    local maximum_squared = limits.placement_distance * limits.placement_distance
    local lower = math.min(top_left.z, bottom_right.z)
    local upper = math.max(top_left.z, bottom_right.z)
    local function corner_is_near(x, y, z)
      local distance_x = actor_coords.x - x
      local distance_y = actor_coords.y - y
      local distance_z = actor_coords.z - z
      return distance_x * distance_x + distance_y * distance_y
        + distance_z * distance_z <= maximum_squared
    end
    if not corner_is_near(top_left.x, top_left.y, lower)
        or not corner_is_near(top_left.x, top_left.y, upper)
        or not corner_is_near(bottom_right.x, bottom_right.y, lower)
        or not corner_is_near(bottom_right.x, bottom_right.y, upper) then
      return nil
    end
  end

  return {
    top_left = top_left,
    bottom_right = bottom_right,
  }
end

local function geometry_from_surface(raw, actor_src, size_name)
  local center = coord_of(raw.center)
  local normal = normal_of(raw.normal)
  if not center or not normal then return nil end
  local geometry, name = VHubOutdoors.deriveGeometry(center, normal, size_name)
  if not geometry then return nil end
  return geometry_of(geometry, actor_src), name
end

local function geometry_matches_size(geometry, size_name)
  local _, preset = VHubOutdoors.resolveSize(size_name)
  if not preset then return false end
  local dx = geometry.top_left.x - geometry.bottom_right.x
  local dy = geometry.top_left.y - geometry.bottom_right.y
  local width = math.sqrt(dx * dx + dy * dy)
  local height = math.abs(geometry.top_left.z - geometry.bottom_right.z)
  return math.abs(width - preset.width) <= 0.03
    and math.abs(height - preset.height) <= 0.03
end

local function row_to_item(row)
  if type(row) ~= 'table' or tonumber(row.active) ~= 1 then return nil end
  local item = {
    id = tonumber(row.id),
    title = VHubOutdoors.sanitizeTitle(row.title),
    media_type = row.media_type,
    source = row.media_type == 'youtube' and row.youtube_id or row.media_url,
    volume = VHubOutdoors.finite(row.volume),
    controller_char_id = tonumber(row.controller_char_id),
    controller_key = row.controller_key,
    top_left = coord_of({
      x = row.top_left_x,
      y = row.top_left_y,
      z = row.top_left_z,
    }),
    bottom_right = coord_of({
      x = row.bottom_right_x,
      y = row.bottom_right_y,
      z = row.bottom_right_z,
    }),
  }
  if not item.id or not item.title or not item.top_left or not item.bottom_right
      or not item.volume or item.volume < 0.0 or item.volume > 1.0
      or not VHubOutdoors.validSnapshotSource(item.media_type, item.source)
      or not geometry_of(item) then
    return nil
  end
  local has_controller = item.controller_char_id ~= nil or item.controller_key ~= nil
  if has_controller and (not item.controller_char_id
      or item.controller_char_id % 1 ~= 0
      or item.controller_char_id < 1
      or type(item.controller_key) ~= 'string'
      or #item.controller_key ~= 32
      or not item.controller_key:match('^%x+$')) then
    return nil
  end
  local stored_size = type(row.size) == 'string'
    and VHubOutdoors.resolveSize(row.size)
    or nil
  if row.size ~= nil and (not stored_size or not geometry_matches_size(item, stored_size)) then
    return nil
  end
  item.size = stored_size
  return item
end

local function row_matches(row, data)
  local epsilon = 0.0001
  local function near(a, b)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= epsilon
  end
  return row.title == data.title
    and row.media_type == data.media_type
    and row.media_url == data.media_url
    and (row.youtube_id or nil) == (data.youtube_id or nil)
    and (row.size or nil) == (data.size or nil)
    and near(row.volume, data.volume)
    and tonumber(row.created_by) == data.actor_id
    and near(row.top_left_x, data.top_left.x)
    and near(row.top_left_y, data.top_left.y)
    and near(row.top_left_z, data.top_left.z)
    and near(row.bottom_right_x, data.bottom_right.x)
    and near(row.bottom_right_y, data.bottom_right.y)
    and near(row.bottom_right_z, data.bottom_right.z)
end

local function mutate(callback)
  if M.mutation_busy then return nil, 'busy' end
  M.mutation_busy = true
  local result = table.pack(pcall(callback))
  M.mutation_busy = false
  if not result[1] then return nil, 'storage' end
  return table.unpack(result, 2, result.n)
end

local function operation_id(kind, actor_id)
  M.nonce = M.nonce + 1
  return ('%s:%s:%d:%d'):format(kind, M.epoch, actor_id, M.nonce)
end

-- Envia notificacao individual pelo canal canonico do vHub.
function M.notify(src, notification_type, message)
  if not tonumber(src) or not GetPlayerName(src) then return end
  pcall(function()
    exports.vhub_notify:notify(src, {
      type = notification_type,
      title = 'Outdoors',
      msg = message,
    })
  end)
end

-- Verifica owner, ACE e permissao do vhub_groups sem confiar no cliente.
function M.hasPermission(src)
  src = tonumber(src)
  if not src or src < 1 or not GetPlayerName(src) then return false end
  local ok_uid, uid = pcall(function() return exports.vhub:getUID(src) end)
  if ok_uid and tonumber(uid) == 1 then return true end
  if IsPlayerAceAllowed(src, 'vhub.admin.full')
      or IsPlayerAceAllowed(src, 'vhub.' .. CFG.permission) then
    return true
  end
  local ok_group, allowed = pcall(function()
    return exports.vhub_groups:hasPermission(src, CFG.permission)
  end)
  return ok_group and allowed == true
end

-- Aplica rate-limit O(1) por jogador e acao.
function M.rate(src, key)
  src = tonumber(src)
  if not src or src < 1 then return false end
  local now = GetGameTimer()
  local by_source = M.rates[src] or {}
  local last = by_source[key]
  local interval = CFG.rates[key] or 1000
  if last and now - last < interval then return false end
  by_source[key] = now
  M.rates[src] = by_source
  return true
end

-- Valida sessao, permissao e frequencia de uma acao administrativa.
function M.guard(src, rate_key)
  if not M.rate(src, rate_key) then return false end
  if not M.ready then
    M.notify(src, 'erro', 'Sistema de outdoors indisponivel.')
    return false
  end
  if not M.hasPermission(src) then
    M.notify(src, 'negado', 'Sem permissao para gerenciar outdoors.')
    return false
  end
  return true
end

-- Publica somente a replica versionada dos registros ativos.
function M.publish()
  local items = {}
  for _, item in pairs(M.active) do items[#items + 1] = replica_item(item) end
  table.sort(items, function(left, right) return left.id < right.id end)
  GlobalState.vhub_outdoors = {
    version = 1,
    revision = M.revision,
    items = items,
  }
end

-- Hidrata a VRAM autoritativa depois do schema e SQL estarem prontos.
function M.load(rows, revision)
  if type(rows) ~= 'table' or #rows > CFG.limits.max_outdoors then
    return false, 'active_limit_exceeded'
  end
  local loaded = {}
  for _, row in ipairs(rows or {}) do
    local item = row_to_item(row)
    if not item or loaded[item.id] then return false, 'invalid_persisted_item' end
    loaded[item.id] = item
  end
  M.active = loaded
  M.revision = tonumber(revision) or 0
  M.ready = true
  M.publish()
  return true
end

-- Abre uma capacidade temporaria de posicionamento para um administrador.
function M.beginPlacement(src, raw_size, raw_url, raw_title)
  if not M.guard(src, 'create_command') then return false end

  local unresolved = M.pending[src]
  if unresolved and unresolved.committing then
    M.notify(src, 'info', 'A operacao anterior ainda esta em commit.')
    return false
  end
  if unresolved and unresolved.geometry and not unresolved.committing then
    unresolved.expires_at = os.time() + CFG.limits.pending_seconds
    unresolved.retries = 0
    Citizen.SetTimeout(0, function()
      if M.pending[src] == unresolved then
        M.commitPlacement(src, { nonce = unresolved.nonce })
      end
    end)
    M.notify(src, 'info', 'Reconciliando a operacao anterior antes de criar outra.')
    return false
  end

  local size_name = VHubOutdoors.resolveSize(raw_size)
  if not size_name then
    M.notify(src, 'info', 'Escolha um tamanho pequeno, medio ou grande.')
    return false
  end
  if active_count() >= CFG.limits.max_outdoors then
    M.notify(src, 'erro', 'Limite global de outdoors atingido.')
    return false
  end

  local media = VHubOutdoors.parseMedia(raw_url)
  local title = VHubOutdoors.sanitizeTitle(raw_title or '')
  if not media then
    M.notify(src, 'erro', 'Use Discord CDN, Imgur direto ou YouTube.')
    return false
  end
  local actor = actor_of(src)
  if not actor then return false end
  if not title then
    title = media.media_type == 'image' and 'Imagem'
      or media.media_type == 'video' and 'Video'
      or 'YouTube'
  end

  M.nonce = M.nonce + 1
  M.pending[src] = {
    nonce = M.nonce,
    expires_at = os.time() + CFG.limits.pending_seconds,
    title = title,
    size = size_name,
    media = media,
    actor_id = actor.id,
    actor_name = actor.name,
    operation_id = operation_id('cmd_create', actor.id),
    retries = 0,
  }
  TriggerClientEvent(E.BEGIN_PLACEMENT, src, {
    nonce = M.pending[src].nonce,
    ray_distance = CFG.limits.ray_distance,
    size = size_name,
  })
  return true
end

-- Executa I/O remoto fora do lock e revalida o estado antes do commit.
function M.create(data, preflight, precommit)
  if preflight then
    local lookup = table.pack(pcall(SQL.findByOperation, data.operation_id))
    if not lookup[1] then return nil, 'storage' end
    if not lookup[2] then
      local checked = table.pack(pcall(preflight))
      if not checked[1] then return nil, 'storage' end
      if not checked[2] then return nil, checked[3] or 'forbidden' end
    end
  end

  return mutate(function()
    local row = SQL.findByOperation(data.operation_id)
    local replayed = row ~= nil
    if not row then
      if active_count() >= CFG.limits.max_outdoors then return nil, 'limit' end
      if precommit then
        local allowed, error_code = precommit()
        if not allowed then return nil, error_code or 'forbidden' end
      end
      local create_error
      row, create_error = SQL.create(data, true, true)
      if not row then return nil, create_error or 'storage' end
    end
    if not row_matches(row, data) or tonumber(row.active) ~= 1 then return nil, 'conflict' end

    local item = row_to_item(row)
    local audit_id = tonumber(row.audit_id)
    if not item or not audit_id then return nil, 'storage' end
    M.active[item.id] = item
    M.revision = math.max(M.revision, audit_id)
    M.publish()
    return {
      ok = true,
      id = item.id,
      replayed = replayed == true,
      size = item.size,
    }
  end)
end

local function commit_pending(src, pending)
  if pending.committing or not pending.geometry then return end
  pending.committing = true
  local remote = VHubOutdoors.Remote
  if not pending.remote_grant then
    pending.remote_grant = remote
      and type(remote.prepareCreatorGrant) == 'function'
      and remote.prepareCreatorGrant(src)
      or nil
  end
  if not pending.remote_grant then
    pending.committing = false
    M.notify(src, 'erro', 'Falha segura ao preparar o controle remoto.')
    return
  end

  local result, error_code = M.create({
    operation_id = pending.operation_id,
    title = pending.title,
    media_type = pending.media.media_type,
    media_url = pending.media.media_url,
    youtube_id = pending.media.youtube_id,
    size = pending.size,
    volume = CFG.audio.volume,
    top_left = pending.geometry.top_left,
    bottom_right = pending.geometry.bottom_right,
    actor_id = pending.actor_id,
    actor_name = pending.actor_name,
    reason = 'Criacao por comando administrativo',
    remote_grant = pending.remote_grant,
  }, function()
    if pending.probe_ok then return true end
    if not Media.probe(pending.media) then return false, 'remote_media_rejected' end
    pending.probe_ok = true
    return true
  end, function()
    local current_actor = revalidate_actor(src, pending.actor_id)
    if M.pending[src] ~= pending or pending.expires_at < os.time()
        or not current_actor or not geometry_of(pending.geometry, src) then
      return false, 'forbidden'
    end
    return true
  end)

  if result and result.ok then
    if M.pending[src] == pending then M.pending[src] = nil end
    M.notify(src, 'sucesso', ('Outdoor #%d criado.'):format(result.id))
    if remote and type(remote.deliverPreparedGrant) == 'function' then
      remote.deliverPreparedGrant(src, result.id, pending.remote_grant)
    end
    return
  end

  local retryable = (error_code == 'storage' or error_code == 'busy')
    and pending.retries < CFG.limits.max_commit_retries
  pending.committing = false
  if retryable then
    pending.retries = pending.retries + 1
    Citizen.SetTimeout(CFG.limits.commit_retry_ms, function()
      commit_pending(src, pending)
    end)
  elseif error_code ~= 'storage' and error_code ~= 'busy'
      and M.pending[src] == pending then
    M.pending[src] = nil
  end

  local message = error_code == 'limit' and 'Limite global de outdoors atingido.'
    or error_code == 'busy' and retryable
      and 'Outra alteracao esta em andamento. Reintentando.'
    or error_code == 'busy'
      and 'Operacao pendente. Use /outdoor para reconciliar.'
    or error_code == 'remote_media_rejected'
      and 'Midia remota recusada por tipo, tamanho ou indisponibilidade.'
    or retryable and 'Commit incerto. Reconciliacao automatica em andamento.'
    or error_code == 'storage' and 'Commit incerto. Use /outdoor para reconciliar.'
    or 'Falha segura ao persistir o outdoor.'
  M.notify(src, 'erro', message)
end

-- Consome a capacidade de posicionamento e ignora URL enviada pelo cliente.
function M.commitPlacement(src, payload)
  if not M.guard(src, 'submit_placement') or type(payload) ~= 'table' then return end
  for key in pairs(payload) do
    if key ~= 'nonce' and key ~= 'center' and key ~= 'normal' then return end
  end

  local pending = M.pending[src]
  local nonce = VHubOutdoors.finite(payload.nonce)
  if pending and pending.committing then return end
  if not pending or pending.expires_at < os.time()
      or not nonce or nonce % 1 ~= 0 or nonce ~= pending.nonce then
    M.pending[src] = nil
    M.notify(src, 'erro', 'Posicionamento expirado ou invalido.')
    return
  end

  local geometry = pending.geometry
  if not geometry then
    geometry = geometry_from_surface(payload, src, pending.size)
    if not geometry then
      M.notify(src, 'erro', 'Area invalida, distante ou fora dos limites.')
      return
    end
    pending.geometry = {
      top_left = copy_coord(geometry.top_left),
      bottom_right = copy_coord(geometry.bottom_right),
    }
  end

  local actor = revalidate_actor(src, pending.actor_id)
  if not actor then
    M.pending[src] = nil
    return
  end

  commit_pending(src, pending)
end

-- Cria outdoor por export confiavel mantendo a autoridade no servidor.
function M.createDirect(src, raw, caller)
  if not M.guard(src, 'export_create') or type(raw) ~= 'table' then
    return { ok = false, err = 'forbidden' }
  end
  for key in pairs(raw) do
    if not DIRECT_KEYS[key] then return { ok = false, err = 'invalid_payload' } end
  end
  local media = VHubOutdoors.parseMedia(raw.media_url)
  local title = VHubOutdoors.sanitizeTitle(raw.title)
  if not media or not title
      or not VHubOutdoors.validOperationId(raw.operation_id, 64) then
    return { ok = false, err = 'invalid_payload' }
  end

  local center = coord_of(raw.center)
  local normal = normal_of(raw.normal)
  local size_name = VHubOutdoors.resolveSize(raw.size)
  local geometry = center and normal and size_name
    and geometry_from_surface({ center = center, normal = normal }, nil, size_name)
    or nil
  if not geometry or not size_name then
    return { ok = false, err = 'invalid_payload' }
  end

  local actor = actor_of(src)
  if not actor then return { ok = false, err = 'offline' } end

  local full_operation = caller .. ':' .. raw.operation_id
  if not VHubOutdoors.validOperationId(full_operation, 96) then
    return { ok = false, err = 'invalid_operation' }
  end

  local result, error_code = M.create({
    operation_id = full_operation,
    title = title,
    media_type = media.media_type,
    media_url = media.media_url,
    youtube_id = media.youtube_id,
    size = size_name,
    volume = CFG.audio.volume,
    top_left = geometry.top_left,
    bottom_right = geometry.bottom_right,
    actor_id = actor.id,
    actor_name = actor.name,
    reason = ('Criacao pelo resource %s'):format(caller),
  }, function()
    if not Media.probe(media) then return false, 'remote_media_rejected' end
    return true
  end, function()
    local current_actor = revalidate_actor(src, actor.id)
    if not current_actor or not geometry_of(geometry, src) then
      return false, 'forbidden'
    end
    return true
  end)
  return result or { ok = false, err = error_code or 'storage' }
end

-- Desativa um outdoor idempotentemente e atualiza a replica apos ACK SQL.
function M.remove(src, id, operation, reason)
  id = VHubOutdoors.finite(id)
  if not id or id % 1 ~= 0 or id < 1
      or not VHubOutdoors.validOperationId(operation, 96) then
    return { ok = false, err = 'invalid_payload' }
  end
  if type(reason) ~= 'string' or #reason < 1 or #reason > CFG.limits.max_reason
      or reason:find('%c') then
    return { ok = false, err = 'invalid_reason' }
  end

  local actor = actor_of(src)
  if not actor then return { ok = false, err = 'offline' } end
  local result, error_code = mutate(function()
    local removed, replayed, audit_id = SQL.softDelete(
      id,
      actor,
      operation,
      reason,
      function()
        return revalidate_actor(src, actor.id) ~= nil, 'forbidden'
      end
    )
    if not removed then return nil, replayed or 'storage' end
    audit_id = tonumber(audit_id)
    if not audit_id then return nil, 'storage' end
    M.active[id] = nil
    M.revision = math.max(M.revision, audit_id)
    M.publish()
    return { ok = true, id = id, replayed = replayed == true }
  end)
  return result or { ok = false, err = error_code or 'storage' }
end

-- Remove por comando com identificador estavel para reconciliar commit incerto.
function M.removeCommand(src, id)
  local actor = actor_of(src)
  if not actor then return { ok = false, err = 'offline' } end
  return M.remove(
    src,
    id,
    ('cmd_delete:%d:%d'):format(actor.id, id),
    'Remocao por comando administrativo'
  )
end

-- Deriva geometria de preset mantendo validacao de mundo e proximidade no servidor.
function M.geometryFromSurface(raw, src, size_name)
  local geometry, resolved = geometry_from_surface(raw, src, size_name)
  if not geometry then return nil end
  return {
    top_left = copy_coord(geometry.top_left),
    bottom_right = copy_coord(geometry.bottom_right),
  }, resolved
end

-- Confirma proximidade tridimensional do jogador ao centro do outdoor.
function M.isNear(src, item, maximum, expected_bucket)
  src = tonumber(src)
  maximum = VHubOutdoors.finite(maximum)
  if not src or not maximum or maximum <= 0.0 or type(item) ~= 'table' then
    return false
  end
  if expected_bucket ~= nil then
    local ok_bucket, bucket = pcall(GetPlayerRoutingBucket, src)
    if not ok_bucket or bucket ~= expected_bucket then return false end
  end
  local ped = GetPlayerPed(src)
  if not ped or ped <= 0 or not DoesEntityExist(ped) then return false end
  local coords = GetEntityCoords(ped)
  local center_x = (item.top_left.x + item.bottom_right.x) * 0.5
  local center_y = (item.top_left.y + item.bottom_right.y) * 0.5
  local center_z = (item.top_left.z + item.bottom_right.z) * 0.5
  local dx = coords.x - center_x
  local dy = coords.y - center_y
  local dz = coords.z - center_z
  return dx * dx + dy * dy + dz * dz <= maximum * maximum
end

-- Ativa uma concessao 1:1 com journal, controlador e auditoria atomicos.
function M.activateController(src, id, char_id, access_key, grant_operation, authorize)
  id = VHubOutdoors.finite(id)
  char_id = VHubOutdoors.finite(char_id)
  if not M.ready or not id or id % 1 ~= 0 or id < 1
      or not char_id or char_id % 1 ~= 0 or char_id < 1
      or char_id > 2147483647
      or type(access_key) ~= 'string' or #access_key ~= 32
      or not access_key:match('^%x+$')
      or not VHubOutdoors.validOperationId(grant_operation, 96)
      or type(authorize) ~= 'function' then
    return { ok = false, err = 'invalid_payload' }
  end

  local actor = actor_of(src)
  if not actor then return { ok = false, err = 'offline' } end
  local result, error_code = mutate(function()
    local current = M.active[id]
    if not current then return nil, 'not_found' end
    local allowed, denied = authorize(current)
    if not allowed then return nil, denied or 'forbidden' end

    local row, activate_error = SQL.activateRemoteGrant(
      id,
      char_id,
      access_key,
      grant_operation,
      function()
        local authoritative = M.active[id]
        if authoritative ~= current then return false, 'conflict' end
        local current_actor = actor_of(src)
        if not current_actor or current_actor.id ~= actor.id then
          return false, 'forbidden'
        end
        return authorize(authoritative)
      end
    )
    if not row then return nil, activate_error or 'storage' end

    local item = row_to_item(row)
    local audit_id = tonumber(row.audit_id)
    if not item or not audit_id then return nil, 'storage' end
    M.active[id] = item
    M.revision = math.max(M.revision, audit_id)
    M.publish()
    return { ok = true, id = id, item = copy_item(item) }
  end)
  if not result and error_code == 'storage' then
    M.ready = false
    Citizen.Trace(
      '[vhub_outdoors][ERRO] ativacao incerta; mutacoes bloqueadas ate restart.\n'
    )
  end
  return result or { ok = false, err = error_code or 'storage' }
end

-- Atualiza canal, volume ou geometria sob autorizacao externa revalidada no commit.
function M.updateItem(src, id, changes, reason, authorize)
  id = VHubOutdoors.finite(id)
  if not M.ready or not id or id % 1 ~= 0 or id < 1
      or type(changes) ~= 'table' or next(changes) == nil
      or type(reason) ~= 'string' or #reason < 1
      or #reason > CFG.limits.max_reason or reason:find('%c')
      or type(authorize) ~= 'function' then
    return { ok = false, err = 'invalid_payload' }
  end
  for key in pairs(changes) do
    if not UPDATE_KEYS[key] then return { ok = false, err = 'invalid_payload' } end
  end

  local media = nil
  if changes.media_url ~= nil then
    media = VHubOutdoors.parseMedia(changes.media_url)
    if not media then return { ok = false, err = 'invalid_media' } end
  end
  local volume = nil
  if changes.volume ~= nil then
    volume = VHubOutdoors.finite(changes.volume)
    if not volume or volume < 0.0 or volume > 1.0 then
      return { ok = false, err = 'invalid_volume' }
    end
  end
  local geometry = nil
  if changes.geometry ~= nil then
    geometry = geometry_of(changes.geometry, src)
    local current = M.active[id]
    if not current or not geometry
        or not current.size or not geometry_matches_size(geometry, current.size) then
      return { ok = false, err = 'invalid_geometry' }
    end
  end
  local actor = actor_of(src)
  if not actor then return { ok = false, err = 'offline' } end
  local update_operation = operation_id('remote_update', actor.id)
  local result, error_code = mutate(function()
    local current = M.active[id]
    if not current then return nil, 'not_found' end
    local allowed, denied = authorize(current)
    if not allowed then return nil, denied or 'forbidden' end

    local data = copy_item(current)
    if media then
      data.media_type = media.media_type
      data.source = media.source
    end
    if volume ~= nil then data.volume = volume end
    if geometry then
      data.top_left = copy_coord(geometry.top_left)
      data.bottom_right = copy_coord(geometry.bottom_right)
    end
    data.controller_char_id = current.controller_char_id
    data.controller_key = current.controller_key

    local media_url = data.media_type == 'youtube'
      and ('https://www.youtube.com/watch?v=%s'):format(data.source)
      or data.source
    local row, update_error = SQL.update({
      id = data.id,
      title = data.title,
      media_type = data.media_type,
      media_url = media_url,
      youtube_id = data.media_type == 'youtube' and data.source or nil,
      size = data.size,
      volume = data.volume,
      controller_char_id = data.controller_char_id,
      controller_key = data.controller_key,
      top_left = data.top_left,
      bottom_right = data.bottom_right,
    }, actor, update_operation, reason, function()
      local authoritative = M.active[id]
      if authoritative ~= current then return false, 'conflict' end
      local current_actor = actor_of(src)
      if not current_actor or current_actor.id ~= actor.id then
        return false, 'forbidden'
      end
      return authorize(authoritative)
    end)
    if not row then return nil, update_error or 'storage' end

    local item = row_to_item(row)
    local audit_id = tonumber(row.audit_id)
    if not item or not audit_id then return nil, 'storage' end
    M.active[id] = item
    M.revision = math.max(M.revision, audit_id)
    M.publish()
    return { ok = true, id = id, item = copy_item(item) }
  end)
  return result or { ok = false, err = error_code or 'storage' }
end

-- Valida o vinculo 1:1 sem expor a chave na replica ou nos exports.
function M.controllerMatches(id, char_id, access_key)
  id = tonumber(id)
  char_id = tonumber(char_id)
  local item = id and M.active[id] or nil
  return item ~= nil
    and item.controller_char_id == char_id
    and type(access_key) == 'string'
    and item.controller_key == access_key
end

-- Retorna copia de um outdoor ativo por ID.
function M.get(id)
  id = tonumber(id)
  local item = id and M.active[id] or nil
  return item and copy_item(item) or nil
end

-- Retorna copia somente-leitura dos outdoors ativos.
function M.list()
  local items = {}
  for _, item in pairs(M.active) do items[#items + 1] = copy_item(item) end
  table.sort(items, function(left, right) return left.id < right.id end)
  return items
end

-- Limpa capacidades e rate-limit de um jogador desconectado.
function M.dropSource(src)
  M.pending[src] = nil
  M.rates[src] = nil
end

-- Encerra a replica e impede novas mutacoes.
function M.shutdown()
  M.ready = false
  M.pending = {}
  M.rates = {}
  GlobalState.vhub_outdoors = nil
end
