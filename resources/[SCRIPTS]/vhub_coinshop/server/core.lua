-- server/core.lua — núcleo do vhub_coinshop: sessões, permissão, rate-limit, caches, logger

VHubCoin = VHubCoin or {}
local Core = {}
VHubCoin.Core = Core


-- ============================================================
-- LOGGER — sem print() fora deste arquivo (R10)
-- ============================================================

-- emite log no console do servidor apenas em modo debug (produção silenciosa)
function Core.log(...)
    if not VHubCoin.cfg.debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(('[vhub_coinshop] %s'):format(table.concat(args, ' ')))
end

-- emite log de erro SEMPRE (não respeita debug)
function Core.logErr(...)
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(('^1[vhub_coinshop:ERRO] %s^0'):format(table.concat(args, ' ')))
end


-- ============================================================
-- USER — bridge para exports.vhub (compat: none, sem shim vRP)
-- ============================================================

-- retorna user {char_id, source, name, ...} ou nil
function Core.getUser(src)
    local ok, user = pcall(exports.vhub.getUser, src)
    if ok and user and user.char_id then return user end
    return nil
end

-- retorna char_id do src ou nil (validação server-side antes do domínio)
function Core.getCharId(src)
    local u = Core.getUser(src)
    return u and u.char_id or nil
end

-- retorna nome de exibição do jogador (fallback PlayerPedId name)
function Core.getPlayerName(src)
    local u = Core.getUser(src)
    if u and u.name then return u.name end
    return GetPlayerName(src) or ('Jogador ' .. tostring(src))
end


-- ============================================================
-- PERMISSÃO — owner uid=1 > ACE > grupos (§3.4)
-- ============================================================

-- retorna true se src tem a permissão do coinshop (owner bypass, ACE, ou grupo vhub_groups)
function Core.hasPerm(src, perm)
    if not src or src == 0 then return true end -- console

    -- owner (uid=1) bypass total
    local u = Core.getUser(src)
    if u and u.uid == 1 then return true end

    -- ACE FiveM nativa (server.cfg: add_ace vhub.coinshop.admin allow)
    local acePerm = 'vhub.' .. (perm or VHubCoin.cfg.adminPermission)
    if IsPlayerAceAllowed(src, acePerm) then return true end

    -- grupos vHub (exports.vhub_groups)
    local ok, result = pcall(exports.vhub_groups.hasPermission, src, perm or VHubCoin.cfg.adminPermission)
    if ok and result == true then return true end

    return false
end

-- atalho para checar admin do coinshop
function Core.isAdmin(src)
    return Core.hasPerm(src, VHubCoin.cfg.adminPermission)
end


-- ============================================================
-- RATE LIMIT — O(1) por (src, chave) — §4.6
-- ============================================================

local _last = {}

-- retorna true se a ação respeita o intervalo mínimo declarado em VHubCoin.cfg.rates
function Core.rate(src, key, ms)
    if not src or src == 0 then return true end -- console sem rate
    local now = GetGameTimer()
    local k = src .. ':' .. key
    if (now - (_last[k] or 0)) < (ms or 1000) then return false end
    _last[k] = now
    return true
end

-- limpa entradas de um jogador que saiu (chamado em playerDropped)
function Core.clearRatesFor(src)
    local p = tostring(src) .. ':'
    for k in pairs(_last) do
        if k:sub(1, #p) == p then _last[k] = nil end
    end
end


-- ============================================================
-- SESSÕES — por personagem (char_id); limpas em playerDropped
-- ============================================================

Core.sessions = {}   -- [src] = { char_id = N, identifier = 'license:...' }
Core._seenSpawn = {} -- replay-guard L-17: [src] = último user.spawns visto


-- ============================================================
-- NOTIFY — wrapper de exports.vhub:notify
-- ============================================================

-- envia notificação amigável ao jogador (info|success|error|warning)
function Core.notify(src, message, kind)
    if not src then return end
    local ok = pcall(exports.vhub.notify, src, message, kind or 'info')
    if not ok then Core.log('notify falhou para src=' .. tostring(src)) end
end
