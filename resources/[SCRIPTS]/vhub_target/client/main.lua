-- client/main.lua — loop de targeting (olho aberto) + seleção via NUI
-- Budget (L-18): com olho FECHADO custo zero (nenhuma thread ativa). Com olho aberto:
--   thread de input a cada frame (necessária p/ DisableControlAction/DrawSprite) e
--   thread de scan a 50 ms (com hit) / 100 ms (sem hit) — padrão upstream ox_target.
-- Cfx Lua (LuaGLM): usa table.wipe — não é Lua 5.4 puro.
---@diagnostic disable: undefined-global, lowercase-global, undefined-field

VHubTarget = VHubTarget or {}

local cfg = VHubTarget.cfg
local lang = VHubTarget.lang
local utils = VHubTarget.utils
local state = VHubTarget.state
local zones = VHubTarget.zones
local cache = VHubTarget.cache
local options = VHubTarget.api.getTargetOptions()

local SendNuiMessage = SendNuiMessage
local GetEntityCoords = GetEntityCoords
local GetEntityType = GetEntityType
local HasEntityClearLosToEntity = HasEntityClearLosToEntity
local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetEntityBonePosition_2 = GetEntityBonePosition_2
local GetEntityModel = GetEntityModel
local IsDisabledControlJustPressed = IsDisabledControlJustPressed
local DisableControlAction = DisableControlAction
local DisablePlayerFiring = DisablePlayerFiring
local GetModelDimensions = GetModelDimensions
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords

local currentTarget = {}
local currentMenu
local menuChanged
local menuHistory = {}
local nearbyZones

local mouseButton = cfg.leftClick and 24 or 25
local debug = cfg.debug
local vec0 = vec3(0, 0, 0)


-- ============================================================
-- FILTRO DE OPÇÃO — decide se uma opção fica oculta p/ o alvo atual
-- ============================================================

-- retorna true se a opção deve ficar oculta (menu, distância, grupo, item, bone, offset, canInteract)
local function shouldHide(option, distance, endCoords, entityHit, entityType, entityModel)
  if option.menuName ~= currentMenu then
    return true
  end

  if distance > (option.distance or 7) then
    return true
  end

  if option.groups and not utils.hasPlayerGotGroup(option.groups) then
    return true
  end

  if option.items and not utils.hasPlayerGotItems(option.items, option.anyItem) then
    return true
  end

  local bone = entityModel and option.bones or nil

  if bone then
    local _type = type(bone)

    if _type == 'string' then
      local boneId = GetEntityBoneIndexByName(entityHit, bone)

      if boneId ~= -1 and #(endCoords - GetEntityBonePosition_2(entityHit, boneId)) <= 2 then
        bone = boneId
      else
        return true
      end
    elseif _type == 'table' then
      local closestBone, boneDistance

      for j = 1, #bone do
        local boneId = GetEntityBoneIndexByName(entityHit, bone[j])

        if boneId ~= -1 then
          local dist = #(endCoords - GetEntityBonePosition_2(entityHit, boneId))

          if dist <= (boneDistance or 1) then
            closestBone = boneId
            boneDistance = dist
          end
        end
      end

      if closestBone then
        bone = closestBone
      else
        return true
      end
    end
  end

  local offset = entityModel and option.offset or nil

  if offset then
    if not option.absoluteOffset then
      local min, max = GetModelDimensions(entityModel)
      offset = (max - min) * offset + min
    end

    offset = GetOffsetFromEntityInWorldCoords(entityHit, offset.x, offset.y, offset.z)

    if #(endCoords - offset) > (option.offsetSize or 1) then
      return true
    end
  end

  if option.canInteract then
    local success, resp = pcall(option.canInteract, entityHit, distance, endCoords, option.name, bone)
    return not success or not resp
  end
end


-- ============================================================
-- LOOP DE TARGETING
-- ============================================================

-- inicia o modo de mira (olho); sai quando o estado desativa
local function startTargeting()
  if state.isDisabled() or state.isActive() or IsNuiFocused() or IsPauseMenuActive() then return end

  VHubTarget.refreshCache()
  state.setActive(true)

  local flag = 511
  local hit, entityHit, endCoords, distance, lastEntity, entityType, entityModel, hasTarget, zonesChanged
  local zoneOptionSets = {}

  -- thread de input/draw: precisa rodar por frame enquanto o olho está aberto
  Citizen.CreateThread(function()
    local dict, texture = utils.getTexture()
    local lastCoords

    while state.isActive() do
      lastCoords = endCoords == vec0 and lastCoords or endCoords or vec0

      if debug then
        DrawMarker(28, lastCoords.x, lastCoords.y, lastCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
          0.2, 0.2, 0.2, 255, 42, 24, 100, false, false, 0, true, false, false, false)
      end

      zones.drawSprites(dict, texture)
      DisablePlayerFiring(cache.playerId, true)
      DisableControlAction(0, 25, true)
      DisableControlAction(0, 140, true)
      DisableControlAction(0, 141, true)
      DisableControlAction(0, 142, true)

      if state.isNuiFocused() then
        DisableControlAction(0, 1, true)
        DisableControlAction(0, 2, true)

        if not hasTarget or options and IsDisabledControlJustPressed(0, 25) then
          state.setNuiFocus(false, false)
        end
      elseif hasTarget and IsDisabledControlJustPressed(0, mouseButton) then
        state.setNuiFocus(true, true)
      end

      Citizen.Wait(0)
    end

    SetStreamedTextureDictAsNoLongerNeeded(dict)
  end)

  -- thread de scan: raycast + resolução de opções (50/100 ms)
  while state.isActive() do
    if not state.isNuiFocused() and state.isLocked() then
      state.setActive(false)
      break
    end

    local playerCoords = GetEntityCoords(cache.ped)
    hit, entityHit, endCoords = utils.raycastFromCamera(flag, 20)
    distance = #(playerCoords - endCoords)

    if entityHit ~= 0 and entityHit ~= lastEntity then
      local success, result = pcall(GetEntityType, entityHit)
      entityType = success and result or 0
    end

    if entityType == 0 then
      local _flag = flag == 511 and 26 or 511
      local _hit, _entityHit, _endCoords = utils.raycastFromCamera(_flag, 20)
      local _distance = #(playerCoords - _endCoords)

      if _distance < distance then
        flag, hit, entityHit, endCoords, distance = _flag, _hit, _entityHit, _endCoords, _distance

        if entityHit ~= 0 then
          local success, result = pcall(GetEntityType, entityHit)
          entityType = success and result or 0
        end
      end
    end

    nearbyZones, zonesChanged = zones.getNearby(endCoords)

    local entityChanged = entityHit ~= lastEntity
    local newOptions = (zonesChanged or entityChanged or menuChanged) and true

    if entityHit > 0 and entityChanged then
      currentMenu = nil

      if flag ~= 511 then
        entityHit = HasEntityClearLosToEntity(entityHit, cache.ped, 7) and entityHit or 0
      end

      if lastEntity ~= entityHit and debug then
        if lastEntity then
          SetEntityDrawOutline(lastEntity, false)
        end

        if entityType ~= 1 then
          SetEntityDrawOutline(entityHit, true)
        end
      end

      if entityHit > 0 then
        local success, result = pcall(GetEntityModel, entityHit)
        entityModel = success and result
      end
    end

    if hasTarget and (zonesChanged or entityChanged and hasTarget > 1) then
      SendNuiMessage('{"event": "leftTarget"}')

      if entityChanged then options:wipe() end

      if debug and lastEntity > 0 then SetEntityDrawOutline(lastEntity, false) end

      hasTarget = false
    end

    if newOptions and entityModel and entityHit > 0 then
      options:set(entityHit, entityType, entityModel)
    end

    lastEntity = entityHit
    currentTarget.entity = entityHit
    currentTarget.coords = endCoords
    currentTarget.distance = distance
    local hidden = 0
    local totalOptions = 0

    for k, v in pairs(options) do
      local optionCount = #v
      local dist = k == '__global' and 0 or distance
      totalOptions = totalOptions + optionCount

      for i = 1, optionCount do
        local option = v[i]
        local hide = shouldHide(option, dist, endCoords, entityHit, entityType, entityModel)

        if option.hide ~= hide then
          option.hide = hide
          newOptions = true
        end

        if hide then hidden = hidden + 1 end
      end
    end

    if zonesChanged then table.wipe(zoneOptionSets) end

    for i = 1, #nearbyZones do
      local zoneOptions = nearbyZones[i].options
      local optionCount = #zoneOptions
      totalOptions = totalOptions + optionCount
      zoneOptionSets[i] = zoneOptions

      for j = 1, optionCount do
        local option = zoneOptions[j]
        local hide = shouldHide(option, distance, endCoords, entityHit)

        if option.hide ~= hide then
          option.hide = hide
          newOptions = true
        end

        if hide then hidden = hidden + 1 end
      end
    end

    if newOptions then
      if hasTarget == 1 and (totalOptions - hidden) > 1 then
        hasTarget = true
      end

      if hasTarget and hidden == totalOptions then
        if hasTarget and hasTarget ~= 1 then
          hasTarget = false
          SendNuiMessage('{"event": "leftTarget"}')
        end
      elseif menuChanged or hasTarget ~= 1 and hidden ~= totalOptions then
        hasTarget = options.size

        local firstGlobal = options.__global[1]
        if currentMenu and (not firstGlobal or firstGlobal.name ~= 'builtin:goback') then
          table.insert(options.__global, 1, {
            icon = 'back',
            label = lang.go_back,
            name = 'builtin:goback',
            menuName = currentMenu,
            openMenu = 'home'
          })
        end

        SendNuiMessage(json.encode({
          event = 'setTarget',
          options = options,
          zones = zoneOptionSets,
        }, { sort_keys = true }))
      end

      menuChanged = false
    end

    if cfg.toggleHotkey and IsPauseMenuActive() then
      state.setActive(false)
    end

    if not hasTarget or hasTarget == 1 then
      flag = flag == 511 and 26 or 511
    end

    Citizen.Wait(hit and 50 or 100)
  end

  if lastEntity and debug then
    SetEntityDrawOutline(lastEntity, false)
  end

  state.setNuiFocus(false)
  SendNuiMessage('{"event": "visible", "state": false}')
  table.wipe(currentTarget)
  options:wipe()

  if nearbyZones then table.wipe(nearbyZones) end
end


-- ============================================================
-- KEYBIND — RegisterKeyMapping nativo (sem ox_lib)
-- ============================================================

if cfg.toggleHotkey then
  RegisterCommand('+vhub_target', function()
    if state.isActive() then
      state.setActive(false)
    else
      startTargeting()
    end
  end, false)
  RegisterCommand('-vhub_target', function() end, false)
else
  RegisterCommand('+vhub_target', startTargeting, false)
  RegisterCommand('-vhub_target', function()
    state.setActive(false)
  end, false)
end

RegisterKeyMapping('+vhub_target', lang.toggle_targeting, 'keyboard', cfg.hotkey)


-- ============================================================
-- SELEÇÃO (NUI → opção)
-- ============================================================

-- monta a resposta entregue ao consumidor (limpa campos internos; netid p/ server)
local function getResponse(option, server)
  local response = table.clone(option)
  response.entity = currentTarget.entity
  response.zone = currentTarget.zone
  response.coords = currentTarget.coords
  response.distance = currentTarget.distance

  if server then
    response.entity = response.entity ~= 0 and NetworkGetEntityIsNetworked(response.entity) and
      NetworkGetNetworkIdFromEntity(response.entity) or 0
  end

  response.icon = nil
  response.groups = nil
  response.items = nil
  response.canInteract = nil
  response.onSelect = nil
  response.export = nil
  response.event = nil
  response.serverEvent = nil
  response.command = nil

  return response
end

RegisterNUICallback('select', function(data, cb)
  cb(1)

  local zone = data[3] and nearbyZones[data[3]]
  local option = zone and zone.options[data[2]] or options[data[1]] and options[data[1]][data[2]]

  if option then
    if option.openMenu then
      local menuDepth = #menuHistory

      if option.name == 'builtin:goback' then
        option.menuName = option.openMenu
        option.openMenu = menuHistory[menuDepth]

        if menuDepth > 0 then
          menuHistory[menuDepth] = nil
        end
      else
        menuHistory[menuDepth + 1] = currentMenu
      end

      menuChanged = true
      currentMenu = option.openMenu ~= 'home' and option.openMenu or nil

      options:wipe()
    else
      state.setNuiFocus(false)
    end

    currentTarget.zone = zone and zone.id or nil

    if option.onSelect then
      option.onSelect(getResponse(option))
    elseif option.export then
      exports[option.resource or zone.resource][option.export](nil, getResponse(option))
    elseif option.event then
      TriggerEvent(option.event, getResponse(option))
    elseif option.serverEvent then
      TriggerServerEvent(option.serverEvent, getResponse(option, true))
    elseif option.command then
      ExecuteCommand(option.command)
    end

    if option.menuName == 'home' then return end
  end

  if not (option and option.openMenu) and IsNuiFocused() then
    state.setActive(false)
  end
end)
