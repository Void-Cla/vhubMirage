-- server/remote.lua - controle remoto vinculado ao inventario

local CFG = VHubOutdoors.cfg
local E = VHubOutdoors.E
local Core = VHubOutdoors.Core
local Media = VHubOutdoors.Media
local SQL = VHubOutdoors.SQL
local sessions = {}
local sequence = 0
local Remote = {}
VHubOutdoors.Remote = Remote

local function only_keys(payload, allowed)
  if type(payload) ~= 'table' then return false end
  for key in pairs(payload) do
    if not allowed[key] then return false end
  end
  return true
end

local function integer(value, minimum, maximum)
  local number = VHubOutdoors.finite(value)
  if not number or number % 1 ~= 0
      or number < minimum or number > maximum then
    return nil
  end
  return number
end

local function user_of(src)
  local ok, user = pcall(function() return exports.vhub:getUser(src) end)
  if not ok or type(user) ~= 'table' then return nil end
  local char_id = integer(user.char_id, 1, 2147483647)
  local account_id = integer(user.id, 1, 2147483647)
  if not char_id or not account_id or tonumber(user.source) ~= tonumber(src) then
    return nil
  end
  return { char_id = char_id, account_id = account_id }
end

local function remote_meta(raw)
  if type(raw) ~= 'table' then return nil end
  for key in pairs(raw) do
    if key ~= 'outdoor_id' and key ~= 'access_key' and key ~= 'serial' then
      return nil
    end
  end
  local outdoor_id = integer(raw.outdoor_id, 1, 2147483647)
  local access_key = raw.access_key
  local serial = raw.serial
  if not outdoor_id
      or type(access_key) ~= 'string'
      or #access_key ~= 32
      or not access_key:match('^%x+$')
      or type(serial) ~= 'string'
      or #serial < 1 or #serial > 128
      or serial:find('%c') then
    return nil
  end
  return outdoor_id, access_key, serial
end

local function inventory_slot(src, slot)
  local ok, snapshot = pcall(function()
    return exports.vhub_inventory:getInventory(src)
  end)
  local slots = ok and type(snapshot) == 'table' and snapshot.slots or nil
  if type(slots) ~= 'table' then return nil end
  return slots[slot] or slots[tostring(slot)]
end

local function slot_matches(src, session)
  local user = user_of(src)
  if not user or user.char_id ~= session.char_id then return false end
  local entry = inventory_slot(src, session.slot)
  if type(entry) ~= 'table' or entry.id ~= CFG.remote.item
      or tonumber(entry.amount) ~= 1 then
    return false
  end
  local outdoor_id, access_key, serial = remote_meta(entry.meta)
  return outdoor_id == session.outdoor_id
    and access_key == session.access_key
    and serial == session.serial
end

local function authorized(src, session, item)
  return sessions[src] == session
    and session.expires_at >= os.time()
    and item.id == session.outdoor_id
    and Core.controllerMatches(item.id, session.char_id, session.access_key)
    and slot_matches(src, session)
    and Core.isNear(
      src, item, CFG.remote.control_distance, CFG.remote.routing_bucket
    )
end

local function token_for(src, char_id)
  sequence = (sequence + 1) % 0x7fffffff
  return ('%08x%08x%08x%08x'):format(
    os.time() % 0xffffffff,
    GetGameTimer() % 0xffffffff,
    tonumber(src) % 0xffffffff,
    (char_id + sequence) % 0xffffffff
  )
end

local function media_url(item)
  if item.media_type == 'youtube' then
    return ('https://www.youtube.com/watch?v=%s'):format(item.source)
  end
  return item.source
end

local function remote_payload(session, item)
  local preset = item.size and CFG.sizes[item.size] or nil
  return {
    token = session.token,
    id = item.id,
    title = item.title,
    size = preset and preset.label or item.size,
    url = media_url(item),
    volume = math.floor(item.volume * 100.0 + 0.5),
  }
end

local function send_result(src, session, action, result)
  local item = result and result.ok and result.item
    or session and Core.get(session.outdoor_id)
    or nil
  TriggerClientEvent(E.UPDATE_REMOTE_UI, src, {
    token = session and session.token or '',
    action = action,
    ok = result and result.ok == true,
    err = result and result.err or 'forbidden',
    item = item and remote_payload(session, item) or nil,
  })
end

local function require_session(src, payload, rate_key, allowed)
  if not Core.rate(src, rate_key) or not Core.ready
      or not only_keys(payload, allowed)
      or type(payload.token) ~= 'string'
      or #payload.token ~= 32 or not payload.token:match('^%x+$') then
    return nil
  end
  local session = sessions[src]
  local item = session and Core.get(session.outdoor_id) or nil
  if not session or session.token ~= payload.token or not item
      or not authorized(src, session, item) then
    sessions[src] = nil
    return nil
  end
  session.expires_at = os.time() + CFG.remote.session_seconds
  return session, item
end

local function find_source(char_id)
  for _, raw_src in ipairs(GetPlayers()) do
    local src = tonumber(raw_src)
    local user = src and user_of(src) or nil
    if user and user.char_id == char_id then return src end
  end
  return nil
end

local function remove_granted_item(target, outdoor_id, access_key)
  local snapshot_ok, snapshot = pcall(function()
    return exports.vhub_inventory:getInventory(target)
  end)
  local slots = snapshot_ok and type(snapshot) == 'table' and snapshot.slots or {}
  for slot, entry in pairs(slots) do
    local id, key = nil, nil
    if type(entry) == 'table' then id, key = remote_meta(entry.meta) end
    if type(entry) == 'table' and entry.id == CFG.remote.item
        and id == outdoor_id and key == access_key then
      local called, removed = pcall(function()
        return exports.vhub_inventory:takeItemFromSlot(target, tonumber(slot), 1)
      end)
      return called and removed == true
    end
  end
  return false
end

-- Prepara os dados do grant para embed na transacao atomica de criacao do outdoor.
function Remote.prepareCreatorGrant(src)
  src = tonumber(src)
  local user = src and user_of(src) or nil
  if not user then return nil end
  local access_key = token_for(src, user.char_id)
  local ok_uid, uid = pcall(function() return exports.vhub:getUID(src) end)
  local account_id = ok_uid and tonumber(uid) or nil
  if not account_id then return nil end
  return {
    operation_id = 'remote_grant:' .. access_key,
    char_id = user.char_id,
    access_key = access_key,
    created_by = account_id,
    src = src,
  }
end

-- Entrega o item ao inventario e ativa o controlador apos o outdoor ser criado com sucesso.
function Remote.deliverPreparedGrant(src, outdoor_id, grant)
  src = tonumber(src)
  outdoor_id = tonumber(outdoor_id)
  if not src or not outdoor_id or type(grant) ~= 'table' then return end
  if not Core.get(outdoor_id) then return end

  local ok, given = pcall(function()
    return exports.vhub_inventory:giveItem(
      src,
      CFG.remote.item,
      1,
      { outdoor_id = outdoor_id, access_key = grant.access_key }
    )
  end)
  if not ok or given ~= true then
    Core.notify(src, 'info', 'Outdoor criado, mas nao havia espaco para o controle.')
    return
  end

  local activated = Core.activateController(
    src,
    outdoor_id,
    grant.char_id,
    grant.access_key,
    grant.operation_id,
    function(current)
      return current.id == outdoor_id, 'forbidden'
    end
  )
  if not activated.ok then
    remove_granted_item(src, outdoor_id, grant.access_key)
    Core.notify(src, 'info', 'Outdoor criado, mas o controle nao foi ativado.')
    return
  end
  Core.notify(src, 'sucesso', ('Controle do outdoor #%d recebido.'):format(outdoor_id))
end

local function grant_control(admin_src, target, outdoor_id, char_id)
  local admin = user_of(admin_src)
  local target_user = user_of(target)
  if not admin or not target_user or target_user.char_id ~= char_id
      or not Core.get(outdoor_id) or not Core.hasPermission(admin_src) then
    return false, 'forbidden'
  end

  local access_key = token_for(target, char_id)
  local grant_operation = 'remote_grant:' .. access_key
  local journal_ok, grant = pcall(SQL.beginRemoteGrant, {
    operation_id = grant_operation,
    outdoor_id = outdoor_id,
    char_id = char_id,
    access_key = access_key,
    created_by = admin.account_id,
  })
  if not journal_ok or type(grant) ~= 'table' then
    return false, 'journal'
  end

  local current_admin = user_of(admin_src)
  target_user = user_of(target)
  if not current_admin or current_admin.account_id ~= admin.account_id
      or not target_user or target_user.char_id ~= char_id
      or not Core.hasPermission(admin_src) then
    pcall(SQL.setRemoteGrantStatus, grant_operation, 'cancelled')
    return false, 'forbidden'
  end

  local ok, given = pcall(function()
    return exports.vhub_inventory:giveItem(
      target,
      CFG.remote.item,
      1,
      { outdoor_id = outdoor_id, access_key = access_key }
    )
  end)
  if not ok or given ~= true then
    pcall(SQL.setRemoteGrantStatus, grant_operation, 'cancelled')
    return false, 'inventory'
  end

  local assigned = Core.activateController(
    admin_src,
    outdoor_id,
    char_id,
    access_key,
    grant_operation,
    function()
      local live_admin = user_of(admin_src)
      local live_target = user_of(target)
      return live_admin ~= nil
        and live_admin.account_id == admin.account_id
        and live_target ~= nil
        and live_target.char_id == char_id
        and Core.hasPermission(admin_src), 'forbidden'
    end
  )
  if not assigned.ok then
    if assigned.err ~= 'storage' then
      remove_granted_item(target, outdoor_id, access_key)
      pcall(SQL.setRemoteGrantStatus, grant_operation, 'cancelled')
    end
    return false, assigned.err or 'storage'
  end
  return true
end

function Remote.grantToCreator(src, outdoor_id)
  src = tonumber(src)
  outdoor_id = integer(outdoor_id, 1, 2147483647)
  local user = src and user_of(src) or nil
  if not user or not outdoor_id then return false end

  local granted, error_code = grant_control(src, src, outdoor_id, user.char_id)
  if granted then
    Core.notify(src, 'sucesso', ('Controle do outdoor #%d recebido.'):format(
      outdoor_id
    ))
    return true
  end
  Core.notify(src, 'erro', error_code == 'inventory'
    and 'Outdoor criado, mas nao havia espaco para o controle.'
    or 'Outdoor criado, mas o controle falhou de forma segura.')
  return false
end

local function open_remote(src, item_id, slot, outdoor_id, access_key, serial)
  if item_id ~= CFG.remote.item or not src or not slot
      or not Core.rate(src, 'remote_open') or not Core.ready then
    return
  end
  local user = user_of(src)
  local item = outdoor_id and Core.get(outdoor_id) or nil
  if not user or not item then
    Core.notify(src, 'erro', 'Controle sem outdoor ativo vinculado.')
    return
  end
  local provisional = {
    outdoor_id = outdoor_id,
    access_key = access_key,
    serial = serial,
    slot = slot,
    char_id = user.char_id,
  }
  if not slot_matches(src, provisional)
      or not Core.isNear(
        src, item, CFG.remote.control_distance, CFG.remote.routing_bucket
      ) then
    Core.notify(src, 'negado', 'Controle revogado ou distante do outdoor.')
    return
  end

  if not Core.controllerMatches(outdoor_id, user.char_id, access_key) then
    local ok_grant, grant = pcall(
      SQL.findRemoteGrant,
      outdoor_id,
      user.char_id,
      access_key
    )
    if not ok_grant or type(grant) ~= 'table'
        or (grant.status ~= 'pending' and grant.status ~= 'active') then
      Core.notify(src, 'negado', 'Controle revogado.')
      return
    end
    local activated = Core.activateController(
      src,
      outdoor_id,
      user.char_id,
      access_key,
      grant.operation_id,
      function(current)
        return current.id == outdoor_id
          and slot_matches(src, provisional)
          and Core.isNear(
            src, current, CFG.remote.control_distance, CFG.remote.routing_bucket
          ), 'forbidden'
      end
    )
    if not activated.ok then
      Core.notify(src, 'erro', 'Falha segura ao ativar o controle.')
      return
    end
    item = Core.get(outdoor_id)
  end

  provisional.token = token_for(src, user.char_id)
  provisional.expires_at = os.time() + CFG.remote.session_seconds
  sessions[src] = provisional
  TriggerClientEvent(E.OPEN_REMOTE_UI, src, remote_payload(provisional, item))
end

exports('useOutdoorRemote', function(src, item_id, slot, meta)
  src = tonumber(src)
  slot = integer(slot, 1, 1000)
  local outdoor_id, access_key, serial = remote_meta(meta)
  if item_id ~= CFG.remote.item or not src or not slot
      or not outdoor_id then
    return false
  end
  CreateThread(function()
    open_remote(src, item_id, slot, outdoor_id, access_key, serial)
  end)
  return false
end)

RegisterCommand(CFG.commands.remote, function(src, args)
  if src == 0 or not Core.guard(src, 'remote_grant') then return end
  local outdoor_id = integer(type(args) == 'table' and args[1], 1, 2147483647)
  local char_id = integer(type(args) == 'table' and args[2], 1, 2147483647)
  if not outdoor_id or not char_id then
    Core.notify(src, 'info', ('Use /%s <outdoor_id> <char_id>.'):format(
      CFG.commands.remote
    ))
    return
  end
  if not Core.get(outdoor_id) then
    Core.notify(src, 'erro', 'Outdoor ativo nao encontrado.')
    return
  end
  local target = find_source(char_id)
  if not target then
    Core.notify(src, 'erro', 'Personagem nao esta online.')
    return
  end
  local granted, error_code = grant_control(src, target, outdoor_id, char_id)
  if not granted then
    Core.notify(src, 'erro', error_code == 'inventory'
      and 'Mochila cheia ou inventario indisponivel.'
      or 'Falha segura ao vincular o controle.')
    return
  end
  Core.notify(src, 'sucesso', ('Controle do outdoor #%d entregue ao ID %d.'):format(
    outdoor_id, char_id
  ))
  Core.notify(target, 'sucesso', ('Voce recebeu o controle do outdoor #%d.'):format(
    outdoor_id
  ))
end, false)

RegisterNetEvent(E.REMOTE_SET_VOLUME, function(payload)
  local src = source
  local session = require_session(src, payload, 'remote_volume', {
    token = true,
    volume = true,
  })
  if not session then return end
  local raw_volume = integer(payload.volume, 0, 100)
  if raw_volume == nil then return end
  local result = Core.updateItem(
    src,
    session.outdoor_id,
    { volume = raw_volume / 100.0 },
    'Volume alterado por controle remoto',
    function(item)
      return authorized(src, session, item), 'forbidden'
    end
  )
  send_result(src, session, 'volume', result)
end)

RegisterNetEvent(E.REMOTE_SET_MEDIA, function(payload)
  local src = source
  local session = require_session(src, payload, 'remote_media', {
    token = true,
    url = true,
  })
  if not session or session.busy
      or type(payload.url) ~= 'string'
      or #payload.url < 1 or #payload.url > CFG.limits.max_url then
    return
  end
  local media = VHubOutdoors.parseMedia(payload.url)
  if not media then
    send_result(src, session, 'media', { ok = false, err = 'invalid_media' })
    return
  end

  session.busy = true
  CreateThread(function()
    local probe_ok = Media.probe(media)
    if sessions[src] ~= session then return end
    session.busy = nil
    if not probe_ok then
      send_result(src, session, 'media', {
        ok = false,
        err = 'remote_media_rejected',
      })
      return
    end
    local result = Core.updateItem(
      src,
      session.outdoor_id,
      { media_url = media.media_url },
      'Canal alterado por controle remoto',
      function(item)
        return authorized(src, session, item), 'forbidden'
      end
    )
    send_result(src, session, 'media', result)
  end)
end)

RegisterNetEvent(E.REMOTE_REQUEST_MOVE, function(payload)
  local src = source
  local session, item = require_session(src, payload, 'remote_move', {
    token = true,
  })
  if not session or session.busy or session.moving or not item.size then return end
  sequence = (sequence + 1) % 0x7fffffff
  session.moving = {
    nonce = sequence + 1,
    expires_at = os.time() + CFG.limits.pending_seconds,
  }
  TriggerClientEvent(E.BEGIN_REMOTE_MOVE, src, {
    token = session.token,
    nonce = session.moving.nonce,
    ray_distance = CFG.limits.ray_distance,
    size = item.size,
  })
end)

RegisterNetEvent(E.SUBMIT_REMOTE_MOVE, function(payload)
  local src = source
  local session, item = require_session(src, payload, 'remote_submit', {
    token = true,
    nonce = true,
    center = true,
    normal = true,
  })
  local moving = session and session.moving or nil
  local nonce = type(payload) == 'table'
    and integer(payload.nonce, 1, 2147483647)
    or nil
  if not session or not moving or not nonce or nonce ~= moving.nonce
      or moving.expires_at < os.time() then
    if session then session.moving = nil end
    return
  end
  local geometry = Core.geometryFromSurface(payload, src, item.size)
  if not geometry then
    Core.notify(src, 'erro', 'Posicao distante ou invalida.')
    return
  end
  session.moving = nil
  local result = Core.updateItem(
    src,
    session.outdoor_id,
    { geometry = geometry },
    'Posicao alterada por controle remoto',
    function(current)
      return authorized(src, session, current), 'forbidden'
    end
  )
  if result.ok then
    Core.notify(src, 'sucesso', ('Outdoor #%d reposicionado.'):format(item.id))
  else
    Core.notify(src, 'erro', 'Falha segura ao reposicionar o outdoor.')
  end
end)

local function try_register_item()
  if GetResourceState('vhub_inventory') ~= 'started' then return false end
  local ok, registered = pcall(function()
    return exports.vhub_inventory:registerItemUse(
      CFG.remote.item,
      'useOutdoorRemote'
    )
  end)
  return ok and registered == true
end

CreateThread(function()
  Wait(500)
  if not try_register_item() then
    Citizen.Trace('[vhub_outdoors][ERRO] item controle_outdoor nao registrado.\n')
  end
end)

AddEventHandler('onResourceStart', function(resource)
  if resource == 'vhub_inventory' then
    CreateThread(function()
      Wait(500)
      try_register_item()
    end)
  end
end)

AddEventHandler('vHub:characterLoad', function(user)
  local src = type(user) == 'table' and tonumber(user.source) or nil
  local session = src and sessions[src] or nil
  if session and tonumber(user.char_id) ~= session.char_id then sessions[src] = nil end
end)

AddEventHandler('playerDropped', function()
  sessions[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then sessions = {} end
end)
