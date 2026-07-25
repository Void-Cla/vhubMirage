-- core.lua — fronteiras, logs, rates e identidade de sessão do SIMS
---@diagnostic disable: undefined-global

VHubSimsCore = VHubSimsCore or {}

local Core = VHubSimsCore
local CFG = VHubSims.cfg
local last = {}
local sequence = 0

Core.ready = false


-- ============================================================
-- OBSERVABILIDADE
-- ============================================================

-- registra evento sem expor falha do logger ao domínio
function Core.log(level, message, metadata)
  pcall(function() exports.vhub:log(level, 'sims', message, metadata or {}) end)
end

-- envia notificação canônica ao jogador
function Core.notify(src, kind, message)
  TriggerClientEvent(VHubSims.E.NOTIFY, src, kind, message)
end


-- ============================================================
-- FRONTEIRAS
-- ============================================================

-- chama export externo isolando throw do provider
function Core.call(resource, method, ...)
  local args = { ... }
  local ok, result = pcall(function()
    return exports[resource][method](exports[resource], table.unpack(args))
  end)
  if not ok then
    Core.log('error', 'Falha em dependência externa.', { resource = resource, method = method })
    return false, nil
  end
  return true, result
end

-- retorna usuário online e personagem atual derivados do CORE
function Core.getUser(src)
  if type(src) ~= 'number' or src < 1 or GetPlayerName(src) == nil then return nil end
  local ok, charId = Core.call('vhub', 'getCharacterId', src)
  charId = ok and tonumber(charId) or nil
  if not charId or charId < 1 then return nil end
  return { source = src, char_id = charId }, charId
end

-- retorna true quando um retorno de contrato representa sucesso
function Core.resultOk(result)
  if result == true then return true end
  return type(result) == 'table' and result.ok == true
end

-- extrai erro semântico estável de um retorno externo
function Core.resultError(result, fallback)
  return type(result) == 'table' and type(result.err) == 'string' and result.err or fallback
end

-- filtra o domínio SIMS e delega a normalização APV2 ao owner HSS
function Core.sanitizePatch(payload, mode)
  if type(payload) == 'table' and next(payload) == nil then return {} end
  local filtered, filterError = VHubSims.APShape.filterMode(payload, mode)
  if not filtered then return nil, filterError end
  local ok, result = Core.call('vhub_hss', 'sanitizeCustomizationPatch', filtered)
  if not ok or not Core.resultOk(result) or type(result.patch) ~= 'table' then
    return nil, Core.resultError(result, 'dependency')
  end
  return result.patch
end

-- lê posição canônica pelo owner HSS, sem native física no SIMS
function Core.getPosition(src)
  local ok, first, second, third = pcall(function()
    return exports.vhub_hss:getPosition(src)
  end)
  if not ok then return nil end
  if type(first) == 'table' then
    local position = first.position or first
    local x = tonumber(position.x or position[1])
    local y = tonumber(position.y or position[2])
    local z = tonumber(position.z or position[3])
    return x and y and z and { x = x, y = y, z = z } or nil
  end
  first, second, third = tonumber(first), tonumber(second), tonumber(third)
  return first and second and third and { x = first, y = second, z = third } or nil
end


-- ============================================================
-- RATE E TOKENS
-- ============================================================

-- aplica rate O(1) por jogador e ação
function Core.rate(src, key)
  local interval = CFG.rates[key]
  if type(interval) ~= 'number' then return false end

  local now = GetGameTimer()
  local bucket = last[src]
  if not bucket then bucket = {}; last[src] = bucket end
  if now - (bucket[key] or -interval) < interval then return false end
  bucket[key] = now
  return true
end

-- cria identificador opaco único no processo
function Core.token(prefix, src)
  sequence = sequence + 1
  return ('%s:%d:%d:%08x%08x%08x'):format(prefix, tonumber(src) or 0, sequence,
    math.random(0, 0x7fffffff), math.random(0, 0x7fffffff), GetGameTimer() & 0xffffffff)
end

-- libera os buckets efêmeros do jogador
function Core.cleanup(src)
  last[src] = nil
end
