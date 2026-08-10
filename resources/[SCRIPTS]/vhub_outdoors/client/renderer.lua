-- client/renderer.lua - streaming lazy de props e superficies DUI

local CFG = VHubOutdoors.cfg
local Props = VHubOutdoors.Props
local world = {}
local streamed = {}
local creating = {}
local failures = {}
local running = true
local render_running = false
local supervisor_running = false
local texture_slots = {}
local CREATE_RUNTIME_TEXTURE_FROM_DUI_HANDLE = 0xB135472B

for index = 1, CFG.limits.max_streamed do
  texture_slots[index] = {
    txd_name = 'vhub_outdoor_txd_' .. index,
    txn_base = 'vhub_outdoor_txn_' .. index,
    txn_name = 'vhub_outdoor_txn_' .. index .. '_1',
    generation = 1,
  }
end

local function copy_coord(raw)
  if type(raw) ~= 'table' then return nil end
  local x = VHubOutdoors.finite(raw.x)
  local y = VHubOutdoors.finite(raw.y)
  local z = VHubOutdoors.finite(raw.z)
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

local function normalize_item(raw)
  if type(raw) ~= 'table' then return nil end
  local id = VHubOutdoors.finite(raw.id)
  local top_left = copy_coord(raw.top_left)
  local bottom_right = copy_coord(raw.bottom_right)
  local size_name = raw.size and VHubOutdoors.resolveSize(raw.size) or nil
  if not id or id % 1 ~= 0 or id < 1 or not top_left or not bottom_right
      or raw.size ~= nil and not size_name
      or not VHubOutdoors.validSnapshotSource(raw.media_type, raw.source) then
    return nil
  end
  return {
    id = id,
    media_type = raw.media_type,
    source = raw.source,
    size = size_name,
    top_left = top_left,
    bottom_right = bottom_right,
    center = vec3(
      (top_left.x + bottom_right.x) * 0.5,
      (top_left.y + bottom_right.y) * 0.5,
      (top_left.z + bottom_right.z) * 0.5
    ),
  }
end

local function signature(item)
  return table.concat({
    item.media_type,
    item.source,
    item.size or 'legacy',
    item.top_left.x, item.top_left.y, item.top_left.z,
    item.bottom_right.x, item.bottom_right.y, item.bottom_right.z,
  }, ':')
end

local function url_encode(value)
  return (value:gsub('([^%w%-_%.~])', function(character)
    return ('%%%02X'):format(character:byte())
  end))
end

local function display_url(item)
  local dx = item.bottom_right.x - item.top_left.x
  local dy = item.bottom_right.y - item.top_left.y
  local width = math.sqrt(dx * dx + dy * dy)
  local height = math.abs(item.bottom_right.z - item.top_left.z)
  local aspect = height > 0.001 and math.max(0.25, math.min(8.0, width / height))
    or (16.0 / 9.0)
  return ('https://cfx-nui-%s/web/display.html?id=%d&type=%s&source=%s&aspect=%.6f'):format(
    GetCurrentResourceName(),
    item.id,
    item.media_type,
    url_encode(item.source),
    aspect
  )
end

local function blank_url()
  return ('https://cfx-nui-%s/web/display.html'):format(GetCurrentResourceName())
end

local function destroy_stream(id)
  local entry = streamed[id]
  if not entry then return end
  streamed[id] = nil
  Props.remover(entry.prop)
  if entry.slot then
    if entry.slot.dui then SetDuiUrl(entry.slot.dui, blank_url()) end
    entry.slot.item_id = nil
  end
end

local function destroy_all()
  local ids = {}
  for id in pairs(streamed) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do destroy_stream(id) end
end

local function destroy_slot_assets()
  for _, slot in ipairs(texture_slots) do
    if slot.dui then DestroyDui(slot.dui) end
    slot.dui = nil
    slot.texture = nil
    slot.txd = nil
    slot.item_id = nil
  end
end

local function draw_surface(surface, entry)
  local top_left = surface.top_left
  local top_right = surface.top_right
  local bottom_left = surface.bottom_left
  local bottom_right = surface.bottom_right
  DrawSpritePoly(
    bottom_right.x, bottom_right.y, bottom_right.z,
    top_right.x, top_right.y, top_right.z,
    top_left.x, top_left.y, top_left.z,
    255, 255, 255, 255,
    entry.txd_name, entry.txn_name,
    1.0, 1.0, 1.0,
    1.0, 0.0, 1.0,
    0.0, 0.0, 1.0
  )
  DrawSpritePoly(
    top_left.x, top_left.y, top_left.z,
    bottom_left.x, bottom_left.y, bottom_left.z,
    bottom_right.x, bottom_right.y, bottom_right.z,
    255, 255, 255, 255,
    entry.txd_name, entry.txn_name,
    0.0, 0.0, 1.0,
    0.0, 1.0, 1.0,
    1.0, 1.0, 1.0
  )
end

local function legacy_surface(item)
  local top_left = item.top_left
  local bottom_right = item.bottom_right
  local lower = math.min(top_left.z, bottom_right.z)
  local upper = math.max(top_left.z, bottom_right.z)
  return {
    top_left = vec3(top_left.x, top_left.y, upper),
    top_right = vec3(bottom_right.x, bottom_right.y, upper),
    bottom_left = vec3(top_left.x, top_left.y, lower),
    bottom_right = vec3(bottom_right.x, bottom_right.y, lower),
  }
end

local function draw_item(entry)
  if entry.prop and not DoesEntityExist(entry.prop) then return end
  draw_surface(entry.surface, entry)
end

local function ensure_render_loop()
  if render_running or next(streamed) == nil then return end
  render_running = true
  CreateThread(function()
    while running and next(streamed) ~= nil do
      for id, entry in pairs(streamed) do
        local item = world[id]
        if item then draw_item(entry) end
      end
      Wait(0)
    end
    render_running = false
    if running and next(streamed) ~= nil then ensure_render_loop() end
  end)
end

local function acquire_slot(item_id)
  for _, slot in ipairs(texture_slots) do
    if not slot.item_id then
      slot.item_id = item_id
      return slot
    end
  end
  return nil
end

local function release_pending(slot, prop)
  Props.remover(prop)
  if not slot then return end
  if slot.dui and slot.texture then
    SetDuiUrl(slot.dui, blank_url())
  elseif slot.dui then
    DestroyDui(slot.dui)
    slot.dui = nil
  end
  slot.item_id = nil
end

local function record_failure(id, stage)
  local failure = failures[id] or { attempts = 0 }
  failure.attempts = math.min(failure.attempts + 1, 5)
  failure.stage = stage or 'unknown'
  failure.retry_at = GetGameTimer() + math.min(30000, 2000 * 2 ^ failure.attempts)
  failures[id] = failure
  if failure.attempts == 1 then
    Citizen.Trace(('[vhub_outdoors] falha de stream #%d na etapa %s; tentativa %d.\n'):format(
      id, failure.stage, failure.attempts
    ))
  end
end

local function current_item(item, expected_signature)
  local current = world[item.id]
  return running and current and signature(current) == expected_signature
end

local function create_runtime_texture(txd, txn_name, dui_handle)
  if type(Citizen) ~= 'table'
      or type(Citizen.InvokeNative) ~= 'function'
      or type(Citizen.ResultAsLong) ~= 'function'
      or type(Citizen.ReturnResultAnyway) ~= 'function' then
    return nil
  end
  local ok, texture = pcall(function()
    return Citizen.InvokeNative(
      CREATE_RUNTIME_TEXTURE_FROM_DUI_HANDLE,
      txd,
      txn_name,
      dui_handle,
      Citizen.ResultAsLong(),
      Citizen.ReturnResultAnyway()
    )
  end)
  if not ok or not texture or texture == 0 then return nil end
  return texture
end

local function initialize_slot(slot, item, expected_signature)
  if slot.dui and slot.texture and slot.txd then
    SetDuiUrl(slot.dui, display_url(item))
    return true
  end

  local dui = CreateDui(
    display_url(item),
    CFG.renderer.dui_width,
    CFG.renderer.dui_height
  )
  if not dui or dui == 0 then return false, 'dui_create' end
  slot.dui = dui

  local deadline = GetGameTimer() + CFG.renderer.dui_timeout_ms
  while current_item(item, expected_signature)
      and not IsDuiAvailable(dui)
      and GetGameTimer() < deadline do
    Wait(0)
  end
  if not current_item(item, expected_signature) or not IsDuiAvailable(dui) then
    DestroyDui(dui)
    slot.dui = nil
    return false, current_item(item, expected_signature) and 'dui_ready' or 'cancelled'
  end

  local txd = slot.txd or CreateRuntimeTxd(slot.txd_name)
  if not txd or txd == 0 then
    DestroyDui(dui)
    slot.dui = nil
    return false, 'txd'
  end
  slot.txd = txd

  local dui_handle = GetDuiHandle(dui)
  local texture = type(dui_handle) == 'string' and dui_handle ~= ''
    and create_runtime_texture(txd, slot.txn_name, dui_handle)
    or nil
  if not texture then
    DestroyDui(dui)
    slot.dui = nil
    slot.generation = slot.generation + 1
    slot.txn_name = slot.txn_base .. '_' .. slot.generation
    return false, 'texture_handle'
  end

  slot.texture = texture
  return true
end

local function animated_media(item)
  if item.media_type ~= 'image' then return true end
  local path = item.source:match('^[^?]+') or item.source
  return path:lower():sub(-4) == '.gif'
end

local function visible_media(item)
  local dx = item.bottom_right.x - item.top_left.x
  local dy = item.bottom_right.y - item.top_left.y
  local width = math.sqrt(dx * dx + dy * dy)
  local height = math.abs(item.bottom_right.z - item.top_left.z)
  local radius = math.max(1.0, math.sqrt(width * width + height * height) * 0.5)
  return IsSphereVisible(item.center.x, item.center.y, item.center.z, radius)
end

local function streaming_limit(item, loaded)
  local preset = item.size and CFG.sizes[item.size] or nil
  local visual = preset and preset.visual or nil
  if type(visual) == 'table' then
    return loaded and visual.unload_distance or visual.load_distance
  end
  return loaded and CFG.renderer.unload_distance or CFG.renderer.load_distance
end

local function create_stream(item)
  if streamed[item.id] or creating[item.id] then return end
  local expected_signature = signature(item)
  creating[item.id] = expected_signature

  local slot = acquire_slot(item.id)
  if not slot then
    creating[item.id] = nil
    return
  end

  local prop = nil
  local surface = nil
  local preset = item.size and CFG.sizes[item.size] or nil
  if preset then
    local hash = Props.carregarModelo(preset)
    if not current_item(item, expected_signature) then
      if hash then SetModelAsNoLongerNeeded(hash) end
      release_pending(slot)
      creating[item.id] = nil
      return
    end
    local normal = Props.normalDaGeometria(item)
    if hash and normal then
      prop, surface = Props.criar(preset, hash, item.center, normal)
    elseif hash then
      SetModelAsNoLongerNeeded(hash)
    end
    if not prop or not surface then
      release_pending(slot, prop)
      creating[item.id] = nil
      record_failure(item.id, 'prop')
      return
    end
  else
    surface = legacy_surface(item)
  end

  local slot_ready, failure_stage = initialize_slot(slot, item, expected_signature)
  if not slot_ready or not current_item(item, expected_signature) then
    release_pending(slot, prop)
    creating[item.id] = nil
    if failure_stage and failure_stage ~= 'cancelled' then
      record_failure(item.id, failure_stage)
    end
    return
  end

  streamed[item.id] = {
    texture = slot.texture,
    prop = prop,
    surface = surface,
    txd_name = slot.txd_name,
    txn_name = slot.txn_name,
    slot = slot,
    signature = expected_signature,
  }
  creating[item.id] = nil
  failures[item.id] = nil
  ensure_render_loop()
end

local function refresh_streaming()
  local player = PlayerPedId()
  if player == 0 or not DoesEntityExist(player) then
    destroy_all()
    return
  end

  local player_coords = GetEntityCoords(player)
  local candidates = {}
  for id, item in pairs(world) do
    local distance = #(player_coords - item.center)
    local limit = streaming_limit(item, streamed[id] ~= nil)
    if distance <= limit then
      candidates[#candidates + 1] = {
        id = id,
        item = item,
        distance = distance,
        loaded = streamed[id] ~= nil,
        visible = visible_media(item),
      }
    end
  end
  table.sort(candidates, function(left, right)
    if left.loaded ~= right.loaded then return left.loaded end
    if left.visible ~= right.visible then return left.visible end
    if left.distance ~= right.distance then return left.distance < right.distance end
    return left.id < right.id
  end)

  local allowed = {}
  local allowed_count = 0
  local animated_count = 0
  for _, candidate in ipairs(candidates) do
    local animated = animated_media(candidate.item)
    if allowed_count >= CFG.limits.max_streamed then break end
    if not animated or animated_count < CFG.limits.max_animated_streamed then
      allowed[candidate.id] = candidate.item
      allowed_count = allowed_count + 1
      if animated then animated_count = animated_count + 1 end
    end
  end

  local stale = {}
  for id, entry in pairs(streamed) do
    local item = allowed[id]
    if not item or entry.signature ~= signature(item)
        or entry.prop and not DoesEntityExist(entry.prop) then
      stale[#stale + 1] = id
    end
  end
  for _, id in ipairs(stale) do destroy_stream(id) end

  local now = GetGameTimer()
  for id, item in pairs(allowed) do
    local failure = failures[id]
    if not streamed[id] and (not failure or now >= failure.retry_at) then
      create_stream(item)
    end
  end
end

local function ensure_supervisor()
  if supervisor_running or next(world) == nil then return end
  supervisor_running = true
  CreateThread(function()
    while running and next(world) ~= nil do
      refresh_streaming()
      local delay = next(streamed) == nil
        and CFG.renderer.idle_check_ms
        or CFG.renderer.active_check_ms
      Wait(delay)
    end
    supervisor_running = false
    if running and next(world) ~= nil then ensure_supervisor() end
  end)
end

local DISPLAY_FAILURES = {
  image_invalid = true,
  image_error = true,
  image_timeout = true,
  video_error = true,
  video_invalid = true,
  video_stalled = true,
  video_timeout = true,
  youtube_stalled = true,
}

RegisterNUICallback('displayFailure', function(data, cb)
  local id = type(data) == 'table' and VHubOutdoors.finite(data.id) or nil
  local stage = type(data) == 'table' and data.stage or nil
  if not id or id % 1 ~= 0 or id < 1 or not DISPLAY_FAILURES[stage] then
    cb({ ok = false })
    return
  end
  if streamed[id] then
    destroy_stream(id)
    record_failure(id, stage)
  end
  cb({ ok = true })
end)

local function apply_snapshot(snapshot)
  if type(snapshot) ~= 'table' or tonumber(snapshot.version) ~= 1
      or type(snapshot.items) ~= 'table' then
    world = {}
    failures = {}
    destroy_all()
    return
  end

  local next_world = {}
  for index = 1, math.min(#snapshot.items, CFG.limits.max_outdoors) do
    local item = normalize_item(snapshot.items[index])
    if item and not next_world[item.id] then next_world[item.id] = item end
  end
  world = next_world

  local stale = {}
  for id, entry in pairs(streamed) do
    local item = world[id]
    if not item or entry.signature ~= signature(item) then stale[#stale + 1] = id end
  end
  for _, id in ipairs(stale) do destroy_stream(id) end
  for id in pairs(failures) do
    if not world[id] then failures[id] = nil end
  end
  refresh_streaming()
  ensure_supervisor()
end

local state_handler = AddStateBagChangeHandler('vhub_outdoors', nil, function(
  bag_name, _, value
)
  if bag_name == 'global' then apply_snapshot(value) end
end)

CreateThread(function()
  apply_snapshot(GlobalState.vhub_outdoors)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  running = false
  if state_handler then RemoveStateBagChangeHandler(state_handler) end
  world = {}
  failures = {}
  destroy_all()
  destroy_slot_assets()
end)
