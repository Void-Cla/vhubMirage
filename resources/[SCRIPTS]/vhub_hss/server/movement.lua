-- server/movement.lua — gate servidor para crouch (agachar) server-authoritative
---@diagnostic disable: undefined-global

local E      = VHubHSS.E
local RATE   = {}
local RATE_MS = 250


-- ============================================================
-- LIFECYCLE
-- ============================================================

AddEventHandler('playerDropped', function()
    RATE[tonumber(source)] = nil
end)


-- ============================================================
-- CROUCH GATE
-- ============================================================

local function onRequestCrouch(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end

    local now = GetGameTimer()
    if RATE[src] and (now - RATE[src]) < RATE_MS then return end
    RATE[src] = now

    -- gate: bloqueado se algemado ou inconsciente
    local blocks = exports['vhub_hss']:getAnimBlocks(src)
    if blocks.handcuffed or blocks.unconscious then return end

    -- toggle efêmero — sem persistência (não viola L-13)
    local crouching = not (Player(src).state.crouching == true)
    TriggerClientEvent(E.SET_CROUCH, src, crouching)
end

RegisterNetEvent(E.REQUEST_CROUCH)
AddEventHandler(E.REQUEST_CROUCH, onRequestCrouch)
