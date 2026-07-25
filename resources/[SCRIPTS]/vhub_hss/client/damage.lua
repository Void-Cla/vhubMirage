-- client/damage.lua — evidência cosmética de dano localizado no ped local
-- Budget: event-driven; zero emissão de verdade ao servidor e zero polling.

local _running = true
local _leg_trauma_until = 0

local LEG_BONES = {
    [14201] = true,
    [36864] = true,
    [51826] = true,
    [52301] = true,
    [58271] = true,
    [63931] = true,
}

AddEventHandler(VHubHSS.E.ENTITY_DAMAGED, function(victim, _culprit, _weapon, base_damage)
    if not _running or GlobalState.vh_hss_active ~= true then return end
    if victim ~= PlayerPedId() or (tonumber(base_damage) or 0) <= 0 then return end

    local found, bone = GetPedLastDamageBone(victim)
    if found and LEG_BONES[bone] then
        local duration = math.max(15000, math.min(90000, (tonumber(base_damage) or 1) * 1800))
        _leg_trauma_until = math.max(_leg_trauma_until, GetGameTimer() + duration)
    end
    ClearPedLastDamageBone(victim)

end)

-- Retorna evidência local temporária usada apenas na animação de mancar.
function VHubHSS_GetLocalLegTrauma()
    return GetGameTimer() < _leg_trauma_until
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    _running = false
    _leg_trauma_until = 0
end)
