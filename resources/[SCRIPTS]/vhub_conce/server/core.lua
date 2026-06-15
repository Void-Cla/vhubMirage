-- server/core.lua — sessões vivas + integração + autoridade de operação por chave
-- Resolve cid SEMPRE server-side (sessão própria via vHub:characterLoad), nunca confia
-- em cid vindo do chamador (L-01). Lê físico via export do CORE; nunca é fonte do físico.
---@diagnostic disable: undefined-global

local SQL = VHubConce.SQL
local U   = VHubConce.U
local CFG = VHubConce.cfg

local M = {}; VHubConce.Core = M


-- ============================================================
-- SESSÕES (src → user) — cache do mesmo upstream do CORE (não é 2ª fonte)
-- ============================================================

M.sessions = {}

-- registra/atualiza a sessão viva do jogador
function M:setSession(src, user) self.sessions[tonumber(src)] = user end

-- remove a sessão ao sair
function M:dropSession(src) self.sessions[tonumber(src)] = nil end

-- retorna o user vivo do src (ou nil)
function M:getSession(src) return self.sessions[tonumber(src)] end

-- char_id atual do src (server-authoritative)
function M:getCharId(src)
  local u = self:getSession(src); return u and u.char_id or nil
end


-- ============================================================
-- INTEGRAÇÃO (chave-item física vive no vhub_inventory)
-- ============================================================

local function safe(callfn)
  local ok, r = pcall(callfn); return ok and r or nil
end

-- jogador carrega a chave-item física da placa?
function M.hasKeyItem(src, plate)
  return safe(function()
    return exports.vhub_inventory:hasVehicleKey(src, plate)
  end) == true
end

-- entrega a chave-item física ao jogador (true se coube no inventário)
function M.giveKeyItem(src, plate)
  return safe(function() return exports.vhub_inventory:giveVehicleKey(src, plate) end) == true
end

-- remove a chave-item física do jogador
function M.takeKeyItem(src, plate)
  return safe(function() return exports.vhub_inventory:takeVehicleKey(src, plate) end) == true
end

-- cobra carteira+banco (true se pagou)
function M.pay(src, valor)
  return safe(function() return exports.vhub_money:tryFullPayment(src, valor) end) == true
end

-- cobra só carteira (true se pagou)
function M.payWallet(src, valor)
  return safe(function() return exports.vhub_money:tryPayment(src, valor) end) == true
end

-- devolve dinheiro à carteira (estorno)
function M.refund(src, valor)
  safe(function() exports.vhub_money:giveWallet(src, valor) end)
end

-- registra ação no log de auditoria (encode JSON do payload)
function M:log(plate, action, actor_id, payload)
  SQL:log(plate, action, actor_id, U.jenc(payload))
end


-- ============================================================
-- AUTORIDADE — quem pode OPERAR a placa (spawn/store/controle)
-- ============================================================

-- dono real da placa? (verdade única: vhub_vehicles.char_id)
function M:isOwner(src, plate)
  local cid = self:getCharId(src); if not cid then return false end
  local v = SQL:getVehicle(plate); if not v then return false end
  return v.char_id == cid
end

-- pode operar a placa? chave-item física + (é dono OU autorização válida no DB).
-- FASE 1 behavior-neutral (replica garage Core:authorized + gate hasKeyItem dos call-sites).
-- A semântica pura-chave (remover o ramo "é dono") entra na FASE 3 com o cron 24h.
function M:canOperate(src, plate)
  local cid = self:getCharId(src); if not cid then return false end
  local p   = U.normalizePlate(plate); if not p then return false end
  if not M.hasKeyItem(src, p) then return false end
  local v = SQL:getVehicle(p); if not v then return false end
  if v.char_id == cid then return true end
  return SQL:hasValidKey(p, cid)
end

-- transfere o DONO REAL da placa (atômico: char_id + chave-row 'owner'). FASE 4.
-- Único ponto que persiste dono (invariante §5.1). A chave-item física e o dinheiro
-- são responsabilidade do chamador (ferinha/garage), na ordem money→transferOwner→giveKey.
function M:transferOwner(plate, new_cid)
  local p = U.normalizePlate(plate); if not p then return false end
  new_cid = tonumber(new_cid); if not new_cid then return false end
  local v = SQL:getVehicle(p); if not v then return false end
  local old = v.char_id
  SQL:updateOwner(p, new_cid)
  if old and old ~= new_cid then SQL:revokeKey(p, old, 'owner') end
  SQL:grantKey(p, new_cid, 'owner', new_cid, nil)
  return true
end


-- ============================================================
-- CONCESSIONÁRIA (placa única + cache de test-drive)
-- ============================================================

M.testDrive = {}   -- [src] = { model, conc_id, expires_at } — placa virtual, fora do DB

-- gera placa única: custom validada (ou erro) OU aleatória sem colisão
function M:newPlate(custom)
  if custom and custom ~= '' then
    local p = U.normalizePlate(custom)
    if not p then return nil, 'placa_invalida' end
    if SQL:plateExists(p) then return nil, 'placa_em_uso' end
    return p
  end
  for _ = 1, 60 do
    local p = U.randomPlate()
    if not SQL:plateExists(p) then return p end
  end
  return 'VH' .. tostring(os.time() % 100000)
end


-- ============================================================
-- CRON — devolução de posse temporária (24h). Chamado pela thread fria (init).
-- ============================================================

-- src online cujo personagem é char_id (ou nil se offline)
function M:srcByCharId(cid)
  for src, u in pairs(self.sessions) do
    if u and u.char_id == cid then return src end
  end
end

-- devolve toda posse temporária vencida ao dono real:
-- revoga a linha + tira a chave-item (se online) + volta o carro p/ a garagem do dono.
function M:returnExpiredHoldings()
  local rows = SQL:listExpiredTempKeys(os.time(), CFG.temp_hold_ttl_s) or {}
  for _, k in ipairs(rows) do
    SQL:revokeKey(k.plate, k.char_id, k.kind)
    local holder = self:srcByCharId(k.char_id)
    if holder then M.takeKeyItem(holder, k.plate) end
    local v = SQL:getVehicle(k.plate)
    if v and v.status ~= 'garage' then
      SQL:updateStatus(k.plate, 'garage')
      TriggerClientEvent('vhub_garage:doDespawn', -1, k.plate)
    end
    Citizen.Wait(0)   -- lote: não trava a thread em varreduras grandes (L-06)
  end
end
