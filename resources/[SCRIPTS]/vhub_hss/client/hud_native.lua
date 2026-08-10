---@diagnostic disable: undefined-global
-- client/hud_native.lua — owner único do HUD GTA/minimapa; emite rua/hora/voz à NUI

local _active  = true   -- ativo por padrão; STATE_HIDE desativa (evita regressão em restart)
local _running = true
local _minimap = nil
local _hud_visible = nil
local _radar_visible = nil

local HIDE_COMPONENTS = { 7, 9 } -- AREA_NAME, STREET_NAME
local SUPPRESSORS = { hud = {}, radar = {} }
local SUPPRESSION_PERMISSIONS = {
    vhub_login = { hud = true },
    vhub_lspdtool = { radar = true },
}

local _voice_mode  = 2
local _voice_label = 'Normal'


-- ============================================================
-- OWNERSHIP DO HUD NATIVO
-- ============================================================

local function apply_native_visibility()
    local hud_visible = _active and next(SUPPRESSORS.hud) == nil
    local radar_visible = hud_visible and next(SUPPRESSORS.radar) == nil

    if hud_visible ~= _hud_visible then
        DisplayHud(hud_visible)
        _hud_visible = hud_visible
    end
    if radar_visible ~= _radar_visible then
        DisplayRadar(radar_visible)
        _radar_visible = radar_visible
    end
end

-- Recursos confiáveis declaram intenção; somente o HSS executa natives de HUD/radar.
exports('setNativeHudSuppressed', function(scope, suppressed)
    local invoker = GetInvokingResource()
    local permissions = invoker and SUPPRESSION_PERMISSIONS[invoker] or nil
    if type(scope) ~= 'string' or type(suppressed) ~= 'boolean'
        or not SUPPRESSORS[scope] or not permissions or permissions[scope] ~= true then
        return false
    end

    SUPPRESSORS[scope][invoker] = suppressed and true or nil
    apply_native_visibility()
    return true
end)

AddEventHandler('onClientResourceStop', function(resource)
    local changed = SUPPRESSORS.hud[resource] or SUPPRESSORS.radar[resource]
    SUPPRESSORS.hud[resource] = nil
    SUPPRESSORS.radar[resource] = nil
    if changed then apply_native_visibility() end
end)


-- ============================================================
-- GATE DE ATIVAÇÃO (espelha STATE_INIT / STATE_HIDE)
-- ============================================================

RegisterNetEvent(VHubHSS.E.STATE_INIT, function()
    _active = true
    apply_native_visibility()
end)

RegisterNetEvent(VHubHSS.E.STATE_HIDE, function()
    _active = false
    apply_native_visibility()
    SendNUIMessage({ type = 'hud:street', visible = false, street = '', zone = '' })
    SendNUIMessage({ type = 'hud:voice_talking', talking = false })
end)


-- ============================================================
-- OCULTAÇÃO POR FRAME
-- Budget: ativo Wait(0), suprimido/inativo 1000 ms; alvo p95 <= 0,10 ms.
-- ============================================================

Citizen.CreateThread(function()
    apply_native_visibility()

    _minimap = RequestScaleformMovie('minimap')
    while _running and not HasScaleformMovieLoaded(_minimap) do Citizen.Wait(50) end
    if not _running then return end

    -- Força a inicialização completa do Scaleform antes de alterar o tipo das barras.
    SetRadarBigmapEnabled(true, false)
    Citizen.Wait(0)
    SetRadarBigmapEnabled(false, false)

    while _running do
        if _active and next(SUPPRESSORS.hud) == nil then
            BeginScaleformMovieMethod(_minimap, 'SETUP_HEALTH_ARMOUR')
            ScaleformMovieMethodAddParamInt(3) -- tipo GOLF: sem barras nativas de vida/colete
            EndScaleformMovieMethod()
            for _, component in ipairs(HIDE_COMPONENTS) do
                HideHudComponentThisFrame(component)
            end
            Citizen.Wait(0)
        else
            Citizen.Wait(1000)
        end
    end
end)


-- ============================================================
-- VOICE PMA — listener local do evento de mudança de modo
-- ============================================================

AddEventHandler('vhub_voicePMA:modeChanged', function(mode, label, _distance)
    _voice_mode  = tonumber(mode) or 2
    _voice_label = type(label) == 'string' and label or 'Normal'
    if _active then
        SendNUIMessage({ type = 'hud:voice', mode = _voice_mode, label = _voice_label })
    end
end)


-- ============================================================
-- THREAD 2 Hz — rua, hora, talking
-- ============================================================

Citizen.CreateThread(function()
    local player_id = PlayerId()

    local _prev_street  = nil
    local _prev_zone    = nil
    local _prev_in_veh  = nil
    local _prev_time    = nil
    local _prev_talking = nil

    while _running do
        Citizen.Wait(500)
        if not _active then goto cont end

        local ped = PlayerPedId()
        if not ped or ped == 0 or not DoesEntityExist(ped) then goto cont end

        -- rua + zona (só em veículo)
        local in_veh = IsPedInAnyVehicle(ped, false)
        local street, zone = '', ''
        if in_veh then
            local c = GetEntityCoords(ped)
            local hash = GetStreetNameAtCoord(c.x, c.y, c.z)
            street = GetStreetNameFromHashKey(hash) or ''
            zone   = GetNameOfZone(c.x, c.y, c.z) or ''
        end
        if street ~= _prev_street or zone ~= _prev_zone or in_veh ~= _prev_in_veh then
            _prev_street = street
            _prev_zone   = zone
            _prev_in_veh = in_veh
            SendNUIMessage({
                type    = 'hud:street',
                visible = in_veh and street ~= '',
                street  = street,
                zone    = zone,
            })
        end

        -- horário do mundo (NetworkOverrideClockTime aplicado pelo vhub_admin)
        local t = string.format('%02d:%02d', GetClockHours(), GetClockMinutes())
        if t ~= _prev_time then
            _prev_time = t
            SendNUIMessage({ type = 'hud:time', time = t })
        end

        -- estado de fala (pulsação no ícone de voz)
        local raw     = NetworkIsPlayerTalking(player_id)
        local talking = raw == true or raw == 1
        if talking ~= _prev_talking then
            _prev_talking = talking
            SendNUIMessage({ type = 'hud:voice_talking', talking = talking })
        end

        ::cont::
    end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    _running = false
    _active  = false
    if _minimap then SetScaleformMovieAsNoLongerNeeded(_minimap) end
    DisplayHud(true)
    DisplayRadar(true)
end)
