-- client/movement.lua — aplicação de clipset de agachar no ped local
---@diagnostic disable: undefined-global

local E = VHubHSS.E

-- confirmar em dev: RequestAnimSet('move_ped_crouched') + HasAnimSetLoaded
local ANIM_SET = 'move_ped_crouched'
local BLEND    = 0.25

-- estado local — espelha padrão VHubHSS_SetInjuredWalk (guard de reentrância)
local _crouched     = false
local _crouched_ped = nil


-- ============================================================
-- CORE
-- ============================================================

local function load_anim_set(name, timeout_ms)
    RequestAnimSet(name)
    local deadline = GetGameTimer() + timeout_ms
    while not HasAnimSetLoaded(name) and GetGameTimer() < deadline do Citizen.Wait(25) end
    return HasAnimSetLoaded(name)
end

-- aplica ou remove clipset de agachar no ped local com guards de reentrância
local function setCrouch(active)
    local ped = PlayerPedId()

    if active then
        if _crouched and _crouched_ped == ped then return end
        if not load_anim_set(ANIM_SET, 1500) then return end
        SetPedMovementClipset(ped, ANIM_SET, BLEND)
        _crouched     = true
        _crouched_ped = ped
    else
        if not _crouched then return end
        ResetPedMovementClipset(ped, BLEND)
        RemoveAnimSet(ANIM_SET)
        _crouched     = false
        _crouched_ped = nil
    end
end


-- ============================================================
-- HANDLERS
-- ============================================================

RegisterNetEvent(E.SET_CROUCH)
AddEventHandler(E.SET_CROUCH, function(active)
    setCrouch(active)
end)

-- cancela crouch ao spawnar (ped resetado pelo HSS)
AddEventHandler(E.SPAWNED, function()
    _crouched     = false
    _crouched_ped = nil
end)

RegisterCommand('agachar', function()
    TriggerServerEvent(E.REQUEST_CROUCH)
end, false)
