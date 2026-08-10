-- client/afk.lua — detecção de input; heartbeat ao servidor (budget: ativo 5 Hz / parado 1 Hz)
---@diagnostic disable: undefined-global

local E = VHubHSS.E

local lastHeartbeat = 0
local BEAT_INTERVAL = 5000

local INPUT_GROUPS   = { 0, 1, 2 }
local INPUT_CONTROLS = { 24, 25, 26, 27, 1, 2, 71, 72, 23 }


-- ============================================================
-- LOOP DE DETECÇÃO
-- ============================================================

-- budget: ativo 5 Hz (200 ms), parado 1 Hz (1000 ms) — sleep adaptativo (L-18)
Citizen.CreateThread(function()
    while true do
        local hasInput = false

        for _, grp in ipairs(INPUT_GROUPS) do
            for _, ctrl in ipairs(INPUT_CONTROLS) do
                if IsControlPressed(grp, ctrl) then
                    hasInput = true
                    break
                end
            end
            if hasInput then break end
        end

        if hasInput then
            local now = GetGameTimer()
            if (now - lastHeartbeat) >= BEAT_INTERVAL then
                lastHeartbeat = now
                TriggerServerEvent(E.AFK_HEARTBEAT)
            end
        end

        Citizen.Wait(hasInput and 200 or 1000)
    end
end)
