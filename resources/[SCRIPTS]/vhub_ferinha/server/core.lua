-- server/core.lua — sessões + integração (money/inventory) + ponte com conce
-- Resolve cid SEMPRE server-side (sessão própria via vHub:characterLoad). ferinha
-- NUNCA escreve char_id direto: a troca de dono passa por exports.vhub_conce:transferOwner.
---@diagnostic disable: undefined-global

local SQL = VHubFerinha.SQL

local M = {}; VHubFerinha.Core = M


-- ============================================================
-- SESSÕES (src → user)
-- ============================================================

M.sessions = {}

function M:setSession(src, user) self.sessions[tonumber(src)] = user end
function M:dropSession(src)      self.sessions[tonumber(src)] = nil end
function M:getSession(src)       return self.sessions[tonumber(src)] end

-- char_id atual do src
function M:getCharId(src)
  local u = self:getSession(src); return u and u.char_id or nil
end

-- src online cujo personagem é char_id (ou nil se offline) — usado no escrow/entrega
function M:srcByCharId(cid)
  for src, u in pairs(self.sessions) do
    if u and u.char_id == cid then return src end
  end
end


-- ============================================================
-- INTEGRAÇÃO (money + inventory + conce)
-- ============================================================

local function safe(fn) local ok, r = pcall(fn); return ok and r or nil end

-- cobra carteira+banco (true se pagou)
function M.pay(src, valor)       return safe(function() return exports.vhub_money:tryFullPayment(src, valor) end) == true end
-- cobra só carteira
function M.payWallet(src, valor) return safe(function() return exports.vhub_money:tryPayment(src, valor) end) == true end
-- devolve à carteira do bidder ONLINE (estorno do delta no lance ao vivo)
function M.refund(src, valor)    safe(function() exports.vhub_money:giveWallet(src, valor) end) end
-- credita o BANCO por char_id, ONLINE ou OFFLINE (payout do vendedor / estorno de perdedor).
-- Offline-safe: o vhub_money incrementa no DB se o char não estiver online (sem perda silenciosa).
function M.payChar(cid, valor)   return safe(function() return exports.vhub_money:giveBankChar(cid, valor, 'auction') end) == true end

-- chave-item física
function M.giveKeyItem(src, plate) return safe(function() return exports.vhub_inventory:giveVehicleKey(src, plate) end) == true end
function M.takeKeyItem(src, plate) return safe(function() return exports.vhub_inventory:takeVehicleKey(src, plate) end) == true end

-- ponte com a autoridade de veículo (conce)
function M.getVehicle(plate)         return safe(function() return exports.vhub_conce:getVehicle(plate) end) end
function M.setStatus(plate, status)  return safe(function() return exports.vhub_conce:updateStatus(plate, status) end) end
function M.transferOwner(plate, cid) return safe(function() return exports.vhub_conce:transferOwner(plate, cid) end) == true end

-- auditoria (encode JSON)
function M:log(plate, action, actor_id, payload)
  SQL:log(plate, action, actor_id, (payload and json.encode(payload)) or nil)
end
