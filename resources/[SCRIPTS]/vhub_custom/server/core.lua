-- server/core.lua — sessões, rate-limit, wrappers de conce e money para o vhub_custom
---@diagnostic disable: undefined-global

local CFG = VHubCustom.cfg

VHubCustom.Core = {}
local Core = VHubCustom.Core


-- ============================================================
-- SESSÕES (char_id por src; limpo em playerDropped)
-- ============================================================

local _sessions = {}   -- [src] = { char_id }
local _rates    = {}   -- [src][ev] = { ts, n }


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- registra sessão quando personagem carrega
AddEventHandler('vHub:characterLoad', function(user)
  if not user then return end
  _sessions[user.source] = { char_id = user.char_id }
end)

-- limpa ao desconectar (sem leak por src)
AddEventHandler('playerDropped', function()
  local src = source
  _sessions[src] = nil
  _rates[src]    = nil
end)


-- ============================================================
-- RATE LIMITING (sliding window por GetGameTimer — ms)
-- ============================================================

-- retorna true se dentro do limite, false se excedeu
function Core.rateOK(src, ev)
  local cfg = CFG.rates[ev]
  if not cfg then return true end
  local now = GetGameTimer()
  _rates[src] = _rates[src] or {}
  local r = _rates[src][ev]
  if not r or (now - r.ts) > cfg.window then
    r = { ts = now, n = 0 }
  end
  r.n = r.n + 1
  _rates[src][ev] = r
  return r.n <= cfg.max
end


-- ============================================================
-- SESSÃO / AUTH
-- ============================================================

-- retorna char_id da sessão ativa, ou nil
function Core.getCharId(src)
  local s = _sessions[src]
  return s and s.char_id or nil
end

-- verifica se o jogador pode operar a placa (chave-item + owner via conce)
-- OBRIGATÓRIO antes de qualquer saveVehicleState
function Core.canOperate(src, plate)
  local ok = false
  local pok, perr = pcall(function()
    ok = exports.vhub_conce:canOperate(src, plate) == true
  end)
  if not pok then VHubCustom.log('[core] canOperate ERRO export: ' .. tostring(perr)) end
  return pok and ok
end

-- estado físico do prontuário (read-only)
function Core.getVehicleState(plate)
  local st
  local pok, perr = pcall(function() st = exports.vhub_conce:getVehicleState(plate) end)
  if not pok then VHubCustom.log('[core] getVehicleState ERRO export: ' .. tostring(perr)) end
  return st
end

-- persiste patch via escritor único do conce
-- plate: string normalizada | patch: tabela | source: 'cosmetic'/'tune'/'repair'
function Core.saveVehicleState(plate, patch, src_type)
  local ok = false
  local pok, perr = pcall(function()
    ok = exports.vhub_conce:saveVehicleState(plate, patch, src_type) == true
  end)
  if not pok then VHubCustom.log('[core] saveVehicleState ERRO export: ' .. tostring(perr)) end
  return ok
end

-- reparo total trusted (delega ao conce — eleva health + limpa dano)
function Core.repairVehicleState(plate)
  local ok = false
  pcall(function()
    ok = exports.vhub_conce:repairVehicleState(plate) == true
  end)
  return ok
end


-- ============================================================
-- MONEY (vhub_money — abstração de cobrança)
-- ============================================================

-- cobra do jogador (carteira → banco); retorna true se sucesso
-- usa tryFullPayment do vhub_money (mesmo caminho de garage/ferinha — export público)
function Core.pay(src, amount)
  if amount <= 0 then return true end
  local ok = false
  pcall(function()
    ok = exports.vhub_money:tryFullPayment(src, amount) == true
  end)
  return ok
end

-- notifica o jogador (feedpost nativo via client do próprio resource)
function Core.notify(src, msg, type_)
  TriggerClientEvent(VHubCustom.E.NOTIFY, src, tostring(msg or ''), type_ or 'info')
end

-- notificação de DEBUG (só quando cfg.debug); prefixa [DEBUG] para distinguir
function Core.dbg(src, msg)
  if not CFG.debug then return end
  TriggerClientEvent(VHubCustom.E.NOTIFY, src, '[DEBUG] ' .. tostring(msg or ''), 'info')
  VHubCustom.log('[dbg] src=' .. tostring(src) .. ' | ' .. tostring(msg))
end

-- log de auditoria no formato padrão do resource
function Core.log(plate, action, cid, extra)
  local parts = { ('%s | plate=%s | cid=%s'):format(action, tostring(plate), tostring(cid)) }
  if type(extra) == 'table' then
    for k, v in pairs(extra) do parts[#parts+1] = k..'='..tostring(v) end
  end
  VHubCustom.log(table.concat(parts, ' | '))
end
