-- client/api.lua — exports públicos do vhub_target (superfície compatível com ox_target 1.18.x)
-- Export-first: toda função registrada aqui vira export automaticamente (metatable).
-- Registro de opções é EFÊMERO client-side por resource; onClientResourceStop limpa.
-- Cfx Lua (LuaGLM): usa table.type/table.wipe/joaat/?. — não é Lua 5.4 puro.
---@diagnostic disable: undefined-global, lowercase-global, undefined-field

VHubTarget = VHubTarget or {}

local zonesApi = VHubTarget.zones
local Zones = VHubTarget.Zones
local E = VHubTarget.E

local function payloadVec3(value, positive)
  if value == nil then return nil end
  local kind = type(value)
  if kind ~= 'table' and kind ~= 'vector3' and kind ~= 'vector4' then return nil end
  local x = tonumber(value.x)
  local y = tonumber(value.y)
  local z = tonumber(value.z)
  if not x or not y or not z or x ~= x or y ~= y or z ~= z
    or math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then
    return nil
  end
  if positive and (x <= 0 or y <= 0 or z <= 0) then return nil end
  return vec3(x, y, z)
end

local api = setmetatable({}, {
  __newindex = function(self, index, value)
    rawset(self, index, value)
    exports(index, value)
  end
})

VHubTarget.api = api


-- ============================================================
-- VALIDAÇÃO DE OPÇÕES
-- ============================================================

-- lança erro de tipo formatado
local function typeError(variable, expected, received)
  error(("expected %s to have type '%s' (received %s)"):format(variable, expected, received))
end

-- normaliza options para array e valida o shape
local function checkOptions(options)
  local optionsType = type(options)

  if optionsType ~= 'table' then
    typeError('options', 'table', optionsType)
  end

  local tableType = table.type(options)

  if tableType == 'hash' and options.label then
    options = { options }
  elseif tableType ~= 'array' then
    typeError('options', 'array', ('%s table'):format(tableType))
  end

  return options
end


-- ============================================================
-- ZONAS (box / sphere / poly) — engine própria (client/zones.lua)
-- ============================================================

-- cria zona poligonal de interação; retorna o id
function api.addPolyZone(data)
  data.resource = GetInvokingResource() or 'vhub_target'
  data.options = checkOptions(data.options)
  return zonesApi.addPoly(data).id
end

-- cria zona caixa de interação; retorna o id
function api.addBoxZone(data)
  if type(data) ~= 'table' then typeError('data', 'table', type(data)) end
  data.coords = payloadVec3(data.coords)
  data.size = payloadVec3(data.size or { x = 2.0, y = 2.0, z = 2.0 }, true)
  if not data.coords or not data.size then typeError('coords/size', 'vec3 payload', 'invalid') end
  data.resource = GetInvokingResource() or 'vhub_target'
  data.options = checkOptions(data.options)
  return zonesApi.addBox(data).id
end

-- cria zona esférica de interação; retorna o id
function api.addSphereZone(data)
  data.resource = GetInvokingResource() or 'vhub_target'
  data.options = checkOptions(data.options)
  return zonesApi.addSphere(data).id
end

-- retorna true se a zona (id numérico ou nome) existe
function api.zoneExists(id)
  local idType = type(id)
  if idType ~= 'number' and idType ~= 'string' then return false end

  if idType == 'number' then return Zones[id] ~= nil end

  for _, zone in pairs(Zones) do
    if zone.name == id then return true end
  end

  return false
end

-- remove zona por id numérico ou por nome (2º arg preservado por compat de assinatura)
function api.removeZone(id, _suppressWarning)
  if type(id) == 'string' then
    local found = false

    for _, zone in pairs(Zones) do
      if zone.name == id then
        found = true
        zone:remove()
      end
    end

    if found then return end
  elseif Zones[id] then
    return Zones[id]:remove()
  end
end


-- ============================================================
-- REGISTRO DE OPÇÕES (globais, por modelo, por netid, por entidade local)
-- ============================================================

-- remove opções por nome dentro de um alvo (respeitando o resource dono)
local function removeTarget(target, remove, resource)
  if type(remove) ~= 'table' then remove = { remove } end

  for i = #target, 1, -1 do
    local option = target[i]

    if option.resource == resource then
      for j = #remove, 1, -1 do
        if option.name == remove[j] then
          table.remove(target, i)
        end
      end
    end
  end
end

-- adiciona opções a um alvo, substituindo homônimas do mesmo resource
local function addTarget(target, options, resource)
  options = checkOptions(options)

  local checkNames = {}

  resource = resource or 'vhub_target'

  for i = 1, #options do
    local option = options[i]
    option.resource = resource

    if option.name then
      checkNames[#checkNames + 1] = option.name
    end
  end

  if checkNames[1] then
    removeTarget(target, checkNames, resource)
  end

  local num = #target

  -- funções (canInteract/onSelect) ficam por referência direta — são do resource chamador,
  -- seguras no mesmo runtime. msgpack NÃO serializa closures (produziria função quebrada).
  for i = 1, #options do
    num = num + 1
    target[num] = options[i]
  end
end

local peds = {}
local vehicles = {}
local objects = {}
local players = {}

-- adiciona opções para todo ped não-player
function api.addGlobalPed(options) addTarget(peds, options, GetInvokingResource()) end

-- remove opções globais de ped por nome
function api.removeGlobalPed(options) removeTarget(peds, options, GetInvokingResource()) end

-- adiciona opções para todo veículo
function api.addGlobalVehicle(options) addTarget(vehicles, options, GetInvokingResource()) end

-- remove opções globais de veículo por nome
function api.removeGlobalVehicle(options) removeTarget(vehicles, options, GetInvokingResource()) end

-- adiciona opções para todo objeto
function api.addGlobalObject(options) addTarget(objects, options, GetInvokingResource()) end

-- remove opções globais de objeto por nome
function api.removeGlobalObject(options) removeTarget(objects, options, GetInvokingResource()) end

-- adiciona opções para todo player
function api.addGlobalPlayer(options) addTarget(players, options, GetInvokingResource()) end

-- remove opções globais de player por nome
function api.removeGlobalPlayer(options) removeTarget(players, options, GetInvokingResource()) end

local models = {}

-- adiciona opções por modelo (hash ou nome)
function api.addModel(arr, options)
  if type(arr) ~= 'table' then arr = { arr } end
  local resource = GetInvokingResource()

  for i = 1, #arr do
    local model = arr[i]
    model = tonumber(model) or joaat(model)

    if not models[model] then
      models[model] = {}
    end

    addTarget(models[model], options, resource)
  end
end

-- remove opções por modelo (todas do modelo se options for nil)
function api.removeModel(arr, options)
  if type(arr) ~= 'table' then arr = { arr } end
  local resource = GetInvokingResource()

  for i = 1, #arr do
    local model = arr[i]
    model = tonumber(model) or joaat(model)

    if models[model] then
      if options then
        removeTarget(models[model], options, resource)
      end

      if not options or #models[model] == 0 then
        models[model] = nil
      end
    end
  end
end

local entities = {}

-- adiciona opções a entidades de rede (netid); avisa o servidor p/ flag global
function api.addEntity(arr, options)
  if type(arr) ~= 'table' then arr = { arr } end
  local resource = GetInvokingResource()

  for i = 1, #arr do
    local netId = arr[i]

    if NetworkDoesNetworkIdExist(netId) then
      if not entities[netId] then
        entities[netId] = {}

        if not Entity(NetworkGetEntityFromNetworkId(netId)).state.hasTargetOptions then
          TriggerServerEvent(E.SET_ENTITY_HAS_OPTIONS, netId)
        end
      end

      addTarget(entities[netId], options, resource)
    end
  end
end

-- remove opções de entidades de rede (todas do netid se options for nil)
function api.removeEntity(arr, options)
  if type(arr) ~= 'table' then arr = { arr } end
  local resource = GetInvokingResource()

  for i = 1, #arr do
    local netId = arr[i]

    if entities[netId] then
      if options then
        removeTarget(entities[netId], options, resource)
      end

      if not options or #entities[netId] == 0 then
        entities[netId] = nil
      end
    end
  end
end

-- GC local: quando o bag hasTargetOptions da entidade cai (entidade morreu/despawnou),
-- descarta TODAS as opções daquele netId — sem broadcast -1 do server (R5).
AddStateBagChangeHandler('hasTargetOptions', nil, function(bagName, _, value)
  if value then return end

  local netId = tonumber(bagName:match('^entity:(%d+)$'))
  if netId and entities[netId] then
    entities[netId] = nil
  end
end)

local localEntities = {}

-- adiciona opções a entidades locais (handle não-networked)
function api.addLocalEntity(arr, options)
  if type(arr) ~= 'table' then arr = { arr } end
  local resource = GetInvokingResource()

  for i = 1, #arr do
    local entityId = arr[i]

    if DoesEntityExist(entityId) then
      if not localEntities[entityId] then
        localEntities[entityId] = {}
      end

      addTarget(localEntities[entityId], options, resource)
    end
  end
end

-- remove opções de entidades locais
function api.removeLocalEntity(arr, options)
  if type(arr) ~= 'table' then arr = { arr } end
  local resource = GetInvokingResource()

  for i = 1, #arr do
    local entity = arr[i]

    if localEntities[entity] then
      if options then
        removeTarget(localEntities[entity], options, resource)
      end

      if not options or #localEntities[entity] == 0 then
        localEntities[entity] = nil
      end
    end
  end
end

-- GC de entidades locais mortas — budget (L-18): 1 varredura/min, O(n) sobre registros
-- guard de saída p/ não vazar thread após restart do resource (R8)
local _gcAlive = true

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then _gcAlive = false end
end)

Citizen.CreateThread(function()
  while _gcAlive do
    Citizen.Wait(60000)

    for entityId in pairs(localEntities) do
      if not DoesEntityExist(entityId) then
        localEntities[entityId] = nil
      end
    end
  end
end)


-- ============================================================
-- LIMPEZA POR RESOURCE (invalidação do registro efêmero)
-- ============================================================

-- remove opções globais registradas por um resource que parou
local function removeResourceGlobals(resource, target)
  for i = 1, #target do
    local options = target[i]

    for j = #options, 1, -1 do
      if options[j].resource == resource then
        table.remove(options, j)
      end
    end
  end
end

-- remove opções por modelo/netid/entidade registradas por um resource que parou
local function removeResourceTargets(resource, target)
  for i = 1, #target do
    local tbl = target[i]

    for key, options in pairs(tbl) do
      for j = #options, 1, -1 do
        if options[j].resource == resource then
          table.remove(options, j)
        end
      end

      if #options == 0 then
        tbl[key] = nil
      end
    end
  end
end

AddEventHandler('onClientResourceStop', function(resource)
  removeResourceGlobals(resource, { peds, vehicles, objects, players })
  removeResourceTargets(resource, { models, entities, localEntities })

  for _, zone in pairs(Zones) do
    if zone.resource == resource then
      zone:remove()
    end
  end
end)


-- ============================================================
-- RESOLUÇÃO DE OPÇÕES DO ALVO ATUAL (consumida pelo main.lua)
-- ============================================================

local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity

local options_mt = {}
options_mt.__index = options_mt
options_mt.size = 1

-- limpa o conjunto de opções do alvo atual
function options_mt:wipe()
  options_mt.size = 1
  self.globalTarget = nil
  self.model = nil
  self.entity = nil
  self.localEntity = nil

  local first = self.__global[1]
  if first and first.name == 'builtin:goback' then
    table.remove(self.__global, 1)
  end
end

-- resolve os conjuntos de opções aplicáveis à entidade mirada
function options_mt:set(entity, _type, model)
  if not entity then return end

  if _type == 1 and IsPedAPlayer(entity) then
    self:wipe()
    self.globalTarget = players
    options_mt.size = options_mt.size + 1

    return
  end

  local netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity)

  self.globalTarget = _type == 1 and peds or _type == 2 and vehicles or objects
  self.model = models[model]
  self.entity = netId and entities[netId] or nil
  self.localEntity = localEntities[entity]
  options_mt.size = options_mt.size + 1

  if self.model then options_mt.size = options_mt.size + 1 end
  if self.entity then options_mt.size = options_mt.size + 1 end
  if self.localEntity then options_mt.size = options_mt.size + 1 end
end

local global = {}

-- adiciona opções globais (aparecem em qualquer alvo)
function api.addGlobalOption(options) addTarget(global, options, GetInvokingResource()) end

-- remove opções globais por nome
function api.removeGlobalOption(options) removeTarget(global, options, GetInvokingResource()) end

local options = setmetatable({
  __global = global
}, options_mt)

-- retorna o conjunto de opções (interno p/ main.lua; com entity, snapshot por alvo)
function api.getTargetOptions(entity, _type, model)
  if not entity then return options end

  if IsPedAPlayer(entity) then
    return { global = players }
  end

  local netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity)

  return {
    global = _type == 1 and peds or _type == 2 and vehicles or objects,
    model = models[model],
    entity = netId and entities[netId] or nil,
    localEntity = localEntities[entity],
  }
end


-- ============================================================
-- CONTROLE EXTERNO (consumidores)
-- ============================================================

local state = VHubTarget.state

-- desabilita/reabilita o targeting por completo
function api.disableTargeting(value)
  if value then
    state.setActive(false)
  end

  state.setDisabled(value)
end

-- trava o targeting durante ação em progresso do consumidor (substituto do progressActive)
function api.setLocked(value)
  state.setLocked(value)
end

-- retorna se o targeting está ativo
function api.isActive()
  return state.isActive()
end
