---@diagnostic disable: undefined-global, lowercase-global

-- server/sessions.lua — cache local de usuarios autenticados.
--
-- Substitui o user_of() com retry de 2s + acesso direto a _vHub.Auth._sessions
-- (que viola contrato pois _sessions tem prefixo _, ou seja, API privada do core).
--
-- A verdade aqui e populada via DOIS sinais publicos do vhub:
--   1) `vHub:characterLoad` (server-side) — emitido apos auth do personagem
--   2) `playerDropped`                    — remove a sessao
--
-- get() retorna IMEDIATAMENTE (zero Wait, zero retry). Se o handler de evento
-- ainda nao foi chamado, get() devolve nil e o caller decide o fallback —
-- esse e o comportamento correto pois o cache reflete o estado real.


VHubRachaSessions = {}
local S = VHubRachaSessions


-- ============================================================
-- STATE (cache em memoria, chave = source numerico)
-- ============================================================

local _cache = {}   -- { [src:number] = user }


-- ============================================================
-- LIFECYCLE — popula via eventos publicos do vhub core
-- ============================================================

-- Registra sessao quando o personagem termina de carregar
AddEventHandler('vHub:characterLoad', function(user)
    if type(user) ~= 'table' then return end
    local src = tonumber(user.source)
    if not src or src <= 0 then return end
    _cache[src] = user
end)


-- Remove sessao no drop
AddEventHandler('playerDropped', function()
    local src = source
    if src and src > 0 then _cache[src] = nil end
end)


-- ============================================================
-- API PUBLICA
-- ============================================================

-- Retorna o user da sessao ativa. nil se nao autenticado. Sem Wait.
function S.get(src)
    if not src then return nil end
    return _cache[tonumber(src)]
end


-- Forca registro manual da sessao (uso em testes / fluxos especiais).
-- Producao: nunca chamar — confiar nos eventos.
function S.put(src, user)
    if not src or not user then return end
    _cache[tonumber(src)] = user
end


-- Conta sessoes ativas (uso em metrics / debug)
function S.count()
    local n = 0
    for _ in pairs(_cache) do n = n + 1 end
    return n
end
