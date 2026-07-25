-- client/native_bridge.lua — HAL de animações do HSS

local INJURED_CLIPSET = 'move_m@injured'
local _injured = false
local _injured_ped = 0
local _animation_token = 0
local _current_animation = nil


-- ============================================================
-- ANIMAÇÃO DE LESÃO
-- ============================================================

local function load_anim_set(name, timeout_ms)
    RequestAnimSet(name)
    local deadline = GetGameTimer() + timeout_ms
    while not HasAnimSetLoaded(name) and GetGameTimer() < deadline do Citizen.Wait(25) end
    return HasAnimSetLoaded(name)
end

-- Ativa ou limpa o clipset de lesão com timeout limitado.
function VHubHSS_SetInjuredWalk(active)
    local ped = PlayerPedId()
    active = active == true
    if active and _injured and _injured_ped == ped then return end
    if not active and not _injured then return end

    if active then
        if not load_anim_set(INJURED_CLIPSET, 1500) then return end
        if _injured_ped ~= 0 and _injured_ped ~= ped and DoesEntityExist(_injured_ped) then
            ResetPedMovementClipset(_injured_ped, 0.35)
        end
        SetPedMovementClipset(ped, INJURED_CLIPSET, 0.35)
        _injured = true
        _injured_ped = ped
    else
        if _injured_ped ~= 0 and DoesEntityExist(_injured_ped) then
            ResetPedMovementClipset(_injured_ped, 0.35)
        end
        RemoveAnimSet(INJURED_CLIPSET)
        _injured = false
        _injured_ped = 0
    end
end


-- ============================================================
-- ANIMAÇÃO DE ITEM
-- ============================================================

local function play_item_animation(kind)
    local spec = VHubHSS.Cfg.ITEM_ANIMATIONS[kind]
    if not spec then return end

    _animation_token = _animation_token + 1
    local token = _animation_token
    if _current_animation then
        StopAnimTask(
            _current_animation.ped,
            _current_animation.dict,
            _current_animation.name,
            1.0
        )
        RemoveAnimDict(_current_animation.dict)
        _current_animation = nil
    end
    RequestAnimDict(spec.dict)
    local deadline = GetGameTimer() + 1500
    while token == _animation_token
        and not HasAnimDictLoaded(spec.dict)
        and GetGameTimer() < deadline do
        Citizen.Wait(25)
    end
    if token ~= _animation_token or not HasAnimDictLoaded(spec.dict) then return end

    local ped = PlayerPedId()
    _current_animation = { ped = ped, dict = spec.dict, name = spec.name }
    TaskPlayAnim(ped, spec.dict, spec.name, 4.0, -4.0, spec.duration_ms, 49, 0.0, false, false, false)
    SetTimeout(spec.duration_ms, function()
        if token ~= _animation_token then return end
        StopAnimTask(ped, spec.dict, spec.name, 1.0)
        RemoveAnimDict(spec.dict)
        _current_animation = nil
    end)
end

RegisterNetEvent(VHubHSS.E.ITEM_EFFECT, function(payload)
    if type(payload) ~= 'table' or type(payload.item_id) ~= 'string' then return end
    local item = VHubHSS.Cfg.ITEMS[payload.item_id]
    if item and item.animation then play_item_animation(item.animation) end
end)


-- ============================================================
-- PED / SPAWN
-- ============================================================

local _ped_running = true
local _hold = false
local _first_spawn = false
local _visual_scene = false

local function current_ped()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

function VHubHSS_MovePed(ped, position)
    if type(position) ~= 'table' then return false end
    local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z)
    if not x or not y or not z then return false end
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    SetEntityHeading(ped, tonumber(position.heading) or tonumber(position.h) or 0.0)
    RequestCollisionAtCoord(x, y, z)
    local deadline = GetGameTimer() + 3000
    while _ped_running
        and not HasCollisionLoadedAroundEntity(ped)
        and GetGameTimer() < deadline do
        Citizen.Wait(100)
    end
    return true
end

local function allowed_model(name)
    return type(name) == 'string' and VHubHSS.Cfg.PED.allowed_models[name] == true
end

local function valid_model_name(name)
    return type(name) == 'string' and #name >= 1 and #name <= 64
        and name:match('^[a-zA-Z0-9_]+$') ~= nil
end

function VHubHSS_ApplyCustomization(ped, custom)
    custom = VHubHSS.Appearance.sanitize(custom)
    local is_mp = allowed_model(custom.model)
    if is_mp then
        local heritage = type(custom.heritage) == 'table' and custom.heritage or {}
        SetPedHeadBlendData(
            ped,
            heritage.shape_first or 0,
            heritage.shape_second or 0,
            0,
            heritage.skin_first or 0,
            heritage.skin_second or 0,
            0,
            heritage.shape_mix or 0.5,
            heritage.skin_mix or 0.5,
            0.0,
            false
        )
        for index = 0, 19 do
            SetPedFaceFeature(ped, index, custom['face:' .. index] or 0.0)
        end
        SetPedEyeColor(ped, custom.eye_color or 0)
    end

    if is_mp then
        for index = 0, 12 do
            local tuple = custom['overlay:' .. index]
            if tuple then
                local colour_type = (index == 1 or index == 2 or index == 10) and 1
                    or (index == 5 or index == 8) and 2 or 0
                SetPedHeadOverlay(ped, index, tuple[1], tuple[4])
                SetPedHeadOverlayColor(ped, index, colour_type, tuple[2], tuple[3])
            end
        end

        local hair = custom['drawable:2']
        if hair then SetPedComponentVariation(ped, 2, hair[1], hair[2], hair[3]) end
        local tint = custom.hair_color or { 0, 0 }
        SetPedHairTint(ped, tint[1], tint[2])
    end

    for index = 0, 11 do
        if index ~= 2 then
            local tuple = custom['drawable:' .. index]
            if tuple then SetPedComponentVariation(ped, index, tuple[1], tuple[2], tuple[3]) end
        end
    end

    for index = 0, 7 do
        local tuple = custom['prop:' .. index]
        if tuple then
            if tuple[1] < 0 then
                ClearPedProp(ped, index)
            else
                SetPedPropIndex(ped, index, tuple[1], tuple[2], true)
            end
        end
    end

    ClearPedDecorationsLeaveScars(ped)
    for _, tattoo in ipairs(custom.tattoos or {}) do
        pcall(AddPedDecorationFromHashes, ped, GetHashKey(tattoo.dlc), GetHashKey(tattoo.hash))
    end
    return true
end

-- Aplica somente as chaves alteradas durante o preview local.
function VHubHSS_ApplyCustomizationPatch(ped, patch, merged)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if type(patch) ~= 'table' or type(merged) ~= 'table' then return false end
    local is_mp = allowed_model(merged.model)

    if is_mp and patch.heritage ~= nil then
        local heritage = merged.heritage
        SetPedHeadBlendData(
            ped,
            heritage.shape_first, heritage.shape_second, 0,
            heritage.skin_first, heritage.skin_second, 0,
            heritage.shape_mix, heritage.skin_mix, 0.0, false
        )
    end
    if is_mp then
        for index = 0, 19 do
            local key = 'face:' .. index
            if patch[key] ~= nil then SetPedFaceFeature(ped, index, merged[key]) end
        end
        if patch.eye_color ~= nil then SetPedEyeColor(ped, merged.eye_color) end
        for index = 0, 12 do
            local key = 'overlay:' .. index
            local tuple = patch[key] ~= nil and merged[key] or nil
            if tuple then
                local colour_type = (index == 1 or index == 2 or index == 10) and 1
                    or (index == 5 or index == 8) and 2 or 0
                SetPedHeadOverlay(ped, index, tuple[1], tuple[4])
                SetPedHeadOverlayColor(ped, index, colour_type, tuple[2], tuple[3])
            end
        end
        if patch.hair_color ~= nil then
            SetPedHairTint(ped, merged.hair_color[1], merged.hair_color[2])
        end
    end

    for index = 0, 11 do
        local key = 'drawable:' .. index
        local tuple = patch[key] ~= nil and merged[key] or nil
        if tuple then SetPedComponentVariation(ped, index, tuple[1], tuple[2], tuple[3]) end
    end
    for index = 0, 7 do
        local key = 'prop:' .. index
        local tuple = patch[key] ~= nil and merged[key] or nil
        if tuple then
            if tuple[1] < 0 then ClearPedProp(ped, index)
            else SetPedPropIndex(ped, index, tuple[1], tuple[2], true) end
        end
    end
    if patch.tattoos ~= nil then
        ClearPedDecorationsLeaveScars(ped)
        for _, tattoo in ipairs(merged.tattoos or {}) do
            pcall(AddPedDecorationFromHashes, ped, GetHashKey(tattoo.dlc), GetHashKey(tattoo.hash))
        end
    end
    return true
end

local function load_ped_model(name, allow_dynamic)
    if not allowed_model(name) and not (allow_dynamic and valid_model_name(name)) then return false end
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) or not IsModelAPed(hash) then return false end
    if GetEntityModel(PlayerPedId()) == hash then return true end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while _ped_running and not HasModelLoaded(hash) and GetGameTimer() < deadline do Citizen.Wait(50) end
    if not HasModelLoaded(hash) then return false end
    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)
    Citizen.Wait(0)
    return true
end

function VHubHSS_ApplyModelAndCustomization(custom)
    custom = type(custom) == 'table' and custom or { model = VHubHSS.Cfg.PED.default_model }
    local model = allowed_model(custom.model) and custom.model or VHubHSS.Cfg.PED.default_model
    local previous_ped = current_ped()
    if not previous_ped then return false end
    local position = GetEntityCoords(previous_ped)
    local heading = GetEntityHeading(previous_ped)
    local health = GetEntityHealth(previous_ped)
    local armour = GetPedArmour(previous_ped)
    local visible = IsEntityVisible(previous_ped)
    local invincible = GetPlayerInvincible(PlayerId())
    local frozen = IsEntityPositionFrozen(previous_ped)
    if not load_ped_model(model) then return false end
    local ped = current_ped()
    if not ped then return false end
    SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, false, false, false)
    SetEntityHeading(ped, heading)
    SetEntityHealth(ped, health)
    SetPedArmour(ped, armour)
    SetEntityVisible(ped, visible, false)
    SetEntityInvincible(ped, invincible)
    FreezeEntityPosition(ped, frozen)
    return VHubHSS_ApplyCustomization(ped, custom) == true
end

local function finish_spawn(first_spawn)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    DoScreenFadeIn(500)
    _hold = false
    TriggerEvent(VHubHSS.E.SPAWNED, first_spawn == true)
    if first_spawn == true then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('Bem-vindo ao servidor!')
        EndTextCommandThefeedPostTicker(false, true)
    end
end

local function apply_weapons(weapons, clear_before)
    local ped = PlayerPedId()
    if clear_before then RemoveAllPedWeapons(ped, true) end
    for name, spec in pairs(type(weapons) == 'table' and weapons or {}) do
        if type(name) == 'string' and name:match('^WEAPON_[A-Z0-9_]+$') then
            GiveWeaponToPed(
                ped,
                GetHashKey(name),
                math.max(0, math.min(9999, tonumber(type(spec) == 'table' and spec.ammo) or 0)),
                false,
                false
            )
        end
    end
end

RegisterNetEvent(VHubHSS.E.PED_APPLY, function(payload)
    if type(payload) ~= 'table' then return end
    Citizen.CreateThread(function()
        local deadline = GetGameTimer() + 10000
        while _ped_running and not NetworkIsPlayerActive(PlayerId()) and GetGameTimer() < deadline do
            Citizen.Wait(100)
        end
        if not _ped_running or not NetworkIsPlayerActive(PlayerId()) then return end

        _hold = payload.hold == true
        _first_spawn = payload.first_spawn == true
        DoScreenFadeOut(200)
        Citizen.Wait(300)
        VHubHSS_ApplyModelAndCustomization(payload.customization)
        local ped = PlayerPedId()
        local position = type(payload.position) == 'table' and payload.position or {}
        local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z)
        local heading = tonumber(position.heading) or tonumber(position.h) or 0.0
        if x and y and z then
            RequestCollisionAtCoord(x, y, z)
            NetworkResurrectLocalPlayer(x, y, z, heading, true, true, false)
            ped = PlayerPedId()
        end
        VHubHSS_MovePed(ped, payload.position)
        ClearPedTasksImmediately(ped)
        RemoveAllPedWeapons(ped, true)
        ClearPlayerWantedLevel(PlayerId())
        SetEntityHealth(ped, math.floor(math.max(0, math.min(200, tonumber(payload.health) or 200))))
        SetPedArmour(ped, math.floor(math.max(0, math.min(100, tonumber(payload.armour) or 0))))
        if ShutdownLoadingScreen then ShutdownLoadingScreen() end
        if ShutdownLoadingScreenNui then ShutdownLoadingScreenNui() end

        if _hold then
            SetEntityVisible(ped, false, false)
            SetEntityInvincible(ped, true)
            -- Devolve o fade mesmo em hold: o ped está invisível (ocultado por SetEntityVisible),
            -- não pela tela escura. O PED_RELEASE faz SetEntityVisible(true) + FadeIn ao spawnar.
            -- Sem este FadeIn, o DoScreenFadeOut(200) acima fica sem par quando o PED_RELEASE
            -- chega antes do PED_APPLY terminar (race window de até 3s de colisão).
            DoScreenFadeIn(300)
        else
            finish_spawn(_first_spawn)
        end
    end)
end)

RegisterNetEvent(VHubHSS.E.PED_RELEASE, function(position, first_spawn)
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        if type(position) == 'table' then VHubHSS_MovePed(ped, position) end
        finish_spawn(first_spawn == true or _first_spawn)
    end)
end)

RegisterNetEvent(VHubHSS.E.PED_GIVE_WEAPONS, function(weapons, clear_before)
    apply_weapons(weapons, clear_before == true)
end)

RegisterNetEvent(VHubHSS.E.PED_SET_ARMOUR, function(amount)
    SetPedArmour(PlayerPedId(), math.floor(math.max(0, math.min(100, tonumber(amount) or 0))))
end)

RegisterNetEvent(VHubHSS.E.PED_SET_HEALTH, function(amount)
    local ped = PlayerPedId()
    local value = math.floor(math.max(0, math.min(200, tonumber(amount) or 200)))
    SetEntityHealth(ped, value)
    if value >= 200 then
        ClearPedBloodDamage(ped)
        ResetPedVisibleDamage(ped)
    end
end)

RegisterNetEvent(VHubHSS.E.PED_SET_MODEL, function(model)
    Citizen.CreateThread(function()
        local previous = current_ped()
        if not previous then return end
        local health = GetEntityHealth(previous)
        local armour = GetPedArmour(previous)
        if not load_ped_model(model, true) then return end
        local ped = current_ped()
        if not ped then return end
        SetEntityHealth(ped, health)
        SetPedArmour(ped, armour)
    end)
end)

RegisterNetEvent(VHubHSS.E.PED_REVIVE, function()
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
        SetEntityHealth(ped, VHubHSS.Cfg.PED.default_health)
        SetPedArmour(ped, 100)
        ClearPedBloodDamage(ped)
        ResetPedVisibleDamage(ped)
    end)
end)

RegisterNetEvent(VHubHSS.E.PED_KILL, function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent(VHubHSS.E.PED_SET_CUSTOMIZATION, function(custom)
    Citizen.CreateThread(function() VHubHSS_ApplyModelAndCustomization(custom) end)
end)

RegisterNetEvent(VHubHSS.E.PED_TELEPORT, function(x, y, z, heading)
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        if not VHubHSS_MovePed(ped, { x = x, y = y, z = z, heading = heading }) then return end
        if _hold then
            finish_spawn(_first_spawn)
        else
            Citizen.Wait(500)
            FreezeEntityPosition(ped, false)
        end
    end)
end)

-- Oculta e imobiliza o ped para uma cena visual sem transferir ownership.
exports('beginVisualScene', function()
    if GetInvokingResource() ~= 'vhub_vrcs' or _visual_scene then return false end
    local ped = current_ped()
    if not ped then return false end
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetEntityCollision(ped, false, false)
    _visual_scene = true
    return true
end)

-- Restaura o ped após a cena visual autorizada.
exports('endVisualScene', function()
    if GetInvokingResource() ~= 'vhub_vrcs' or not _visual_scene then return false end
    local ped = current_ped()
    _visual_scene = false
    if not ped then return false end
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    return true
end)

local _regen_generation = 0

RegisterNetEvent(VHubHSS.E.STATE_INIT, function()
    _regen_generation = _regen_generation + 1
    local generation = _regen_generation
    Citizen.CreateThread(function()
        while _ped_running and generation == _regen_generation do
            SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
            Citizen.Wait(1000)
        end
    end)
end)

RegisterNetEvent(VHubHSS.E.STATE_HIDE, function()
    _regen_generation = _regen_generation + 1
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local restored = type(VHubHSS_RestoreCustomizationOnStop) ~= 'function'
      or VHubHSS_RestoreCustomizationOnStop() == true
    _ped_running = false
    _regen_generation = _regen_generation + 1
    _hold = false
    _visual_scene = false
    local ped = current_ped()
    if ped then
        FreezeEntityPosition(ped, false)
        SetEntityVisible(ped, restored, false)
        SetEntityInvincible(ped, not restored)
        SetEntityCollision(ped, true, true)
    end
    DoScreenFadeIn(0)
    _animation_token = _animation_token + 1
    if _current_animation and DoesEntityExist(_current_animation.ped) then
        StopAnimTask(
            _current_animation.ped,
            _current_animation.dict,
            _current_animation.name,
            1.0
        )
    end
    if _current_animation then RemoveAnimDict(_current_animation.dict) end
    _current_animation = nil
    VHubHSS_SetInjuredWalk(false)
end)
