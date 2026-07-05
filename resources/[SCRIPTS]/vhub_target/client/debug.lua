-- client/debug.lua — zonas e opções de teste (SOMENTE com cfg.debug = true; dev only)
---@diagnostic disable: undefined-global, lowercase-global

local E = VHubTarget.E
local lang = VHubTarget.lang

AddEventHandler(E.DEBUG, function(data)
  if not VHubTarget.cfg.debug then return end

  if data.entity and GetEntityType(data.entity) > 0 then
    data.archetype = GetEntityArchetypeName(data.entity)
    data.model = GetEntityModel(data.entity)
  end

  print(json.encode(data, { indent = true }))
end)

if not VHubTarget.cfg.debug then return end

local api = VHubTarget.api

api.addBoxZone({
  coords = vec3(442.5363, -1017.666, 28.85637),
  size = vec3(3, 3, 3),
  rotation = 45,
  drawSprite = true,
  options = {
    { name = 'debug_box', event = E.DEBUG, icon = 'box', label = lang.debug_box },
  }
})

api.addSphereZone({
  coords = vec3(440.5363, -1015.666, 28.85637),
  radius = 3,
  drawSprite = true,
  options = {
    { name = 'debug_sphere', event = E.DEBUG, icon = 'circle', label = lang.debug_sphere },
  }
})

api.addModel(joaat('police'), {
  { name = 'debug_model', event = E.DEBUG, icon = 'lock', label = lang.debug_police_car },
})

api.addGlobalPed({
  { name = 'debug_ped', event = E.DEBUG, icon = 'person', label = lang.debug_ped },
})

api.addGlobalVehicle({
  { name = 'debug_vehicle', event = E.DEBUG, icon = 'car', label = lang.debug_vehicle },
})

api.addGlobalObject({
  { name = 'debug_object', event = E.DEBUG, icon = 'flask', label = lang.debug_object },
})

api.addGlobalOption({
  { name = 'debug_global', icon = 'globe', label = lang.debug_global, openMenu = 'debug_global' },
})

api.addGlobalOption({
  { name = 'debug_global2', event = E.DEBUG, icon = 'globe', label = lang.debug_global .. ' 2', menuName = 'debug_global' },
})
