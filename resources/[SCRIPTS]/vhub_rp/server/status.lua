-- server/status.lua — handler do /status (jogadores online)
---@diagnostic disable: undefined-global

local E   = VHubRP.E
local Cfg = VHubRP.Cfg

local STATUS_CD = {}


-- ============================================================
-- LIFECYCLE
-- ============================================================

AddEventHandler('playerDropped', function()
    STATUS_CD[source] = nil
end)


-- ============================================================
-- COMMAND /status
-- ============================================================

-- informa o total de jogadores online com cooldown individual
RegisterCommand('status', function(src, _)
    if not src or src <= 0 then return end

    local now = GetGameTimer()
    if STATUS_CD[src] and (now - STATUS_CD[src]) < Cfg.STATUS_CD_MS then return end
    STATUS_CD[src] = now

    TriggerClientEvent(E.STATUS_REPLY, src, #GetPlayers())
end, false)
