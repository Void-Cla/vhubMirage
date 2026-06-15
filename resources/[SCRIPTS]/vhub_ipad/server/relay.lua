---@diagnostic disable: undefined-global, lowercase-global

-- server/relay.lua — BROKER do canal app↔resource (App SDK embutido).
-- O iPad é roteador OPACO: NÃO lê nem persiste o payload de domínio (L-04).
-- Só transporta + injeta o `src` confiável + valida ACL (zero-trust, L-01).

VHubIpad = VHubIpad or {}

local Registry = VHubIpad.Registry
local E        = VHubIpadE


-- ============================================================
-- ANTI-DoS — cap de profundidade/keys do payload (cliente ou resource)
-- ============================================================

local MAX_DEPTH, MAX_KEYS = 5, 100

-- true se o payload está dentro dos limites (tabela hostil gigante/profunda = false)
local function safePayload(v, depth)
  if type(v) ~= 'table' then return true end
  depth = depth or 1
  if depth > MAX_DEPTH then return false end
  local n = 0
  for _, val in pairs(v) do
    n = n + 1
    if n > MAX_KEYS then return false end
    if not safePayload(val, depth + 1) then return false end
  end
  return true
end


-- ============================================================
-- APP → SERVER (broker; cliente só nomeia o app, servidor autoriza)
-- ============================================================

RegisterNetEvent(E.APP_RELAY)
AddEventHandler(E.APP_RELAY, function(app, action, data)
  local src = source
  IpadLog(("appRelay recebido: src=%s app=%s action=%s"):format(tostring(src), tostring(app), tostring(action)))

  if type(app) ~= 'string' or type(action) ~= 'string' then return end
  if data ~= nil and not safePayload(data) then IpadLog('appRelay: payload rejeitado (cap)'); return end

  local relay = Registry:getRelay(app)
  if not relay then IpadLog('appRelay: SEM descritor relay para app='..app); return end
  if not Registry:permittedFor(src, app) then IpadLog('appRelay: ACL negou src='..src..' app='..app); return end
  if GetResourceState(relay.resource) ~= 'started' then
    IpadLog('appRelay: resource '..relay.resource..' NÃO está started'); return
  end

  -- payload OPACO: o iPad não interpreta; só transporta + injeta o src confiável.
  -- IMPORTANTE: a forma colchete `exports[res][name](a,...)` descarta o 1º arg como `self`.
  -- Passamos o proxy como self explícito (equivale a `exports.res:name(...)` com nome dinâmico).
  local proxy = exports[relay.resource]
  local ok, err = pcall(function() return proxy[relay.export](proxy, src, action, data) end)
  if ok then
    IpadLog(('appRelay OK: %s:%s(src=%s, %s)'):format(relay.resource, relay.export, tostring(src), action))
  else
    IpadLog(('appRelay ERRO: %s:%s → %s'):format(relay.resource, relay.export, tostring(err)))
  end
end)


-- ============================================================
-- SERVER → APP (push do resource DONO para o app embutido)
-- ============================================================

-- chamado pelo SERVER do resource dono para empurrar dados ao seu app no iPad.
-- OWNER-BINDING (fail-closed): só o resource DONO do app pode empurrar para ele.
exports('appPush', function(src, app, action, data)
  IpadLog(('appPush recebido: caller=%s src=%s app=%s action=%s'):format(
    tostring(GetInvokingResource()), tostring(src), tostring(app), tostring(action)))

  if type(src) ~= 'number' or type(app) ~= 'string' or type(action) ~= 'string' then
    IpadLog('appPush: args inválidos'); return false
  end
  if data ~= nil and not safePayload(data) then IpadLog('appPush: payload rejeitado (cap)'); return false end

  local relay = Registry:getRelay(app)
  if not relay then IpadLog('appPush: app sem relay='..app); return false end

  -- só o resource dono do app empurra (chamada local do próprio iPad = caller nil, permitida)
  local caller = GetInvokingResource()
  if caller ~= nil and caller ~= relay.resource then
    IpadLog(('appPush: NEGADO (caller=%s ≠ dono=%s)'):format(tostring(caller), relay.resource)); return false
  end

  TriggerClientEvent(E.APP_PUSH, src, { app = app, action = action, data = data })
  IpadLog(('appPush OK → src=%s app=%s action=%s'):format(tostring(src), app, action))
  return true
end)
