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

local function _invoker_is(resource)
  return GetInvokingResource() == resource
end

local CHARACTER_ID_CALLERS = {
  vhub_login = true,
  vhub_hss = true,
  vhub_identity = true,
  vhub_sims = true,
  vhub_spawselector = true,
  vhub_voicePMA = true,
  vhub_vehcontrol = true,
}

local SIMS_READ_CALLERS = {
  vhub_hss = true,
  vhub_login = true,
  vhub_sims = true,
}

local LOG_CALLERS = {
  vhub_hss = true,
  vhub_identity = true,
  vhub_login = true,
  vhub_sims = true,
}


-- ============================================================
-- QUERIES (read-only)
-- ============================================================

vHub.Kernel:export("getVHub",      function()           return vHub            end)
vHub.Kernel:export("getUser",      function(src)        return vHub.Auth:getUser(src) end)
vHub.Kernel:export("getUID",       function(src)        return vHub.Auth:getUID(src)  end)
vHub.Kernel:export("hasPerm",      function(u,p)        return vHub.Kernel:hasPerm(u,p)   end)

-- Retorna somente o char_id canônico da sessão online, sem expor referência viva.
vHub.Kernel:export("getCharacterId", function(src)
  if CHARACTER_ID_CALLERS[GetInvokingResource() or ""] ~= true then return nil end
  src = tonumber(src)
  if not src or src < 1 then return nil end
  local user = vHub.Auth:getUser(src)
  return user and tonumber(user.char_id) or nil
end)

-- Retorna bootstrap imutável de migração exclusivamente ao owner físico HSS.
vHub.Kernel:export("getCharacterBootstrap", function(src)
  if not _invoker_is("vhub_hss") then return nil end
  src = tonumber(src)
  local user = src and vHub.Auth:getUser(src) or nil
  if not user or not tonumber(user.char_id) then return nil end
  local data = type(user.data) == "table" and user.data or {}
  return {
    char_id = tonumber(user.char_id),
    spawns = math.max(0, tonumber(user.spawns) or 0),
    vitals = vHub.Utils.dataCopy(type(data.vitals) == "table" and data.vitals or {}),
    state = vHub.Utils.dataCopy(type(data.state) == "table" and data.state or {}),
  }
end)

-- Registra morte física observada exclusivamente pelo owner HSS.
vHub.Kernel:export("reportPhysicalDeath", function(src)
  if not _invoker_is("vhub_hss") then return false end
  return vHub.Boot.reportPhysicalDeath(src)
end)

-- Conclui respawn físico observado exclusivamente pelo owner HSS.
vHub.Kernel:export("reportPhysicalRespawn", function(src)
  if not _invoker_is("vhub_hss") then return false end
  return vHub.Boot.reportPhysicalRespawn(src)
end)

-- Lista cópias dos personagens da sessão exclusivamente ao gate de login.
vHub.Kernel:export("listCharacters", function(src)
  if not _invoker_is("vhub_login") then return nil end
  src = tonumber(src)
  local user = src and vHub.Auth:getUser(src) or nil
  return user and vHub.Utils.dataCopy(vHub.Auth:getCharacters(user.id)) or nil
end)

-- Retorna IDs de personagem exclusivamente aos owners consumidores autorizados.
vHub.Kernel:export("getCharacterIds", function(src)
  if CHARACTER_ID_CALLERS[GetInvokingResource() or ""] ~= true then
    return { ok = false, err = "forbidden" }
  end
  return vHub.Auth:getCharacterIds(src)
end)

-- Cria personagem exclusivamente por intenção do gate de login.
vHub.Kernel:export("createCharacter", function(src, request_id)
  if not _invoker_is("vhub_login") then return { ok = false, err = "forbidden" } end
  return vHub.Auth:createCharacterRequest(src, request_id)
end)

-- Apaga personagem meio-criado/abandonado exclusivamente por intenção do gate de login (ADR #76).
vHub.Kernel:export("deleteCharacter", function(src, char_id)
  if not _invoker_is("vhub_login") then return { ok = false, err = "forbidden" } end
  return vHub.Auth:deleteCharacterRequest(src, char_id)
end)

-- Consulta conclusão do criador para login e SIMS.
vHub.Kernel:export("getSimsCreation", function(src)
  if SIMS_READ_CALLERS[GetInvokingResource() or ""] ~= true then
    return { ok = false, err = "forbidden" }
  end
  return vHub.Auth:getSimsCreation(src)
end)

-- Persiste conclusão do criador exclusivamente pelo owner SIMS.
vHub.Kernel:export("commitSimsCreation", function(src, request_id, apv)
  if not _invoker_is("vhub_sims") then return { ok = false, err = "forbidden" } end
  return vHub.Auth:commitSimsCreation(src, request_id, apv)
end)

-- Seleciona personagem pelo contrato autoritativo exclusivo do gate de login.
vHub.Kernel:export("selectCharacter", function(src, char_id)
  if not _invoker_is("vhub_login") then return false end
  src, char_id = tonumber(src), tonumber(char_id)
  local user = src and vHub.Auth:getUser(src) or nil
  if not user or not char_id then return false end
  local before = tonumber(user.char_id)
  local selected = vHub.Auth:selectCharacter(user, char_id)
  if selected then
    vHub.audit("vhub_login", "selectCharacter", tostring(src), "login", before, char_id)
  end
  return selected == true
end)

-- Encaminha log estruturado de resources confiáveis sem expor o objeto vHub.
vHub.Kernel:export("log", function(level, module, message, meta)
  local caller = GetInvokingResource() or ""
  if not _invoker_allowed() and LOG_CALLERS[caller] ~= true then return false end
  local method = type(level) == "string" and level:lower() or ""
  if method ~= "debug" and method ~= "info" and method ~= "warn" and method ~= "error" then
    return false
  end
  if type(module) ~= "string" or module == "" or #module > 32 then return false end
  if type(message) ~= "string" or message == "" or #message > 512 then return false end
  vHub.Logger[method](vHub.Logger, module, message, type(meta) == "table" and meta or nil)
  return true
end)
-- Snapshot do VD como CÓPIA (L-14; ADR #50) — com a cadeia física reanimada (#37),
-- devolver a referência viva reativaria o vetor de mutação externa apontado no
-- GATILHO da decisão #32. Consumidores (vehcontrol/lspdtool) só leem campos.
vHub.Kernel:export("getVehicle",   function(plate)
  local p = plate and plate:upper() or nil
  local vd = p and vHub.Vehicle._veh[p]
  return vd and vHub.Utils.dataCopy(vd) or nil
end)
vHub.Kernel:export("getVehicleByKey", function(key)     return vHub.Vehicle:byKey(key)   end)

vHub.Kernel:export("getCData", function(cid, key)
  if not _invoker_allowed() then return nil end
  return vHub.getCData(cid, key)
end)

vHub.Kernel:export("setCData", function(cid, key, value, tx)
  if not _invoker_allowed() then return false end
  local ok = vHub.setCData(cid, key, value, tx)
  vHub.audit(GetInvokingResource() or "?", "setCData", tostring(cid), nil, nil, { key = key, value = value })
  return ok
end)

vHub.Kernel:export("getGData", function(key)
  if not _invoker_allowed() then return nil end
  return vHub.getGData(key)
end)

vHub.Kernel:export("setGData", function(key, value, tx)
  if not _invoker_allowed() then return false end
  local ok = vHub.setGData(key, value, tx)
  vHub.audit(GetInvokingResource() or "?", "setGData", "__g", nil, nil, { key = key, value = value })
  return ok
end)

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
  pump   = { fuel = true, _resource = "vhub_legacyfuel" },
  fuel_can = { fuel = true, _resource = "vhub_legacyfuel" },
  fuel_admin = { fuel = true, _resource = "vhub_legacyfuel" },
  fuel_migration = { fuel = true, _resource = "vhub_conce" },
  fuel_compat = { fuel = true, _resource = "vhub_conce" },
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
  local invoker = GetInvokingResource()
  if allowed ~= true and allowed._resource and allowed._resource ~= invoker then
    vHub.Logger:warn("exports",
      ("commitVehicleState: source '%s' negada para '%s'"):format(
        tostring(source_tag), tostring(invoker)))
    return false, { code = "forbidden_source" }
  end
  for campo in pairs(patch) do
    if campo == "_resource" or (allowed ~= true and not allowed[campo]) then
      vHub.Logger:warn("exports",
        ("commitVehicleState: source '%s' não pode mutar '%s'"):format(
          tostring(source_tag), tostring(campo)))
      return false
    end
  end

  if patch.fuel ~= nil then
    local fuel = patch.fuel
    if type(fuel) ~= "number" or fuel ~= fuel or math.abs(fuel) == math.huge then
      return false, { code = "invalid_fuel" }
    end
    patch.fuel = math.max(0.0, math.min(100.0, fuel))
  end

  local vd = vHub.Vehicle:register(plate, nil)
  if not vd then return false end
  if patch.fuel ~= nil and not vd.anchored then
    return false, { code = "unanchored", anchored = false }
  end

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
  return true, { code = "queued", anchored = vd.anchored == true, persistence = "queued" }
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
  return vHub.Vehicle:onSpawned(plate, netid) == true
end)

-- Registra despawn físico (salva estado + posição e libera índices do CORE).
vHub.Kernel:export("registerVehicleDespawn", function(plate)
  if not _invoker_allowed() then return false end
  vHub.Vehicle:onDespawned(plate)
  return true
end)
