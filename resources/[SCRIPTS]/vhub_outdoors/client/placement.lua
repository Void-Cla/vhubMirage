-- client/placement.lua - posicionamento efemero por superficie validada

local CFG = VHubOutdoors.cfg
local E = VHubOutdoors.E
local Props = VHubOutdoors.Props
local placement = nil
local creator_open = false

local function creator_sizes()
  local sizes = {}
  for name, preset in pairs(CFG.sizes) do
    sizes[#sizes + 1] = {
      id = name,
      label = preset.label,
      hint = preset.hint,
      width = preset.width,
      height = preset.height,
    }
  end
  table.sort(sizes, function(left, right)
    return CFG.sizes[left.id].order < CFG.sizes[right.id].order
  end)
  return sizes
end

local function creator_items(raw)
  local items = {}
  if type(raw) ~= 'table' then return items end
  for index = 1, math.min(#raw, CFG.limits.max_outdoors) do
    local item = raw[index]
    local id = type(item) == 'table' and VHubOutdoors.finite(item.id) or nil
    local title = type(item) == 'table' and item.title or nil
    local media_type = type(item) == 'table' and item.media_type or nil
    local preset = nil
    if type(item) == 'table' then
      local _, resolved = VHubOutdoors.resolveSize(item.size)
      preset = resolved
    end
    if id and id % 1 == 0 and id >= 1 and id <= 2147483647
        and type(title) == 'string' and #title <= CFG.limits.max_title
        and (media_type == 'image' or media_type == 'video' or media_type == 'youtube') then
      items[#items + 1] = {
        id = id,
        title = title,
        media_type = media_type,
        size_label = preset and preset.label or 'personalizado',
      }
    end
  end
  return items
end

local function notify(notification_type, message)
  TriggerEvent('vHub:notify', {
    type = notification_type,
    title = 'Outdoors',
    msg = message,
  })
end

local function encerrar_posicionamento(current)
  if not current then return end
  if placement == current then placement = nil end
  if current.model_hash then SetModelAsNoLongerNeeded(current.model_hash) end
  current.model_hash = nil
  Props.remover(current.preview)
  current.preview = nil
end

local function close_creator()
  if not creator_open then return end
  creator_open = false
  SetNuiFocus(false, false)
  SendNUIMessage({ type = 'creator:close', data = {} })
end

local function open_creator(payload)
  TriggerEvent('vhub_outdoors:client:closeRemote')
  local items = creator_items(type(payload) == 'table' and payload.items or nil)
  if creator_open then
    SendNUIMessage({
      type = 'creator:items',
      data = { items = items },
    })
    return
  end
  encerrar_posicionamento(placement)
  creator_open = true
  SetNuiFocus(true, true)
  SendNUIMessage({
    type = 'creator:open',
    data = {
      sizes = creator_sizes(),
      items = items,
    },
  })
end

local function rotation_to_direction(rotation)
  local x = math.rad(rotation.x)
  local z = math.rad(rotation.z)
  return vec3(
    -math.sin(z) * math.abs(math.cos(x)),
    math.cos(z) * math.abs(math.cos(x)),
    math.sin(x)
  )
end

local function normalized_surface(coords, hit_normal, preset)
  local x = VHubOutdoors.finite(hit_normal and hit_normal.x)
  local y = VHubOutdoors.finite(hit_normal and hit_normal.y)
  local z = VHubOutdoors.finite(hit_normal and hit_normal.z)
  local cx = VHubOutdoors.finite(coords and coords.x)
  local cy = VHubOutdoors.finite(coords and coords.y)
  local cz = VHubOutdoors.finite(coords and coords.z)
  if not x or not y or not z or not cx or not cy or not cz
      or math.abs(x) > 1.1 or math.abs(y) > 1.1 or math.abs(z) > 1.1 then
    return nil
  end

  local magnitude = math.sqrt(x * x + y * y + z * z)
  if magnitude < 0.8 or magnitude > 1.2 then return nil end
  local anchor = { x = cx, y = cy, z = cz }

  if preset.modo == 'chao' then
    local inclinacao = math.sqrt(x * x + y * y)
    if z < 0.75 or inclinacao > CFG.limits.max_surface_tilt then return nil end
    local jogador = GetEntityCoords(PlayerPedId())
    local frente_x = jogador.x - cx
    local frente_y = jogador.y - cy
    local horizontal = math.sqrt(frente_x * frente_x + frente_y * frente_y)
    if horizontal < 0.25 then return nil end
    local normal = {
      x = frente_x / horizontal,
      y = frente_y / horizontal,
      z = 0.0,
    }
    local center = Props.centroDaTela(anchor, preset, normal)
    if not center then return nil end
    return {
      anchor = anchor,
      center = center,
      normal = normal,
    }
  end

  local horizontal = math.sqrt(x * x + y * y)
  if horizontal < 0.75 or math.abs(z) > CFG.limits.max_surface_tilt then return nil end
  return {
    anchor = anchor,
    center = anchor,
    normal = { x = x / horizontal, y = y / horizontal, z = 0.0 },
  }
end

local function update_raycast(current)
  if current.ray_handle then
    local status, hit, coords, normal, entity = GetShapeTestResult(current.ray_handle)
    if status == 2 then
      current.ray_handle = nil
      local valid_hit = hit == true or hit == 1
      local valid_entity = not entity or entity == 0
        or DoesEntityExist(entity) and IsEntityStatic(entity)
      current.ray_hit = valid_hit and valid_entity
        and normalized_surface(coords, normal, current.preset)
        or nil
    elseif status == 0 then
      current.ray_handle = nil
      current.ray_hit = nil
    end
  end

  if not current.ray_handle then
    local origin = GetGameplayCamCoord()
    local direction = rotation_to_direction(GetGameplayCamRot(2))
    local target = origin + direction * current.ray_distance
    current.ray_handle = StartShapeTestRay(
      origin.x, origin.y, origin.z,
      target.x, target.y, target.z,
      17, PlayerPedId(), 0
    )
  end
  return current.ray_hit
end

local function drain_raycast(current)
  local limite = GetGameTimer() + 1000
  while current.ray_handle and GetGameTimer() < limite do
    Wait(0)
    local status = GetShapeTestResult(current.ray_handle)
    if status == 0 or status == 2 then current.ray_handle = nil end
  end
  current.ray_handle = nil
end

local function help_text(message)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(message)
  EndTextCommandDisplayHelp(0, false, true, -1)
end

local function draw_preview(surface)
  local top_left = surface.top_left
  local top_right = surface.top_right
  local bottom_left = surface.bottom_left
  local bottom_right = surface.bottom_right
  DrawPoly(
    bottom_right.x, bottom_right.y, bottom_right.z,
    top_right.x, top_right.y, top_right.z,
    top_left.x, top_left.y, top_left.z,
    214, 173, 96, 110
  )
  DrawPoly(
    top_left.x, top_left.y, top_left.z,
    bottom_left.x, bottom_left.y, bottom_left.z,
    bottom_right.x, bottom_right.y, bottom_right.z,
    214, 173, 96, 110
  )
end

local function finish(current, surface)
  encerrar_posicionamento(current)
  local payload = {
    nonce = current.nonce,
    center = {
      x = surface.center.x,
      y = surface.center.y,
      z = surface.center.z,
    },
    normal = {
      x = surface.normal.x,
      y = surface.normal.y,
      z = surface.normal.z,
    },
  }
  if current.remote then payload.token = current.token end
  TriggerServerEvent(
    current.remote and E.SUBMIT_REMOTE_MOVE or E.SUBMIT_PLACEMENT,
    payload
  )
end

local function carregar_preview(current)
  CreateThread(function()
    local hash = Props.carregarModelo(current.preset)
    if placement ~= current then
      if hash then SetModelAsNoLongerNeeded(hash) end
      return
    end
    if not hash then
      encerrar_posicionamento(current)
      notify('erro', 'Falha ao carregar o modelo do outdoor.')
      return
    end
    current.model_hash = hash
    current.model_ready = true
  end)
end

local function run(current)
  carregar_preview(current)
  CreateThread(function()
    while placement == current do
      Wait(0)
      if placement ~= current then break end
      DisableControlAction(0, 24, true)
      DisableControlAction(0, 25, true)

      local surface = update_raycast(current)
      local prop_surface = nil
      if surface and current.model_ready then
        local preview_center = Props.aplicarDeslocamento(surface.center, surface.normal)
        if current.preview then
          SetEntityVisible(current.preview, true, false)
          prop_surface = Props.alinhar(
            current.preview, current.preset, preview_center, surface.normal
          )
        else
          current.preview, prop_surface = Props.criar(
            current.preset,
            current.model_hash,
            preview_center,
            surface.normal,
            155
          )
          current.model_hash = nil
          if not current.preview then
            encerrar_posicionamento(current)
            notify('erro', 'Falha ao criar a pre-visualizacao.')
            break
          end
        end

        local anchor = surface.anchor
        DrawMarker(
          28, anchor.x, anchor.y, anchor.z,
          0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
          0.08, 0.08, 0.08,
          214, 173, 96, 220,
          false, false, 2, false, nil, nil, false
        )
        if prop_surface then draw_preview(prop_surface) end
      elseif current.preview then
        SetEntityVisible(current.preview, false, false)
      end

      help_text(current.model_ready and current.help or 'Carregando modelo do outdoor...')
      if IsControlJustReleased(0, 177) then
        encerrar_posicionamento(current)
        notify('aviso', 'Posicionamento cancelado.')
      elseif surface and prop_surface and IsControlJustReleased(0, 38) then
        finish(current, surface)
      end
    end
    Props.remover(current.preview)
    current.preview = nil
    drain_raycast(current)
  end)
end

local function begin_placement(payload, remote)
  if type(payload) ~= 'table' then return end
  local nonce = VHubOutdoors.finite(payload.nonce)
  local ray_distance = VHubOutdoors.finite(payload.ray_distance)
  local size_name, preset = VHubOutdoors.resolveSize(payload.size)
  local token = remote and payload.token or nil
  if not nonce or nonce % 1 ~= 0 or nonce < 1 or not preset
      or not ray_distance or ray_distance < 5.0
      or ray_distance > CFG.limits.ray_distance
      or remote and (type(token) ~= 'string'
        or #token ~= 32 or not token:match('^%x+$')) then
    return
  end

  TriggerEvent('vhub_outdoors:client:closeRemote')
  close_creator()
  encerrar_posicionamento(placement)
  local instruction = preset.modo == 'chao'
    and 'Mire no chao'
    or 'Mire no centro da parede'
  placement = {
    nonce = nonce,
    ray_distance = ray_distance,
    size = size_name,
    preset = preset,
    remote = remote == true,
    token = token,
    help = ('%s: %.2f x %.2f m. %s e pressione ~INPUT_CONTEXT~. '
      .. '~INPUT_CELLPHONE_CANCEL~ cancela.'):format(
      preset.label:upper(),
      preset.width,
      preset.height,
      instruction
    ),
  }
  notify('info', ('Outdoor %s: %s.'):format(preset.label, instruction:lower()))
  run(placement)
end

RegisterNetEvent(E.BEGIN_PLACEMENT, function(payload)
  begin_placement(payload, false)
end)

RegisterNetEvent(E.BEGIN_REMOTE_MOVE, function(payload)
  begin_placement(payload, true)
end)

RegisterNetEvent(E.OPEN_CREATE_UI, function(payload)
  open_creator(payload)
end)

RegisterNetEvent(E.UPDATE_ADMIN, function(payload)
  if not creator_open or type(payload) ~= 'table' then return end
  SendNUIMessage({
    type = 'creator:items',
    data = {
      items = creator_items(payload.items),
      ok = payload.ok == true,
      err = type(payload.err) == 'string' and payload.err or nil,
    },
  })
end)

AddEventHandler('vhub_outdoors:client:closeCreator', close_creator)

RegisterNUICallback('creatorClose', function(_, cb)
  close_creator()
  cb({ ok = true })
end)

RegisterNUICallback('creatorSubmit', function(data, cb)
  if not creator_open or type(data) ~= 'table' then
    cb({ ok = false, err = 'invalid_state' })
    return
  end
  for key in pairs(data) do
    if key ~= 'size' and key ~= 'url' then
      cb({ ok = false, err = 'invalid_payload' })
      return
    end
  end

  local size_name = VHubOutdoors.resolveSize(data.size)
  local valid_media = VHubOutdoors.parseMedia(data.url)
  if not size_name then
    cb({ ok = false, err = 'invalid_size' })
    return
  end
  if not valid_media then
    cb({ ok = false, err = 'invalid_media' })
    return
  end

  close_creator()
  TriggerServerEvent(E.REQUEST_PLACEMENT, {
    size = size_name,
    url = data.url,
  })
  cb({ ok = true })
end)

RegisterNUICallback('creatorRemove', function(data, cb)
  if not creator_open or type(data) ~= 'table' then
    cb({ ok = false, err = 'invalid_state' })
    return
  end
  for key in pairs(data) do
    if key ~= 'id' then
      cb({ ok = false, err = 'invalid_payload' })
      return
    end
  end
  local id = VHubOutdoors.finite(data.id)
  if not id or id % 1 ~= 0 or id < 1 or id > 2147483647 then
    cb({ ok = false, err = 'invalid_payload' })
    return
  end
  TriggerServerEvent(E.REQUEST_REMOVE, { id = id })
  cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  encerrar_posicionamento(placement)
  close_creator()
end)
