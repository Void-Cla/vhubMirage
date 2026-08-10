-- client/presence.lua — blips e NPCs das concessionárias no mapa/mundo
-- Lê VHubConce.cfg diretamente (shared_script): sem dependência de SETUP do garage.
-- Peds locais (não networked): cada cliente cria o seu. Cleanup no resource stop.
---@diagnostic disable: undefined-global

local _blips = {}
local _peds  = {}


-- ============================================================
-- UTILITÁRIOS
-- ============================================================

-- cria blip e retorna handle
local function makeBlip(x, y, z, sprite, color, scale, label)
  local b = AddBlipForCoord(x, y, z)
  SetBlipSprite(b, sprite)
  SetBlipColour(b, color)
  SetBlipScale(b, scale)
  SetBlipAsShortRange(b, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(label)
  EndTextCommandSetBlipName(b)
  return b
end

-- aguarda modelo carregado (timeout 5s)
local function loadModel(hash)
  RequestModel(hash)
  local waited = 0
  while not HasModelLoaded(hash) do
    Citizen.Wait(50)
    waited = waited + 50
    if waited >= 5000 then return false end
  end
  return true
end

-- cria ped estático invencível congelado; retorna handle ou nil
local function spawnAmbientPed(modelName, x, y, z, heading)
  local hash = GetHashKey(modelName)
  if not loadModel(hash) then return nil end
  local ped = CreatePed(4, hash, x, y, z, heading or 0.0, false, false)
  SetEntityInvincible(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  FreezeEntityPosition(ped, true)
  SetPedFleeAttributes(ped, 0, false)
  SetPedCombatAttributes(ped, 46, true)
  SetModelAsNoLongerNeeded(hash)
  return ped
end


-- ============================================================
-- SPAWN INICIAL (config local — sem dep. de SETUP)
-- ============================================================

Citizen.CreateThread(function()
  Citizen.Wait(0)
  for _, c in ipairs(VHubConce.cfg.concessionarias or {}) do
    local bp = c.blip or {}
    _blips[#_blips + 1] = makeBlip(
      c.coord.x, c.coord.y, c.coord.z,
      bp.sprite or 326,
      bp.color  or 3,
      bp.scale  or 0.85,
      c.label or 'Concessionária'
    )
    local ped = spawnAmbientPed('cs_barry', c.coord.x, c.coord.y, c.coord.z, 0.0)
    if ped then
      _peds[#_peds + 1] = ped
      local concId = c.id
      local label  = c.label or 'Concessionária'
      pcall(function()
        exports.vhub_target:addLocalEntity({ ped }, {
          {
            name     = 'vhub_conce_open_' .. concId,
            label    = label,
            icon     = 'car',
            distance = 3.0,
            onSelect = function()
              TriggerEvent('vhub_conce:abrirCatalogo', concId)
            end,
          },
        })
      end)
    end
  end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  for _, b in ipairs(_blips) do if DoesBlipExist(b)    then RemoveBlip(b)    end end
  for _, p in ipairs(_peds)  do if DoesEntityExist(p)  then DeleteEntity(p)  end end
end)
