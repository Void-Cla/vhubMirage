-- client/effects.lua — apresentação física local derivada do HSS
-- Budget: avaliação consolidada no HUD a 2 Hz; zero thread própria.

local Cfg = VHubHSS.Cfg.FX

local _shake = false
local _facial_ped = 0
local _blur = false
local _death_fx = false
local _sweat = false
local _sweat_ped = 0


-- ============================================================
-- EFEITOS DE BORDA
-- ============================================================

local function apply_adrenaline(ped, adrenaline)
    local active = adrenaline >= Cfg.shake_adr_threshold
    if active then
        local amplitude = math.min(0.38, 0.08 + adrenaline * 0.28)
        if _shake then
            SetGameplayCamShakeAmplitude(amplitude)
        else
            ShakeGameplayCam('HAND_SHAKE', amplitude)
            _shake = true
        end

        if _facial_ped ~= ped then
            if _facial_ped ~= 0 and DoesEntityExist(_facial_ped) then
                ClearFacialIdleAnimOverride(_facial_ped)
            end
            SetFacialIdleAnimOverride(ped, 'mood_stressed_1', 0)
            _facial_ped = ped
        end
    else
        if _shake then
            StopGameplayCamShaking(true)
            _shake = false
        end
        if _facial_ped ~= 0 then
            if DoesEntityExist(_facial_ped) then ClearFacialIdleAnimOverride(_facial_ped) end
            _facial_ped = 0
        end
    end
end

local function apply_blur(pain)
    local active = pain >= Cfg.blur_pain_threshold
    if active then
        SetTimecycleModifier('damage')
        SetTimecycleModifierStrength(math.min(0.75, pain))
        _blur = true
    elseif _blur then
        ClearTimecycleModifier()
        _blur = false
    end
end

local function apply_death_fx(active)
    if active and not _death_fx then
        AnimpostfxPlay('DeathFailOut', 0, true)
        _death_fx = true
    elseif not active and _death_fx then
        AnimpostfxStop('DeathFailOut')
        _death_fx = false
    end
end

local function apply_sweat(ped, stress, adrenaline)
    local active = math.max(stress, adrenaline) >= Cfg.sweat_stress_threshold
    if _sweat_ped ~= 0 and (_sweat_ped ~= ped or not active) then
        if DoesEntityExist(_sweat_ped) then SetPedSweat(_sweat_ped, 0.0) end
        _sweat_ped = 0
    end
    if active and (_sweat_ped ~= ped or not _sweat) then SetPedSweat(ped, 100.0) end
    _sweat = active
    if active then _sweat_ped = ped end
end


-- ============================================================
-- API LOCAL
-- ============================================================

-- Atualiza sintomas cosméticos sem alterar velocidade, stamina ou cadência de tiro.
function VHubHSS_UpdateEffects(state)
    if type(state) ~= 'table' then return end

    local ped = PlayerPedId()
    local adrenaline = tonumber(state.adrenaline) or 0.0
    local pain = tonumber(state.pain) or 0.0
    local blood = tonumber(state.blood) or 1.0
    local stress = tonumber(state.stress) or 0.0
    local trauma = tonumber(state.trauma) or 0.0
    local unconscious = state.consciousness == 'unconscious'

    apply_adrenaline(ped, adrenaline)
    apply_blur(pain)
    apply_death_fx(unconscious or blood <= Cfg.blood_fx_threshold)
    apply_sweat(ped, stress, adrenaline)

    local local_leg = VHubHSS_GetLocalLegTrauma and VHubHSS_GetLocalLegTrauma() or false
    VHubHSS_SetInjuredWalk(local_leg or trauma >= Cfg.limp_trauma_threshold)
end

-- Limpa integralmente efeitos cosméticos ao ocultar ou encerrar o HSS.
function VHubHSS_ClearEffects()
    if _shake then StopGameplayCamShaking(true) end
    if _facial_ped ~= 0 and DoesEntityExist(_facial_ped) then
        ClearFacialIdleAnimOverride(_facial_ped)
    end
    if _blur then ClearTimecycleModifier() end
    if _death_fx then AnimpostfxStop('DeathFailOut') end
    if _sweat_ped ~= 0 and DoesEntityExist(_sweat_ped) then SetPedSweat(_sweat_ped, 0.0) end
    _shake = false
    _facial_ped = 0
    _blur = false
    _death_fx = false
    _sweat = false
    _sweat_ped = 0
    VHubHSS_SetInjuredWalk(false)
end


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    VHubHSS_ClearEffects()
end)
