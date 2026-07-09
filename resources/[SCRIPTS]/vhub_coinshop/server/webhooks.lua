-- server/webhooks.lua — emite embeds para webhooks Discord (outbound HTTP; opcional por cfg)

VHubHub = VHubHub or {}
VHubCoin = VHubCoin or {}
local Webhooks = {}
VHubCoin.Webhooks = Webhooks


-- envia um embed para o webhook da categoria (purchases|redeems|admin); no-op se URL vazia
function Webhooks.fire(category, title, description, fields)
    local url = VHubCoin.cfg.webhooks[category]
    if not VHubCoin.isNonEmptyStr(url) then return end

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
