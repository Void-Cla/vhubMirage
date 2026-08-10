-- server/broadcast.lua — handler do /me (R1, L-01, sanitização server-side)
---@diagnostic disable: undefined-global

local E   = VHubRP.E
local Cfg = VHubRP.Cfg

local COOLDOWN = {}


-- ============================================================
-- UTILS
-- ============================================================

-- remove códigos de cor GTA (^0-9), tokens (~r~/~h~) e chars HTML (<>&)
local function sanitize(s)
    return (s:gsub('%^%d', ''):gsub('~%w+~', ''):gsub('[<>&]', ''))
end


-- ============================================================
-- LIFECYCLE
-- ============================================================

AddEventHandler('playerDropped', function()
    COOLDOWN[source] = nil
end)


-- ============================================================
-- COMMAND /me
-- ============================================================

-- broadcast de ação RP em raio (30 m), validado e sanitizado server-side
RegisterCommand('me', function(src, args)
    if not src or src <= 0 then return end

    local now = GetGameTimer()
    if COOLDOWN[src] and (now - COOLDOWN[src]) < Cfg.ME_COOLDOWN_MS then return end
    COOLDOWN[src] = now

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local text = table.concat(args, ' '):sub(1, Cfg.ME_MAX_LEN):gsub('[\r\n]', '')
    text = sanitize(text)
    if #text == 0 then return end

    local ok, name = pcall(function() return exports['vhub_identity']:getFullName(src) end)
    if not ok or not name or name == '' then name = GetPlayerName(src) or 'Desconhecido' end
    name = sanitize(name)

    local origin = GetEntityCoords(ped)
    local rSq    = Cfg.ME_RADIUS * Cfg.ME_RADIUS

    -- iteração server-side; TriggerClientEvent targeted (nunca -1) — R5
    for _, pid in ipairs(GetPlayers()) do
        local pidN = tonumber(pid)
        local tped = GetPlayerPed(pidN)
        if tped and tped ~= 0 then
            local tc = GetEntityCoords(tped)
            local dx = origin.x - tc.x
            local dy = origin.y - tc.y
            local dz = origin.z - tc.z
            if (dx * dx + dy * dy + dz * dz) <= rSq then
                TriggerClientEvent(E.ME_CHAT, pidN, name, text)
            end
        end
    end
end, false)
