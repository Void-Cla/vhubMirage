---@diagnostic disable: undefined-global

-- client/shop.lua — NPCs da oficina; UI e compra pertencem ao vhub_inventory.
local LOJAS = VHubCustom.cfg.lojas
local peds = {}
local IDS = { performance = 'oficina_pecas', mecanica = 'mecanica_suprimentos' }

local function criarNpc(chave, loja)
  local model = joaat(loja.model)
  RequestModel(model)
  local limite = GetGameTimer() + 5000
  while not HasModelLoaded(model) and GetGameTimer() < limite do Wait(25) end
  if not HasModelLoaded(model) then VHubCustom.log(('[CRITICAL] modelo da loja %s indisponível'):format(chave)); return end
  local ped = CreatePed(4, model, loja.x, loja.y, loja.z - 1.0, loja.h, false, false)
  SetModelAsNoLongerNeeded(model)
  if ped == 0 or not DoesEntityExist(ped) then return end
  peds[#peds + 1] = ped
  SetEntityAsMissionEntity(ped, true, true); SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true); SetPedCanRagdoll(ped, false)
  exports.vhub_target:addLocalEntity(ped, {
    { name = 'vhub_custom:loja:' .. chave, label = loja.alvo, icon = 'wrench', distance = loja.raio,
      onSelect = function() exports.vhub_inventory:openStore(IDS[chave]) end },
  })
end

CreateThread(function() for chave, loja in pairs(LOJAS or {}) do if IDS[chave] then criarNpc(chave, loja) end end end)
AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  for _, ped in ipairs(peds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
end)
