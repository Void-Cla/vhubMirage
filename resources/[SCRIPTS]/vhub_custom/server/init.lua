-- server/init.lua — bootstrap do vhub_custom (replay-guard + lifecycle)
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local E    = VHubCustom.E

-- replay-guard: evita duplo disparo em onResourceStart do core
local _seen = {}

-- catálogo pré-processado com nome do modelo em lowercase como chave
-- (hash server-side pode ser signed; lowercase string é portável client↔server)
local _catalog_indexed = nil

-- indexa o catálogo do conce com DUAS chaves por entrada:
--   1. lowercase do spawn name (ex: 'skyliner34')
--   2. lowercase do display name via native (ex: 'skylinegtr')
-- Isso garante que o client acha o entry mesmo quando display name ≠ spawn name.
local function buildCatalogIndex()
  if _catalog_indexed then return _catalog_indexed end
  local ok, raw = pcall(function() return exports.vhub_conce:getCatalog() end)
  if not ok or type(raw) ~= 'table' then return {} end
  local indexed = {}
  for k, v in pairs(raw) do
    local entry = { nome = v.nome, stats = v.stats, categoria = v.categoria }
    -- chave 1: spawn name em lowercase
    indexed[string.lower(k)] = entry
    -- chave 2: display name em lowercase (para mods onde display ≠ spawn)
    local h = GetHashKey(k)
    if h and h ~= 0 then
      local dOk, disp = pcall(GetDisplayNameFromVehicleModel, h)
      if dOk and type(disp) == 'string' and disp ~= '' and disp ~= 'NULL' then
        indexed[string.lower(disp)] = entry
      end
    end
  end
  -- não cacheia catálogo vazio (race condition se conce ainda está carregando)
  if next(indexed) then _catalog_indexed = indexed end
  return indexed
end

AddEventHandler('vHub:playerSpawn', function(user)
  if not user then return end
  local spawns = tonumber(user.spawns) or 0
  if _seen[user.source] == spawns then return end
  _seen[user.source] = spawns
end)

-- envia catálogo (spawn name + display name, ambos lowercase) ao cliente que solicitou
RegisterNetEvent(E.REQ_CATALOG)
AddEventHandler(E.REQ_CATALOG, function()
  local src = source
  TriggerClientEvent(E.CATALOG, src, buildCatalogIndex())
end)

-- lookup autoritativo: placa → model via prontuário → entrada do catálogo
-- resolve a ambiguidade de display name para mods onde o cliente não acha a chave
RegisterNetEvent(E.REQ_VEH_DATA)
AddEventHandler(E.REQ_VEH_DATA, function(plate)
  local src = source
  local p   = plate and tostring(plate):upper():match('^%s*(.-)%s*$') or ''
  if p == '' then return end

  local veh_row = nil
  pcall(function() veh_row = exports.vhub_conce:getVehicle(p) end)
  if not veh_row then
    TriggerClientEvent(E.VEH_DATA, src, p, nil); return
  end

  local model_key = veh_row.model and string.lower(veh_row.model) or ''
  local idx       = buildCatalogIndex()
  local cat       = idx[model_key] or {}

  TriggerClientEvent(E.VEH_DATA, src, p, {
    nome      = cat.nome,
    stats     = cat.stats,
    categoria = cat.categoria,
  })
end)

AddEventHandler('playerDropped', function()
  local src = source
  _seen[src] = nil
end)

-- log de boot
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  VHubCustom.log('iniciado — bennys/mec/oficina prontos')
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  VHubCustom.log('encerrado')
end)
