-- server/webhooks.lua — emite embeds para webhooks Discord (outbound HTTP; opcional por cfg)

VHubHub = VHubHub or {}
VHubCoin = VHubCoin or {}
local Webhooks = {}
VHubCoin.Webhooks = Webhooks

-- mapa categoria → convar de fallback (lida em runtime para não versionar URL)
local _convar = {
    purchases = 'coinshop_webhook_purchases',
    redeems   = 'coinshop_webhook_redeems',
    admin     = 'coinshop_webhook_admin',
}

-- resolve URL: config estática > convar > ausente
local function resolveUrl(category)
    local url = VHubCoin.cfg.webhooks[category]
    if VHubCoin.isNonEmptyStr(url) then return url end
    local cv = _convar[category]
    if cv then
        local v = GetConvar(cv, '')
        if v ~= '' then return v end
    end
    return nil
end


-- envia um embed para o webhook da categoria (purchases|redeems|admin); no-op se URL vazia
function Webhooks.fire(category, title, description, fields)
    local url = resolveUrl(category)
    if not url then return end

    local color = VHubCoin.cfg.webhookColors[category] or 16777215
    local embed = {
        title       = title,
        description = description,
        color       = color,
        fields      = fields or {},
        footer      = { text = 'vHub Coinshop • ' .. os.date('%Y-%m-%d %H:%M:%S') },
    }

    local payload = json.encode({
        username   = VHubCoin.cfg.webhookName,
        avatar_url = VHubCoin.cfg.webhookAvatar,
        embeds     = { embed },
    })

    -- pcall: fronteira externa, falha não derruba quem chamou (R7)
    pcall(PerformHttpRequest, url, function() end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end
