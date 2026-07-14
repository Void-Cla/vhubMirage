-- server/core.lua — núcleo do vhub_df: sessão, permissão, rate-limit, logger

VHubDF = VHubDF or {}
local Core = {}
VHubDF.Core = Core


-- ============================================================
-- LOGGER — sem print() fora deste arquivo (R10)
-- ============================================================

-- log de depuração (respeitado somente quando cfg.debug=true)
function Core.log(...)
    if not VHubDF.cfg.debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(('[vhub_df] %s'):format(table.concat(args, ' ')))
end

-- erro sempre visível no console
function Core.logErr(...)
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(('^1[vhub_df:ERRO] %s^0'):format(table.concat(args, ' ')))
end


-- ============================================================
-- USER — bridge para exports.vhub (compat: none)
-- ============================================================

-- retorna user {char_id, source, name, id, ...} ou nil
-- colon-call obrigatório: dot-call descarta 1º arg (fix decisão #58)
function Core.getUser(src)
    local ok, u = pcall(function() return exports.vhub:getUser(src) end)
    if ok and u and u.char_id then return u end
    return nil
end

-- retorna char_id ou nil
function Core.getCharId(src)
    local u = Core.getUser(src)
    return u and u.char_id or nil
end

-- nome de exibição do jogador (fallback nativo)
function Core.getPlayerName(src)
    local u = Core.getUser(src)
    if u and u.name then return u.name end
    return GetPlayerName(src) or ('Jogador ' .. tostring(src))
end


-- ============================================================
-- PERMISSÃO — owner uid=1 > ACE > grupos (§3.4)
-- ============================================================

-- verifica permissão: owner bypass, ACE nativa, ou vhub_groups
function Core.hasPerm(src, perm)
    if not src or src == 0 then return true end
    local u = Core.getUser(src)
    if u and u.id == 1 then return true end
    if IsPlayerAceAllowed(src, 'vhub.' .. (perm or 'df.admin')) then return true end
    local ok, r = pcall(function() return exports.vhub_groups:hasPermission(src, perm or 'df.admin') end)
    return ok and r == true
end


-- ============================================================
-- RATE LIMIT — O(1) por (src, chave) — L-18
-- ============================================================

local _last = {}

-- retorna true se a ação respeita o intervalo mínimo (ms)
function Core.rate(src, key, ms)
    if not src or src == 0 then return true end
    local now = GetGameTimer()
    local k   = tostring(src) .. ':' .. key
    if (now - (_last[k] or 0)) < (ms or 1000) then return false end
    _last[k] = now
    return true
end

-- limpa entradas do jogador que saiu (sem leak de _last)
function Core.clearRates(src)
    local p = tostring(src) .. ':'
    for k in pairs(_last) do
        if k:sub(1, #p) == p then _last[k] = nil end
    end
end


-- ============================================================
-- NOTIFICAÇÃO — canal canônico vHub:notify (decisão #31)
-- ============================================================

local KIND = { success = 'sucesso', error = 'erro', warning = 'aviso', info = 'info' }

-- envia toast vHub:notify para o jogador (server-side)
function Core.notify(src, message, kind)
    if not src or src == 0 then return end
    TriggerClientEvent('vHub:notify', src, KIND[kind] or 'info', tostring(message))
end


-- ============================================================
-- DISCORD AUDIT — fire-and-forget via PerformHttpRequest
-- ============================================================

-- envia embed de auditoria para o webhook Discord configurado (falha silenciosa)
function Core.discordAudit(title, description, color, fields)
    local url = GetConvar('df_discord_webhook', '')
    if url == '' then return end
    local cfg = VHubDF.cfg.discord
    local embed = {
        title       = title,
        description = description,
        color       = color or cfg.colorOk,
        fields      = fields or {},
        timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    local body = json.encode({
        username   = cfg.username,
        avatar_url = cfg.avatarUrl,
        embeds     = { embed },
    })
    PerformHttpRequest(url, function(s)
        if s < 200 or s >= 300 then
            Core.logErr('discord audit HTTP ' .. tostring(s))
        end
    end, 'POST', body, { ['Content-Type'] = 'application/json' })
end
