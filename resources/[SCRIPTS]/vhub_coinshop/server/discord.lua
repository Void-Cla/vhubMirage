-- server/discord.lua — busca opcional de avatar Discord (cache VRAM, pcall-wrapped na fronteira HTTP)

VHubCoin = VHubCoin or {}
local Discord = {}
VHubCoin.Discord = Discord


-- cache por discordId: { username, avatar, discordId }
local _cache = {}


-- retorna dados do Discord do src (cache-first; busca HTTP só se token configurado)
function Discord.fetch(src, cb)
    if not src then return cb(nil) end

    local discordId
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:match('^discord:') then
            discordId = id:gsub('^discord:', '')
            break
        end
    end
    if not discordId then return cb(nil) end

    -- cache hit
    if _cache[discordId] then return cb(_cache[discordId]) end

    local token = VHubCoin.cfg.discordBotToken
    if not VHubCoin.isNonEmptyStr(token) then return cb(nil) end

    -- boundary HTTP externa — pcall (R7: falha isolada, nunca derruba o tick)
    PerformHttpRequest('https://discord.com/api/v10/users/' .. discordId, function(status, body)
        if status ~= 200 or not body then return cb(nil) end
        local data = json.decode(body)
        if not data then return cb(nil) end

        local avatarUrl
        if data.avatar then
            local ext = data.avatar:sub(1, 2) == 'a_' and 'gif' or 'png'
            avatarUrl = ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=128'):format(discordId, data.avatar, ext)
        else
            local index = (tonumber(data.discriminator) or 0) % 5
            avatarUrl = ('https://cdn.discordapp.com/embed/avatars/%d.png'):format(index)
        end

        local entry = {
            username  = data.global_name or data.username or 'Desconhecido',
            avatar    = avatarUrl,
            discordId = discordId,
        }
        _cache[discordId] = entry
        cb(entry)
    end, 'GET', '', { Authorization = 'Bot ' .. token })
end


-- retorna o cache (sincrónico) se já buscado; nil caso contrário
function Discord.cached(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:match('^discord:') then
            local did = id:gsub('^discord:', '')
            return _cache[did]
        end
    end
    return nil
end


-- limpa cache do jogador que saiu (evita leak)
function Discord.onPlayerDropped(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:match('^discord:') then
            local did = id:gsub('^discord:', '')
            _cache[did] = nil
            break
        end
    end
end
