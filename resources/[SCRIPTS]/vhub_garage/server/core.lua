-- server/core.lua  state em mem ria + helpers + sess es
-- L da por todos os m dulos. N o faz SQL diretamente (delega a SQL.*).
---@diagnostic disable: undefined-global

local SQL = VHubGarage.SQL
local U   = VHubGarage.U
local CFG = VHubGarage.cfg

local M = {}; VHubGarage.Core = M

-- ----------------------------------------------------------------------------
-- Sess es vivas (src   user)
-- ----------------------------------------------------------------------------
M.sessions = {}

function M:setSession(src, user) self.sessions[src] = user end
function M:getSession(src)       return self.sessions[tonumber(src)] end
function M:dropSession(src)      self.sessions[tonumber(src)] = nil end
function M:getCharId(src)
  local u = self:getSession(src); return u and u.char_id or nil
end
function M:getUid(src)
  local u = self:getSession(src); return u and u.id or nil
end

-- ----------------------------------------------------------------------------
-- Cache de runtime de ve culos test-drive (placa virtual N O entra no DB)
-- ----------------------------------------------------------------------------
M.testDrive = {}   -- [src] = { plate, expires_at, model, conc_id }

-- ----------------------------------------------------------------------------
-- Gera  o de placa  nica
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- Helpers de integra  o com outros resources
-- ----------------------------------------------------------------------------
local function safe(callfn)
  local ok, r = pcall(callfn); return ok and r or nil
end

function M.pay(src, valor)
  return safe(function()
    return exports.vhub_money:tryFullPayment(src, valor)
  end) == true
end

function M.payWallet(src, valor)
  return safe(function()
    return exports.vhub_money:tryPayment(src, valor)
  end) == true
end

function M.refund(src, valor)
  safe(function() exports.vhub_money:giveWallet(src, valor) end)
end

function M.giveBank(src, valor)
  safe(function() exports.vhub_money:giveBank(src, valor) end)
end

function M.hasKeyItem(src, plate)
  return safe(function()
    return exports.vhub_inventory:hasVehicleKey(src, plate)
  end) == true
end

function M.giveKeyItem(src, plate)
  return safe(function()
    return exports.vhub_inventory:giveVehicleKey(src, plate)
  end) == true
end

function M.takeKeyItem(src, plate)
  return safe(function()
    return exports.vhub_inventory:takeVehicleKey(src, plate)
  end) == true
end

function M.hasPerm(src, perm)
  return safe(function()
    return exports.vhub_groups:hasPermission(src, perm)
  end) == true
end

-- ----------------------------------------------------------------------------
-- Verificar se o jogador pode operar a placa (autoriza  o l gica)
--   Delega ao vhub_conce (autoridade unica de chave/placa desde a FASE 1).
--   canOperate = chave-item fisica + (e dono OU autorizacao valida no DB).
--   Os 3 call-sites ja gateiam hasKeyItem antes, entao a delegacao e behavior-neutral.
-- ----------------------------------------------------------------------------
function M:authorized(src, plate)
  return exports.vhub_conce:canOperate(src, plate) == true
end

-- ----------------------------------------------------------------------------
-- Resolver  nico de concession ria por id (decis o #25)
--   A config de localiza  o da concession ria vive em vhub_conce; o garage
--   faz PULL no boot (VHubGarage.concessionarias). Fonte  nica para os 3
--   call-sites antigos de getConc (dealership/rental/REQ_CATALOG) — sem c pia.
-- ----------------------------------------------------------------------------
function M:resolveConc(id)
  for _, c in ipairs(VHubGarage.concessionarias or {}) do
    if c.id == id then return c end
  end
end

-- ----------------------------------------------------------------------------
-- Notifica  o ao cliente (wrapper sobre evento padr o)
-- ----------------------------------------------------------------------------
function M.notify(src, msg)
  TriggerClientEvent(VHubGarage.E.NOTIFY, src, tostring(msg or ''))
end

-- ----------------------------------------------------------------------------
-- Snapshot enviado ao NUI para um ve culo
-- ----------------------------------------------------------------------------
function M:vehicleSnapshot(row)
  local entry = VHubGarage.catalog[row.model] or {}
  return {
    plate       = row.plate,
    model       = row.model,
    nome        = entry.nome or row.model,
    vtype       = row.vtype,
    categoria   = row.category,
    status      = row.status,
    locked      = row.locked == 1 or row.locked == true,
    preco       = entry.preco or 0,
    stats       = entry.stats or { vel=50, acel=50, freio=50, dir=50 },
    tags        = entry.tags or {},
    ipva_until  = row.ipva_paid_until,
    rented_until= row.rented_until,
    last_seen   = row.last_seen_at,
  }
end

-- ----------------------------------------------------------------------------
-- Log conveniente (encode JSON do payload)
-- ----------------------------------------------------------------------------
function M:log(plate, action, actor_id, payload)
  SQL:log(plate, action, actor_id, U.jenc(payload))
end
