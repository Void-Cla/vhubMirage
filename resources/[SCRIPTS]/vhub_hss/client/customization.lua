-- client/customization.lua — HAL efêmera do editor de aparência

local _stage_active = false
local _stage_ready = false   -- verdadeiro só após VHubHSS_MovePed concluir
local _preview_active = false
local _snapshot = nil
local _preview = nil
local _camera = nil
local _base_heading = 0.0
local _stage_failed = false

local CAMERA_PRESETS = {
    full = { bone = 24818, offset = { x = 0.0, y = 2.35, z = 0.15 }, fov = 38.0 },
    face = { bone = 31086, offset = { x = 0.0, y = 0.82, z = 0.05 }, fov = 24.0 },
    body = { bone = 24818, offset = { x = 0.0, y = 1.45, z = 0.02 }, fov = 32.0 },
    legs = { bone = 11816, offset = { x = 0.0, y = 1.55, z = 0.10 }, fov = 34.0 },
}
CAMERA_PRESETS.head = CAMERA_PRESETS.face
CAMERA_PRESETS.torso = CAMERA_PRESETS.body
CAMERA_PRESETS.feet = CAMERA_PRESETS.legs


-- ============================================================
-- GUARDS / CLEANUP
-- ============================================================

local function invoker_ok()
    return GetInvokingResource() == 'vhub_sims'
end

local function current_ped()
    local ped = PlayerPedId()
    return ped ~= 0 and DoesEntityExist(ped) and ped or nil
end

local function cleanup_camera()
    if _camera then
        RenderScriptCams(false, false, 0, true, true)
        if DoesCamExist(_camera) then DestroyCam(_camera, true) end
    end
    _camera = nil
end

local function abort_stage()
    cleanup_camera()
    _stage_active = false
    _stage_ready = false
    _preview_active = false
    _snapshot = nil
    _preview = nil
    _stage_failed = true
    DoScreenFadeIn(0)
end

local function apply_preview(customization)
    local ped = current_ped()
    if not ped then return false end
    if VHubHSS_ApplyModelAndCustomization(customization) ~= true then return false end
    ped = current_ped()
    if not ped then return false end
    if _stage_active then
        FreezeEntityPosition(ped, true)
        SetEntityVisible(ped, true, false)
        SetEntityInvincible(ped, true)
    end
    return true
end


-- ============================================================
-- ESTÁGIO AUTORITATIVO
-- ============================================================

RegisterNetEvent(VHubHSS.E.CUSTOMIZATION_STAGE_BEGIN, function(payload)
    if type(payload) ~= 'table' or type(payload.position) ~= 'table' then return end
    Citizen.CreateThread(function()
        cleanup_camera()
        _snapshot = VHubHSS.Appearance.sanitize(payload.customization)
        _preview = VHubHSS.Appearance.copy(_snapshot)
        _base_heading = tonumber(payload.position.heading) or tonumber(payload.position.h) or 0.0
        _stage_active = true
        _stage_ready = false
        _preview_active = true
        _stage_failed = false

        DoScreenFadeOut(150)
        Citizen.Wait(200)
        if not apply_preview(_snapshot) then
            abort_stage()
            return
        end
        local ped = current_ped()
        if not ped or not VHubHSS_MovePed(ped, payload.position) then
            abort_stage()
            return
        end
        SetEntityCollision(ped, true, true)
        _stage_ready = true   -- ped está na posição; câmera pode ser configurada
        DoScreenFadeIn(250)
    end)
end)

RegisterNetEvent(VHubHSS.E.CUSTOMIZATION_STAGE_END, function(payload)
    if type(payload) ~= 'table' then return end
    Citizen.CreateThread(function()
        cleanup_camera()
        _stage_failed = false
        local authoritative = VHubHSS.Appearance.sanitize(payload.customization)
        VHubHSS_ApplyModelAndCustomization(authoritative)
        local ped = current_ped()
        if ped then
            if type(payload.position) == 'table' then VHubHSS_MovePed(ped, payload.position) end
            FreezeEntityPosition(ped, true)
            SetEntityVisible(ped, false, false)
            SetEntityInvincible(ped, true)
            SetEntityCollision(ped, true, true)
        end
        _stage_active = false
        _preview_active = false
        _snapshot = nil
        _preview = nil
        DoScreenFadeIn(0)
    end)
end)


-- ============================================================
-- BRIDGE DO VHub SIMS
-- ============================================================

-- Abre a sessão efêmera e retorna snapshot APV2 independente.
exports('beginCustomizationPreview', function(snapshot)
    if not invoker_ok() then return { ok = false, err = 'forbidden' } end
    if _stage_failed then return { ok = false, err = 'inactive' } end
    -- estágio iniciado mas ped ainda se movendo: aguardar VHubHSS_MovePed
    if _stage_active and not _stage_ready then return { ok = false, err = 'stage_not_ready' } end
    if not _stage_active then
        if type(snapshot) ~= 'table' then return { ok = false, err = 'inactive' } end
        _snapshot = VHubHSS.Appearance.sanitize(snapshot)
        _base_heading = GetEntityHeading(current_ped() or 0)
    end
    if not _snapshot then return { ok = false, err = 'inactive' } end
    _preview = VHubHSS.Appearance.copy(_snapshot)
    _preview_active = true
    return { ok = true, customization = VHubHSS.Appearance.copy(_snapshot) }
end)

-- Mescla patch sanitizado e aplica preview local sem persistência.
exports('previewCustomization', function(patch)
    if not invoker_ok() or not _preview_active or not _preview then
        return { ok = false, err = 'inactive' }
    end
    local clean = VHubHSS.Appearance.sanitizePatch(patch)
    if not clean then return { ok = false, err = 'invalid_patch' } end
    local next_preview = VHubHSS.Appearance.merge(_preview, clean)
    local model_changed = clean.model ~= nil and clean.model ~= _preview.model
    local applied
    if model_changed then
        applied = apply_preview(next_preview)
    else
        applied = VHubHSS_ApplyCustomizationPatch(current_ped(), clean, next_preview)
    end
    if not applied then return { ok = false, err = 'native' } end
    _preview = next_preview
    return { ok = true, customization = VHubHSS.Appearance.copy(_preview) }
end)

-- Restaura o snapshot capturado na abertura do estágio.
exports('restoreCustomizationPreview', function()
    if not invoker_ok() or not _preview_active or not _snapshot then
        return { ok = false, err = 'inactive' }
    end
    if not apply_preview(_snapshot) then return { ok = false, err = 'native' } end
    _preview = VHubHSS.Appearance.copy(_snapshot)
    return { ok = true, customization = VHubHSS.Appearance.copy(_preview) }
end)

-- Posiciona câmera HSS em preset fechado e callback-driven.
exports('setCustomizationCamera', function(preset_name)
    if not invoker_ok() or not _preview_active then return { ok = false, err = 'inactive' } end
    local preset = type(preset_name) == 'string' and CAMERA_PRESETS[preset_name] or nil
    local ped = current_ped()
    if not preset or not ped then return { ok = false, err = 'invalid_camera' } end

    local position = GetOffsetFromEntityInWorldCoords(
        ped,
        preset.offset.x,
        preset.offset.y,
        preset.offset.z
    )
    local target = GetPedBoneCoords(ped, preset.bone, 0.0, 0.0, 0.0)
    if not _camera or not DoesCamExist(_camera) then
        _camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    end
    if not _camera or not DoesCamExist(_camera) then return { ok = false, err = 'native' } end
    SetCamCoord(_camera, position.x, position.y, position.z)
    PointCamAtCoord(_camera, target.x, target.y, target.z)
    SetCamFov(_camera, preset.fov)
    SetCamActive(_camera, true)
    RenderScriptCams(true, false, 0, true, true)
    return { ok = true }
end)

-- Rotaciona o ped dentro do estágio sem thread permanente.
exports('rotateCustomizationPed', function(delta)
    if not invoker_ok() or not _preview_active then return { ok = false, err = 'inactive' } end
    local number = tonumber(delta)
    local ped = current_ped()
    if not number or number ~= number or not ped then return { ok = false, err = 'invalid_rotation' } end
    number = math.max(-45.0, math.min(45.0, number))
    _base_heading = (_base_heading + number) % 360.0
    SetEntityHeading(ped, _base_heading)
    return { ok = true, heading = _base_heading }
end)

-- Encerra câmera/preview local; o hold autoritativo termina somente no servidor HSS.
exports('endCustomizationPreview', function(restore)
    if not invoker_ok() then return { ok = false, err = 'forbidden' } end
    cleanup_camera()
    if restore == true and _preview_active and _snapshot then apply_preview(_snapshot) end
    _preview_active = false
    if not _stage_active then
        _snapshot = nil
        _preview = nil
    else
        _preview = _snapshot and VHubHSS.Appearance.copy(_snapshot) or nil
    end
    return { ok = true }
end)

-- restaura o snapshot autoritativo antes do loader de modelo ser encerrado
function VHubHSS_RestoreCustomizationOnStop()
    if _preview_active and _snapshot then return apply_preview(_snapshot) end
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanup_camera()
    _stage_active = false
    _preview_active = false
    _stage_failed = false
    _snapshot = nil
    _preview = nil
end)
