-- server/exports.lua — superfície interna do vhub_conce (autoridade chave/placa/dono)
-- Todos os exports exigem invoker confiável: conce é a autoridade, não API pública.
-- A superfície pública de leitura continua em vhub_garage (que proxia para cá).
-- Cada export roda no thread do chamador (SQL usa Citizen.Await) — não envolver em CreateThread.
---@diagnostic disable: undefined-global

local SQL  = VHubConce.SQL
local Core = VHubConce.Core

local TRUSTED = {
  ['vhub']            = true,
  ['vhub_garage']     = true,
  ['vhub_ferinha']    = true,
  ['vhub_admin']      = true,
  ['vhub_inventory']  = true,
  ['vhub_vehcontrol'] = true,   -- telemetria física + engine de skill → saveVehicleState (telemetry/handling)
  ['vhub_legacyfuel'] = true,   -- bomba de combustível → saveVehicleState {fuel}
  ['vhub_testrunner'] = true,   -- testes server-side (somente ambiente de teste)
  ['vhub_custom']     = true,   -- oficina (bennys/mec/oficina) → saveVehicleState (cosmetic/tune/repair)
  ['vhub_nitro']      = true,   -- nitro → saveVehicleState (customization.nitro, source='nitro')
  ['vhub_vrcs']       = true,   -- Race Cinema: getVehicleState (read-only) p/ preservar aparência no replay
}

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

-- estado físico decodificado da placa (fuel/health/odômetro/customization/damage)
exports('getVehicleState', function(plate)
  if not _invoker_allowed() then return nil end
  return VHubConce.VState:get(plate)
end)

-- aplica patch parcial validado (telemetria/store/bomba/cosmetic/tune/repair); source define as regras
-- customization é mesclada por chave sobre o persistido (não substituída) — ver VState:save
exports('saveVehicleState', function(plate, patch, source)
  if not _invoker_allowed() then return false end
  return VHubConce.VState:save(plate, patch, source)
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

-- transações: retornam { ok, msg, ... }; quem fala com a NUI é o garage
exports('buy',        function(src, model, placa, conc) if not _invoker_allowed() then return { ok = false } end return VHubConce.buy(src, model, placa, conc) end)
exports('sellToShop', function(src, plate)              if not _invoker_allowed() then return { ok = false } end return VHubConce.sellToShop(src, plate)        end)
exports('testDrive',  function(src, model, conc)        if not _invoker_allowed() then return { ok = false } end return VHubConce.testDrive(src, model, conc)   end)


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
