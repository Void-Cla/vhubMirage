-- server/exports.lua — exports cross-resource seguros (default-deny, ADR #39/#42)

local _warned_empty_trust = false
local function _invoker_allowed()
  local trust = vHub.cfg and vHub.cfg.trusted_resources
  if not trust or next(trust) == nil then
    if not _warned_empty_trust and vHub.Logger then
      _warned_empty_trust = true
      vHub.Logger:warn("exports",
        "trusted_resources VAZIO — exports sensíveis NEGADOS (default-deny). Popule vHub.cfg.trusted_resources.")
    end
    return false                      -- N0-2: era return true (default-permissivo)
  end
  local caller = GetInvokingResource()
  if not caller then return false end -- N0-2: era return true
  return trust[caller] == true
end


-- ============================================================
-- QUERIES (read-only)
-- ============================================================

vHub.Kernel:export("getVHub",      function()           return vHub            end)
vHub.Kernel:export("getUser",      function(src)        return vHub.Auth:getUser(src) end)
vHub.Kernel:export("getUID",       function(src)        return vHub.Auth:getUID(src)  end)
vHub.Kernel:export("hasPerm",      function(u,p)        return vHub.Kernel:hasPerm(u,p)   end)
-- Snapshot do VD como CÓPIA (L-14; ADR #50) — com a cadeia física reanimada (#37),
-- devolver a referência viva reativaria o vetor de mutação externa apontado no
-- GATILHO da decisão #32. Consumidores (vehcontrol/lspdtool) só leem campos.
vHub.Kernel:export("getVehicle",   function(plate)
  local p = plate and plate:upper() or nil
  local vd = p and vHub.Vehicle._veh[p]
  return vd and vHub.Utils.dataCopy(vd) or nil
end)
vHub.Kernel:export("getVehicleByKey", function(key)     return vHub.Vehicle:byKey(key)   end)

-- Motorista atual da placa (src) ou nil — gate de autoridade de input (FASE 3.1)
vHub.Kernel:export("getVehicleDriver", function(plate)
  local p = plate and plate:upper() or nil
  local vd = p and vHub.Vehicle._veh[p]
  return vd and vd.driver or nil
end)

-- Ocupantes atuais da placa como CÓPIA { [src]=seat } — base do single-pilot-channel (FASE 3.2)
vHub.Kernel:export("getVehicleOccupants", function(plate)
  local p = plate and plate:upper() or nil
  local vd = p and vHub.Vehicle._veh[p]
  if not vd then return {} end
  local copia = {}
  for src, seat in pairs(vd.occupants) do copia[src] = seat end
  return copia
end)

-- Retorna CÓPIA do estado físico do veículo — nunca a referência viva (L-14).
-- Exige Citizen.CreateThread no chamador (pode ir ao DB no primeiro acesso).
vHub.Kernel:export("getVehicleState", function(plate)
  vHub.assertThread()
  local vd = vHub.Vehicle:register(plate, nil)
  if not vd then return nil end
  return vHub.Utils.dataCopy(vd.state)
end)


-- ============================================================
-- MUTATIONS (gated default-deny + audit — R12)
-- ============================================================

vHub.Kernel:export("grantPerm",    function(u,p)
  if not _invoker_allowed() then return false end
  vHub.Kernel:grantPerm(u,p)
  vHub.audit(GetInvokingResource() or "?", "grantPerm", tostring(u), nil, nil, { perm = p })
end)
vHub.Kernel:export("transferKey",  function(pl,key)
  if not _invoker_allowed() then return false end
  local ok = vHub.Vehicle:transferKey(pl,key)
  if ok then
    vHub.audit(GetInvokingResource() or "?", "transferKey", tostring(pl), nil, nil, { key_uid = key })
  end
  return ok
end)
vHub.Kernel:export("banPlayer",    function(u,r,by)
  if not _invoker_allowed() then return false end
  vHub.Auth:ban(u,r,by)
  vHub.audit(GetInvokingResource() or "?", "banPlayer", tostring(u), nil, nil, { reason = r, by = by })
end)
vHub.Kernel:export("unbanPlayer",  function(u)
  if not _invoker_allowed() then return false end
  vHub.Auth:unban(u)
  vHub.audit(GetInvokingResource() or "?", "unbanPlayer", tostring(u), nil, nil, nil)
end)


-- ============================================================
-- CONTRATO DE COMMIT DE VEÍCULO (ADR #39 — F-028)
-- ============================================================

-- Campos que cada origem de negócio pode mutar. `true` = todos (admin/migração).
local SOURCE_GATES = {
  pump   = { fuel = true },
  repair = { engine_health = true, body_health = true, damage = true },
  tune   = { tuning = true },
  garage = { fuel = true, engine_health = true, body_health = true, damage = true,
             garage = true, last_pos = true, engine_on = true },
  system = true,
}

-- Muta estado físico sob contrato: VRAM + State Bags + SQL (batch) + evento + audit.
-- Exige Citizen.CreateThread no chamador. Retorna true/false.
vHub.Kernel:export("commitVehicleState", function(plate, patch, source_tag)
  if not _invoker_allowed() then return false end
  vHub.assertThread()
  if type(patch) ~= "table" or next(patch) == nil then return false end

  local allowed = SOURCE_GATES[source_tag]
  if not allowed then
    vHub.Logger:warn("exports",
      ("commitVehicleState: source '%s' não autorizado"):format(tostring(source_tag)))
    return false
  end
  for campo in pairs(patch) do
    if allowed ~= true and not allowed[campo] then
      vHub.Logger:warn("exports",
        ("commitVehicleState: source '%s' não pode mutar '%s'"):format(
          tostring(source_tag), tostring(campo)))
      return false
    end
  end

  local vd = vHub.Vehicle:register(plate, nil)
  if not vd then return false end

  local antes = {}
  for campo, valor in pairs(patch) do
    antes[campo] = vd.state[campo]
    vd.state[campo] = valor
  end
  vd.dirty = true
  vd:_syncBags()
  vHub.Vehicle:_save(vd)  -- persiste via setVData → batch SQL (nunca síncrono no tick)

  TriggerEvent(vHub.E.EVT_VEH_COMMITTED, vd.plate, source_tag, patch)
  vHub.audit(GetInvokingResource() or "?", "commitVehicleState", vd.plate, source_tag, antes, patch)
  return true
end)


-- ============================================================
-- REGISTRO DE SPAWN/DESPAWN (ADR #37 — verdade server-side dos donos)
-- ============================================================

-- Registra spawn físico de veículo no CORE (chamado pelo dono do spawn: garage/conce).
-- Substitui a superfície de rede vSpawned, que segue desarmada.
vHub.Kernel:export("registerVehicleSpawn", function(plate, netid)
  if not _invoker_allowed() then return false end
  vHub.assertThread()
  if type(netid) ~= "number" then return false end
  vHub.Vehicle:onSpawned(plate, netid)
  return true
end)

-- Registra despawn físico (salva estado + posição e libera índices do CORE).
vHub.Kernel:export("registerVehicleDespawn", function(plate)
  if not _invoker_allowed() then return false end
  vHub.Vehicle:onDespawned(plate)
  return true
end)
