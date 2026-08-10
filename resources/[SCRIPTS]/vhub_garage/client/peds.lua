-- client/peds.lua — NPCs imersivos nas zonas de garagem e feirinha
-- Peds locais (não networked): cada cliente cria o seu. Cleanup no resource stop.
-- Garagens: spawnam do cfg local (mesmo padrão do vhub_money, sem dep. de SETUP).
-- Ferinha: spawna após SETUP (handle tracking idempotente).
-- NPCs de concessionária são criados pelo próprio vhub_conce (ownership correto).
---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local state = VHubGarage.state

local _staticHandles = {}  -- garagens (cfg local, 1x por sessão)
local _dynHandles    = {}  -- ferinha (limpa a cada SETUP)


-- ============================================================
-- UTILITÁRIOS
-- ============================================================

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
  local ped = CreatePed(4, hash, x, y, z, heading, false, false)
  SetEntityInvincible(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  FreezeEntityPosition(ped, true)
  SetPedFleeAttributes(ped, 0, false)
  SetPedCombatAttributes(ped, 46, true)
  SetModelAsNoLongerNeeded(hash)
  return ped
end


-- ============================================================
-- GARAGENS — peds do cfg local (sem dep. de SETUP, spawnam 1x)
-- ============================================================

CreateThread(function()
  Citizen.Wait(0)
  for _, g in ipairs(VHubGarage.cfg.garagens or {}) do
    local ped = spawnAmbientPed('s_m_m_dockwork_01',
      g.coord.x, g.coord.y, g.coord.z, g.h or 0.0)
    if ped then _staticHandles[#_staticHandles + 1] = ped end
  end
end)


-- ============================================================
-- FERINHA — ped após SETUP (idempotente)
-- ============================================================

local function spawnDynamicPeds()
  for _, handle in ipairs(_dynHandles) do
    if DoesEntityExist(handle) then DeleteEntity(handle) end
  end
  _dynHandles = {}

  -- s_m_m_hairdress_01 na feirinha (imersão apenas)
  if state.leilao then
    local l = state.leilao
    local ped = spawnAmbientPed('s_m_m_hairdress_01', l.x, l.y, l.z, 0.0)
    if ped then _dynHandles[#_dynHandles + 1] = ped end
  end
end

AddEventHandler('vhub_garage:setupReady', spawnDynamicPeds)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  for _, handle in ipairs(_staticHandles) do
    if DoesEntityExist(handle) then DeleteEntity(handle) end
  end
  for _, handle in ipairs(_dynHandles) do
    if DoesEntityExist(handle) then DeleteEntity(handle) end
  end
end)
