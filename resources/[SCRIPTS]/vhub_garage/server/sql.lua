-- server/sql.lua  reposit rio centralizado (todas as queries SQL vivem aqui)
-- Resources externos N O usam S:prepare()/S:query() do core  decis o congelada em contexto.md.
-- Usamos exports.oxmysql diretamente. Toda fun  o pode ser chamada dentro de thread (Citizen.Await).
---@diagnostic disable: undefined-global

local M = {}; VHubGarage = VHubGarage or {}; VHubGarage.SQL = M

local ox = function() return exports['oxmysql'] end

-- helpers que devolvem Promise resolvida em thread ---------------------------
local function pscalar(sql, args)
  local p = promise.new()
  ox():scalar(sql, args or {}, function(r) p:resolve(r) end)
  return Citizen.Await(p)
end

local function pexec(sql, args)
  local p = promise.new()
  ox():execute(sql, args or {}, function(r) p:resolve(r) end)
  return Citizen.Await(p)
end

local function pquery(sql, args)
  local p = promise.new()
  ox():query(sql, args or {}, function(r) p:resolve(r or {}) end)
  return Citizen.Await(p)
end

M.scalar  = pscalar
M.execute = pexec
M.query   = pquery

-- ----------------------------------------------------------------------------
-- Inicializa o schema (cria tabelas se n o existirem)
-- ----------------------------------------------------------------------------
function M:initSchema()
  -- O DDL ainda mora aqui ate a FASE 6. O espelho/backfill vh_vehicles migrou
  -- para vhub_conce (escritor unico de vh_vehicles desde a FASE 1).
  local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
  if not schema then return false end
  return VHubSQLScript.aplicar(schema, function(instrucao)
    MySQL.query.await(instrucao, {})
  end)
end

-- ----------------------------------------------------------------------------
-- vhub_vehicles  (PROXY -> vhub_conce: escritor unico desde a FASE 1)
-- O dado e a verdade vivem no vhub_conce; aqui apenas encaminhamos a chamada para
-- manter os ~16 call-sites do garage inalterados ate a FASE 6.
-- ----------------------------------------------------------------------------
-- existe linha para a placa?
function M:plateExists(plate)               return exports.vhub_conce:plateExists(plate) end
-- retorna a linha de negocio do veiculo (read-only)
function M:getVehicle(plate)                return exports.vhub_conce:getVehicle(plate) end
-- veiculos cujo dono real e char_id
function M:listByOwner(char_id)             return exports.vhub_conce:listByOwner(char_id) end
-- veiculos em um status
function M:listByStatus(status)             return exports.vhub_conce:listByStatus(status) end
-- cria registro inicial (compra) + espelho vh_vehicles (feito no conce)
function M:createVehicle(row)               return exports.vhub_conce:createVehicle(row) end
-- muda status (garage/out/impound/auction/rental/sold)
function M:updateStatus(plate, status)      return exports.vhub_conce:updateStatus(plate, status) end
-- CAS e compensação usam exclusivamente o escritor canônico do registro.
function M:confirmarRetirada(plate, anterior, posJson) return exports.vhub_conce:confirmarRetirada(plate, anterior, posJson) end
function M:cancelarRetirada(plate, anterior, posJson) return exports.vhub_conce:cancelarRetirada(plate, anterior, posJson) end
-- atualiza ultima posicao conhecida
function M:updatePosition(plate, posJson)   return exports.vhub_conce:updatePosition(plate, posJson) end
-- atualiza estetica + trava
function M:updateCustomization(plate, custJson, locked)
  return exports.vhub_conce:updateCustomization(plate, custJson, locked)
end
-- atualiza vencimento de IPVA
function M:updateIpva(plate, paidUntil)     return exports.vhub_conce:updateIpva(plate, paidUntil) end
-- remove veiculo + espelho vh_vehicles (feito no conce)
function M:deleteVehicle(plate)             return exports.vhub_conce:deleteVehicle(plate) end

-- ----------------------------------------------------------------------------
-- vhub_vehicle_keys  (PROXY -> vhub_conce: escritor unico desde a FASE 1)
-- ----------------------------------------------------------------------------
-- concede/atualiza autorizacao logica de chave
function M:grantKey(plate, char_id, kind, granted_by, expires_at)
  return exports.vhub_conce:grantKey(plate, char_id, kind, granted_by, expires_at)
end
-- revoga chave (kind especifico, ou todas menos 'owner')
function M:revokeKey(plate, char_id, kind)
  return exports.vhub_conce:revokeKey(plate, char_id, kind)
end
-- lista autorizacoes de uma placa
function M:listKeys(plate)
  return exports.vhub_conce:listKeys(plate)
end
-- remove autorizacoes expiradas
function M:purgeExpiredKeys()
  return exports.vhub_conce:purgeExpiredKeys()
end

-- ----------------------------------------------------------------------------
-- vhub_auctions / vhub_auction_bids  (PROXY -> vhub_ferinha desde a FASE 4)
-- A logica de leilao (criar/lance/finalizar/cancelar/escrow/cron) mora no ferinha.
-- So a leitura usada pelo painel admin (info) permanece como proxy.
-- ----------------------------------------------------------------------------
-- leilao ativo de uma placa (info admin)
function M:getAuctionByPlate(plate)
  return exports.vhub_ferinha:getAuctionByPlate(plate)
end

-- ----------------------------------------------------------------------------
-- vhub_impound
-- ----------------------------------------------------------------------------
function M:impoundPut(plate, reason, fee, by)
  return pexec([[
    INSERT INTO vhub_impound (plate, reason, fee, impounded_by, impounded_at)
    SELECT ?, ?, ?, ?, ? FROM DUAL
     WHERE NOT EXISTS (SELECT 1 FROM vhub_impound WHERE plate = ? AND released_at IS NULL)
  ]], { plate, reason or 'apreendido', fee or 0, by, os.time(), plate })
end

function M:impoundGetActive(plate)
  local r = pquery([[
    SELECT * FROM vhub_impound
    WHERE plate = ? AND released_at IS NULL
    ORDER BY id DESC LIMIT 1
  ]], { plate })
  return r and r[1] or nil
end

function M:impoundRelease(id, by)
  return pexec(
    'UPDATE vhub_impound SET released_at = ?, released_by = ? WHERE id = ?',
    { os.time(), by, id })
end

function M:impoundList()
  return pquery([[
    SELECT i.*, v.model, v.vtype
      FROM vhub_impound i
      JOIN vhub_vehicles v ON v.plate = i.plate
     WHERE i.released_at IS NULL
     ORDER BY i.impounded_at DESC
  ]], {})
end

-- ----------------------------------------------------------------------------
-- vhub_dealership_stock  (PROXY -> vhub_conce: escritor unico desde a FASE 1)
-- ----------------------------------------------------------------------------
-- estoque atual do modelo (ou nil = ilimitado)
function M:stockGet(model)               return exports.vhub_conce:stockGet(model) end
-- define estoque/preco custom do modelo
function M:stockSet(model, qty, price)   return exports.vhub_conce:stockSet(model, qty, price) end

-- ----------------------------------------------------------------------------
-- vhub_vehicle_log
-- ----------------------------------------------------------------------------
function M:log(plate, action, actor_id, payload)
  pexec([[
    INSERT INTO vhub_vehicle_log (plate, action, actor_id, payload, created_at)
    VALUES (?, ?, ?, ?, ?)
  ]], { plate, action, actor_id, payload, os.time() })
end
