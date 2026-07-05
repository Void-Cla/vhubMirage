-- client/init.lua — cache leve de ped/veículo do jogador local
-- Budget (L-18): 1 thread a 2 Hz (500 ms), 2 natives por tick — custo fixo O(1).
-- O loop de targeting (main.lua) chama VHubTarget.refreshCache() ao abrir o olho,
-- garantindo valor fresco no início da interação.
---@diagnostic disable: undefined-global, lowercase-global

VHubTarget = VHubTarget or {}

VHubTarget.cache = {
  ped      = PlayerPedId(),
  playerId = PlayerId(),
  vehicle  = false,
}

local cache = VHubTarget.cache

-- atualiza ped/veículo do cache imediatamente (chamado ao iniciar targeting)
function VHubTarget.refreshCache()
  cache.ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(cache.ped, false)
  cache.vehicle = veh ~= 0 and veh or false
end

-- guard de saída: encerra a thread no stop do resource (evita 2 threads após restart, L-18/R8)
local _alive = true

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then _alive = false end
end)

Citizen.CreateThread(function()
  while _alive do
    VHubTarget.refreshCache()
    Citizen.Wait(500)
  end
end)
