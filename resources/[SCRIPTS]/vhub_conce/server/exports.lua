-- server/exports.lua — superfície interna do vhub_conce (autoridade chave/placa/dono)
-- Todos os exports exigem invoker confiável: conce é a autoridade, não API pública.
-- A superfície pública de leitura continua em vhub_garage (que proxia para cá).
-- Cada export roda no thread do chamador (SQL usa Citizen.Await) — não envolver em CreateThread.
---@diagnostic disable: undefined-global

local SQL  = VHubConce.SQL
local Core = VHubConce.Core
local U    = VHubConce.U

local TRUSTED = {
  ['vhub']            = true,
  ['vhub_garage']     = true,
  ['vhub_ferinha']    = true,
  ['vhub_admin']      = true,
  ['vhub_inventory']  = true,
  ['vhub_vehcontrol'] = true,   -- telemetria física + engine de skill → saveVehicleState (telemetry/handling)
  ['vhub_legacyfuel'] = true,   -- migração única ADR #61
  ['vhub_testrunner'] = true,   -- testes server-side (somente ambiente de teste)
  ['vhub_custom']     = true,   -- oficina + nitro (absorveu vhub_nitro ADR #81) → saveVehicleState
  ['vhub_vrcs']       = true,   -- Race Cinema: getVehicleState (read-only) p/ preservar aparência no replay
}
local CATALOG_SNAPSHOT_TRUSTED = { ['vhub_coinshop'] = true, ['vhub_admin'] = true }

local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return true end   -- chamada interna
  return TRUSTED[caller] == true
end


-- ============================================================
-- AUTORIDADE
-- ============================================================

-- pode operar (spawn/store/controle) a placa? (chave física + dono/autorização)
exports('canOperate', function(src, plate)
  if not _invoker_allowed() then return false end
  return Core:canOperate(src, plate)
end)

-- auditoria append-only; src=0 é reservado à reconciliação offline do caller exato.
exports('appendVehicleAudit', function(src, actor_char_id, plate, action, payload)
  if GetInvokingResource() ~= 'vhub_custom' then return false end
  src, actor_char_id = tonumber(src), tonumber(actor_char_id)
  local p = U.normalizePlate(plate)
  if not src or src < 0 or not actor_char_id or actor_char_id <= 0
      or actor_char_id % 1 ~= 0 or not p or type(action) ~= 'string' or #action > 64
      or not action:match('^custom%.[a-z_]+$') or type(payload) ~= 'table' then return false end
  local online_actor = src > 0 and Core:getCharId(src) or nil
  if online_actor and tonumber(online_actor) ~= actor_char_id then return false end
  local encoded = U.jenc(payload)
  if type(encoded) ~= 'string' or #encoded > 8192 then return false end
  return SQL:log(p, action, actor_char_id, encoded) == true
end)

-- é o dono real da placa?
exports('isOwner', function(src, plate)
  if not _invoker_allowed() then return false end
  return Core:isOwner(src, plate)
end)

-- transfere o dono real (atômico char_id + chave-row 'owner'); consumido por ferinha/garage
exports('transferOwner', function(plate, new_cid)
  if not _invoker_allowed() then return false end
  return Core:transferOwner(plate, new_cid)
end)


-- ============================================================
-- vhub_vehicles — leitura
-- ============================================================

exports('plateExists',  function(plate)        if not _invoker_allowed() then return false end return SQL:plateExists(plate)  end)
exports('getVehicle',   function(plate)        if not _invoker_allowed() then return nil   end return SQL:getVehicle(plate)   end)
exports('listByOwner',  function(char_id)      if not _invoker_allowed() then return {}    end return SQL:listByOwner(char_id)  end)
exports('listByStatus', function(status)       if not _invoker_allowed() then return {}    end return SQL:listByStatus(status) end)


-- ============================================================
-- vhub_vehicles — escrita (escritor único)
-- ============================================================

exports('createVehicle',       function(row)               if not _invoker_allowed() then return false end return SQL:createVehicle(row)                       end)
exports('updateStatus',        function(plate, status)     if not _invoker_allowed() then return false end return SQL:updateStatus(plate, status)             end)
exports('updatePosition',      function(plate, posJson)    if not _invoker_allowed() then return false end return SQL:updatePosition(plate, posJson)           end)
exports('updateCustomization', function(plate, cj, locked) if not _invoker_allowed() then return false end return SQL:updateCustomization(plate, cj, locked)   end)
exports('updateIpva',          function(plate, until_ts)   if not _invoker_allowed() then return false end return SQL:updateIpva(plate, until_ts)              end)
exports('updateRental',        function(plate, until_ts)   if not _invoker_allowed() then return false end return SQL:updateRental(plate, until_ts)            end)
exports('deleteVehicle',       function(plate)             if not _invoker_allowed() then return false end return SQL:deleteVehicle(plate)                     end)


-- ============================================================
-- vhub_vehicle_keys (autorização)
-- ============================================================

exports('grantKey',        function(plate, cid, kind, by, exp) if not _invoker_allowed() then return false end return SQL:grantKey(plate, cid, kind, by, exp) end)
exports('revokeKey',       function(plate, cid, kind)          if not _invoker_allowed() then return false end return SQL:revokeKey(plate, cid, kind)         end)
exports('hasValidKey',     function(plate, cid)                if not _invoker_allowed() then return false end return SQL:hasValidKey(plate, cid)             end)
exports('listKeys',        function(plate)                     if not _invoker_allowed() then return {}    end return SQL:listKeys(plate)                    end)
exports('listKeysOfChar',  function(char_id)                   if not _invoker_allowed() then return {}    end return SQL:listKeysOfChar(char_id)            end)
exports('purgeExpiredKeys',function()                          if not _invoker_allowed() then return false end return SQL:purgeExpiredKeys()                  end)

-- MANUTENÇÃO: backfills chamados pelo garage APÓS criar vhub_vehicles (conce sobe ANTES do
-- garage; rodar no boot do conce falhava porque a tabela ainda nao existe). Idempotentes.
exports('backfillMirror',   function() if not _invoker_allowed() then return false end return SQL:backfillMirror()   end)
exports('backfillOwnerKeys',function() if not _invoker_allowed() then return false end return SQL:backfillOwnerKeys() end)


-- ============================================================
-- PRONTUÁRIO (vhub_vehicle_state) — estado físico por placa, escritor ÚNICO
-- Semântica: getVehicleState NUNCA é nil para placa registrada (devolve estado de
-- fábrica se nunca persistiu); difere do homônimo legado exports.vhub:getVehicleState
-- (CORE, nil sem VRAM — cadeia inerte pós-PRONTUÁRIO). Consumidores novos usam ESTE.
-- ============================================================

-- estado físico decodificado; fuel é sobreposto pelo snapshot autoritativo do CORE.
exports('getVehicleState', function(plate)
  if not _invoker_allowed() then return nil end
  local state = VHubConce.VState:get(plate)
  if type(state) ~= 'table' then return nil end

  local copy = {}
  for key, value in pairs(state) do copy[key] = value end
  copy.fuel = nil
  local ok, coreState = pcall(function() return exports.vhub:getVehicleState(plate) end)
  if ok and type(coreState) == 'table' then copy.fuel = coreState.fuel end
  return copy
end)

-- Mantém compatibilidade: fuel é delegado ao CORE; demais campos ficam no prontuário.
-- customization é mesclada por chave sobre o persistido (não substituída) — ver VState:save
exports('saveVehicleState', function(plate, patch, source)
  if not _invoker_allowed() then return false end
  if type(patch) ~= 'table' then return false end

  local legacyPatch = {}
  for key, value in pairs(patch) do
    if key ~= 'fuel' then legacyPatch[key] = value end
  end

  local fuelOk = true
  if patch.fuel ~= nil then
    local caller = GetInvokingResource()
    local allowedFuelCaller = caller == 'vhub_garage' or caller == 'vhub_testrunner'
    if allowedFuelCaller then
      local ok, accepted = pcall(function()
        return exports.vhub:commitVehicleState(plate, { fuel = patch.fuel }, 'fuel_compat')
      end)
      fuelOk = ok and accepted == true
    else
      fuelOk = false
    end
  end

  local stateOk = next(legacyPatch) == nil or VHubConce.VState:save(plate, legacyPatch, source)
  return fuelOk and stateOk
end)

-- Executa a migração única de fuel legado para o CORE.
exports('migrateFuelToCore', function()
  if not _invoker_allowed() then return { total = 0, migrated = 0, failed = 1 } end
  return VHubConce.VState:migrateFuelToCore()
end)

-- reparo trusted (manutenção/admin): único caminho que ELEVA health e limpa dano
exports('repairVehicleState', function(plate)
  if not _invoker_allowed() then return false end
  return VHubConce.VState:repair(plate)
end)

-- dossiê (identidade + físico) p/ metadata da chave-item e painéis admin
exports('getVehicleDossier', function(plate)
  if not _invoker_allowed() then return nil end
  return VHubConce.VState:dossier(plate)
end)

-- backfill 1x da customization legada + limpeza de órfãos (garage dispara pós-DDL)
exports('backfillVehicleState',  function() if not _invoker_allowed() then return false end return VHubConce.VState:backfillCustomization() end)
exports('reconcileVehicleState', function() if not _invoker_allowed() then return false end return VHubConce.VState:reconcileOrphans()      end)


-- ============================================================
-- vhub_dealership_stock
-- ============================================================

exports('stockGet',       function(model)               if not _invoker_allowed() then return nil   end return SQL:stockGet(model)              end)
exports('stockSet',       function(model, qty, price)   if not _invoker_allowed() then return false end return SQL:stockSet(model, qty, price)  end)
exports('stockDecrement', function(model)               if not _invoker_allowed() then return false end return SQL:stockDecrement(model)        end)


-- ============================================================
-- CONCESSIONÁRIA (catálogo + transações; result-table p/ o delegator do garage)
-- ============================================================

-- catálogo canônico (o garage faz cache read-only no boot)
exports('getCatalog', function()
  if not _invoker_allowed() then return {} end
  return VHubConce.catalog
end)

-- retorna uma cópia enxuta do catálogo para importadores explicitamente autorizados
exports('getCatalogSnapshot', function()
  local caller = GetInvokingResource()
  if caller and caller ~= GetCurrentResourceName() and not CATALOG_SNAPSHOT_TRUSTED[caller] then
    return {}
  end

  local out = {}
  for model, def in pairs(VHubConce.catalog) do
    if type(model) == 'string' and type(def) == 'table' then
      out[#out + 1] = {
        model = model,
        name  = tostring(def.nome or model):sub(1, 100),
        type  = tostring(def.tipo or ''),
      }
    end
  end
  table.sort(out, function(a, b) return a.model < b.model end)
  return out
end)

-- transações: retornam { ok, msg, ... }; quem fala com a NUI é o garage
exports('buy',        function(src, model, placa, conc) if not _invoker_allowed() then return { ok = false } end return VHubConce.buy(src, model, placa, conc) end)
exports('sellToShop', function(src, plate)              if not _invoker_allowed() then return { ok = false } end return VHubConce.sellToShop(src, plate)        end)
exports('testDrive',  function(src, model, conc)        if not _invoker_allowed() then return { ok = false } end return VHubConce.testDrive(src, model, conc)   end)

-- concede veículo SEM cobrar (pagamento é do CHAMADOR — coinshop moedas/admin).
-- assinatura: grantVehicle(src, model) — SEM placa custom (sem taxa → sem personalização).
-- GRANT_TRUSTED é lista SEPARADA por design; NÃO herda da lista TRUSTED global
-- (só quem vende por outra moeda entra aqui — não misturar com leitores read-only).
local GRANT_TRUSTED = { ['vhub_coinshop'] = true, ['vhub_admin'] = true }
exports('grantVehicle', function(src, model)
  local caller = GetInvokingResource()
  if caller and caller ~= GetCurrentResourceName() and not GRANT_TRUSTED[caller] then
    return { ok = false, code = 'forbidden' }
  end
  src = tonumber(src)
  if not src or type(model) ~= 'string' or model == '' then
    return { ok = false, code = 'bad_args' }
  end
  return VHubConce.grantVehicle(src, model)
end)


-- ============================================================
-- ZONAS (config de localização — dono desde a decisão #25)
-- vec3/vec4 são de uso LOCAL; ao cruzar a fronteira do export, a coord vai
-- ACHATADA p/ primitivo {x,y,z[,h]} (msgpack mangle o vetor nativo — L-19).
-- ============================================================

-- lista achatada das concessionárias p/ o garage agregar no SETUP (read-only, estática)
exports('getZones', function()
  if not _invoker_allowed() then return {} end
  local out = {}
  for _, c in ipairs(VHubConce.cfg.concessionarias or {}) do
    local ts = c.test_spawn
    out[#out + 1] = {
      id = c.id, label = c.label,
      x = c.coord.x, y = c.coord.y, z = c.coord.z, raio = c.raio,
      tipos = c.tipos, blip = c.blip,
      test_spawn = ts and { x = ts.x, y = ts.y, z = ts.z, h = ts.w } or nil,
    }
  end
  return out
end)
