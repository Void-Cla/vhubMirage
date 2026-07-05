-- client/utils.lua — raycast da câmera + filtros de grupo/item das opções
-- Cfx Lua (LuaGLM): usa string.strsplit — não é Lua 5.4 puro.
---@diagnostic disable: undefined-global, lowercase-global, undefined-field

VHubTarget = VHubTarget or {}

local utils = {}
VHubTarget.utils = utils

local GetWorldCoordFromScreenCoord = GetWorldCoordFromScreenCoord
local StartShapeTestLosProbe = StartShapeTestLosProbe
local GetShapeTestResultIncludingMaterial = GetShapeTestResultIncludingMaterial


-- ============================================================
-- RAYCAST
-- ============================================================

-- raycast do centro da tela até maxDist metros; retorna hit, entityHit, endCoords
function utils.raycastFromCamera(flag, maxDist)
  local coords, normal = GetWorldCoordFromScreenCoord(0.5, 0.5)
  local destination = coords + normal * (maxDist or 20)
  local handle = StartShapeTestLosProbe(
    coords.x, coords.y, coords.z,
    destination.x, destination.y, destination.z,
    flag, VHubTarget.cache.ped, 4)

  while true do
    Citizen.Wait(0)
    local retval, hit, endCoords, _, _, entityHit = GetShapeTestResultIncludingMaterial(handle)

    if retval ~= 1 then
      return hit, entityHit, endCoords
    end
  end
end

-- carrega a textura do sprite de zona (dict compartilhado do jogo)
function utils.getTexture()
  local dict = 'shared'
  if not HasStreamedTextureDictLoaded(dict) then
    RequestStreamedTextureDict(dict, false)
    local deadline = GetGameTimer() + 5000
    while not HasStreamedTextureDictLoaded(dict) and GetGameTimer() < deadline do
      Citizen.Wait(10)
    end
  end
  return dict, 'emptydot_32'
end


-- ============================================================
-- FILTRO DE GRUPO — via vhub_groups (cache local do próprio resource dele)
-- ============================================================

-- retorna true se o player pertence a algum dos grupos do filtro (UX; verdade = server)
function utils.hasPlayerGotGroup(filter)
  local ok, groups = pcall(function() return exports.vhub_groups:getGroupsLocal() end)
  if not ok or type(groups) ~= 'table' then return true end   -- soft-dep: sem groups, não filtra

  if type(filter) == 'string' then filter = { filter } end

  for i = 1, #filter do
    local g = filter[i]
    for j = 1, #groups do
      local pg = groups[j]
      if pg == g or (type(pg) == 'table' and pg.name == g) then return true end
    end
  end

  return false
end


-- ============================================================
-- FILTRO DE ITEM — stub permissivo DOCUMENTADO (zero-trust)
-- ============================================================
-- vhub_inventory não expõe contagem client-side (API é server-only por design).
-- O filtro `items` aqui é APENAS UX: retorna true e deixa a opção visível.
-- A validação REAL do item é OBRIGAÇÃO do consumidor no handler server-side
-- (exports.vhub_inventory:hasItem/getItemAmount) — cliente nunca decide (L-01).

-- retorna true (stub permissivo; validação de item é server-side no consumidor)
function utils.hasPlayerGotItems(filter, hasAny)
  return true
end


-- ============================================================
-- HELPERS
-- ============================================================

-- verifica se um export 'resource.func' existe (sem invocar)
function utils.hasExport(export)
  local resource, exportName = string.strsplit('.', export)
  return pcall(function()
    return exports[resource][exportName]
  end)
end
