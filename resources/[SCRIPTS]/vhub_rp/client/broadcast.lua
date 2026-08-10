-- client/broadcast.lua — exibição de /me e /status no chat
---@diagnostic disable: undefined-global

local E = VHubRP.E


-- ============================================================
-- UTILS
-- ============================================================

-- defesa em profundidade: sanitizar antes de exibir no CEF
local function sanitize(s)
    return tostring(s):gsub('%^%d', ''):gsub('~%w+~', ''):gsub('[<>&]', '')
end


-- ============================================================
-- HANDLERS
-- ============================================================

-- exibe ação RP no chat com formatação âmbar
RegisterNetEvent(E.ME_CHAT)
AddEventHandler(E.ME_CHAT, function(name, text)
    TriggerEvent('chat:addMessage', {
        color     = { 255, 200, 100 },
        multiline = true,
        args      = { '* ' .. sanitize(name), sanitize(text) },
    })
end)

-- exibe contagem de jogadores no chat
RegisterNetEvent(E.STATUS_REPLY)
AddEventHandler(E.STATUS_REPLY, function(count)
    TriggerEvent('chat:addMessage', {
        color = { 200, 200, 255 },
        args  = { '[Status]', ('Jogadores online: %d'):format(count) },
    })
end)
