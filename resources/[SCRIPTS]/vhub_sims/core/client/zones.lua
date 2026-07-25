-- zones.lua — registro único das vitrines no vhub_target
---@diagnostic disable: undefined-global

local E = VHubSims.E

local function open(shopId)
  TriggerServerEvent(E.SRV_OPEN_REQUEST, { shop_id = shopId })
end

local function onFoot()
  return not IsPedInAnyVehicle(PlayerPedId(), false)
end

Citizen.CreateThread(function()
  for _, shop in ipairs(VHubSims.shops) do
    exports.vhub_target:addBoxZone({
      coords = { x = shop.coords.x, y = shop.coords.y, z = shop.coords.z },
      size = { x = shop.size.x, y = shop.size.y, z = shop.size.z },
      rotation = shop.rotation,
      options = {
        {
          name = 'vhub_sims:' .. shop.id,
          label = shop.label,
          icon = 'person',
          distance = 2.0,
          canInteract = onFoot,
          onSelect = function() open(shop.id) end,
        },
      },
    })
  end
end)
