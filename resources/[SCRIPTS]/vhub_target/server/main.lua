-- server/main.lua — validação server-side do vhub_target (zero-trust, manual §4.6/§6.6)
-- Eventos de cliente validados por: shape → rate → entidade → tipo → alcance.
-- Budget (L-18): GC de entityStates a cada 10 s, O(n) sobre netids registrados;
-- GC libera registro server-side; bag de entidade morre com a entidade (client faz GC local).
---@diagnostic disable: undefined-global, lowercase-global

local E = VHubTarget.E
local RATES = VHubTarget.cfg.rates

-- porta de veículo é interação corpo-a-corpo; medimos ao CENTRO da entidade,
-- então o raio inclui a folga centro→porta de veículos longos (sedã/van ~2 m)
local DOOR_RANGE = 5.0

-- cap defensivo do registro de netids com opções (anti-spam de flag)
local MAX_ENTITY_STATES = 2048


-- ============================================================
-- RATE-LIMIT O(1) por (src, chave) — manual §4.6
-- ============================================================

local _last = {}
local _alive = true   -- desligado no onResourceStop; encerra a thread de GC (L-18/R8)

-- retorna true se a ação respeita o intervalo mínimo declarado em cfg.rates
local function rateOK(src, key, ms)
  local now = GetGameTimer()
  local k = src .. ':' .. key
  if (now - (_last[k] or 0)) < ms then return false end
  _last[k] = now
  return true
end

AddEventHandler('playerDropped', function()
  local p = source .. ':'
  for k in pairs(_last) do
    if k:sub(1, #p) == p then _last[k] = nil end
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then
    _last = {}
    _alive = false
  end
end)


-- ============================================================
-- REGISTRO DE ENTIDADES COM OPÇÕES (flag global via State Bag)
-- ============================================================

-- registro netId → handle numérico (não guardar o wrapper Entity(): __data é campo
-- privado não-contratual; o handle cru é estável entre versões do runtime)
local entityStates = {}
local entityCount = 0

RegisterNetEvent(E.SET_ENTITY_HAS_OPTIONS, function(netId)
  local src = source

  -- shape → rate → entidade (ordem do manual §6.6)
  if type(netId) ~= 'number' then return end
  if not rateOK(src, 'seteo', RATES.set_entity_options) then return end
  if entityStates[netId] then return end                        -- idempotente (R14)
  if entityCount >= MAX_ENTITY_STATES then return end           -- cap anti-spam

  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return end

  -- replicated=true (3º arg): sem ele o bag só existe server-side e o client nunca lê
  Entity(entity).state:set('hasTargetOptions', true, true)
  entityStates[netId] = entity
  entityCount = entityCount + 1
end)


-- ============================================================
-- PORTA DE VEÍCULO — client pede, servidor valida e delega ao owner
-- ============================================================

RegisterNetEvent(E.TOGGLE_ENTITY_DOOR, function(netId, door)
  local src = source

  -- shape
  if type(netId) ~= 'number' or type(door) ~= 'number' then return end
  door = math.floor(door)
  if door < 0 or door > 5 then return end

  -- rate
  if not rateOK(src, 'door', RATES.toggle_door) then return end

  -- entidade viva e do tipo certo
  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return end
  if GetEntityType(entity) ~= 2 then return end                 -- 2 = veículo

  -- alcance: pedido de porta só vale corpo-a-corpo (anti-grief a distância)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return end
  if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > DOOR_RANGE then return end

  local owner = NetworkGetEntityOwner(entity)
  if owner and owner > 0 then
    TriggerClientEvent(E.TOGGLE_ENTITY_DOOR, owner, netId, door)
  end
end)


-- ============================================================
-- GC — remove netids de entidades mortas (escritor único do bag)
-- ============================================================
-- Quando a entidade morre, seu State Bag (hasTargetOptions) é destruído junto com ela
-- e o client faz seu GC local via AddStateBagChangeHandler (R5: sem broadcast -1 de
-- estado de entidade). Aqui só liberamos o registro server-side.
-- Budget (L-18): 1 varredura/10 s, O(n) sobre registros; encerra no onResourceStop.

Citizen.CreateThread(function()
  while _alive do
    Citizen.Wait(10000)

    for netId, handle in pairs(entityStates) do
      if not DoesEntityExist(handle) then
        entityStates[netId] = nil
        entityCount = entityCount - 1
      end
    end
  end
end)
