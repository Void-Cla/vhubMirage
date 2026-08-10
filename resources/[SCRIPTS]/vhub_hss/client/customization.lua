-- client/customization.lua — HAL efêmera do editor de aparência

local _stage_active = false
local _stage_ready = false   -- verdadeiro só após VHubHSS_MovePed concluir
local _preview_active = false
local _snapshot = nil
local _preview = nil
local _camera = nil
local _base_heading = 0.0
local _stage_failed = false
local _loaded_ipls = {}

local CAMERA_PRESETS = {
    full = { bone = 24818, dist = 2.35, height = 0.15, pitch = 0.0, fov = 38.0 },
    face = { bone = 31086, dist = 0.82, height = 0.05, pitch = 0.0, fov = 24.0 },
    body = { bone = 24818, dist = 1.45, height = 0.02, pitch = 0.0, fov = 32.0 },
    legs = { bone = 11816, dist = 1.55, height = 0.10, pitch = -6.0, fov = 34.0 },
}
CAMERA_PRESETS.head = CAMERA_PRESETS.face
CAMERA_PRESETS.torso = CAMERA_PRESETS.body
CAMERA_PRESETS.chest = CAMERA_PRESETS.body
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

-- Carrega best-effort os IPLs da cena do interior; guarda os nomes para remover depois.
local function request_scene_ipls(list)
    _loaded_ipls = {}
    if type(list) ~= 'table' then return end
    for _, name in ipairs(list) do
        if type(name) == 'string' and name ~= '' then
            RequestIpl(name)
            _loaded_ipls[#_loaded_ipls + 1] = name
        end
    end
end

-- Remove os IPLs da cena carregados nesta sessão (idempotente).
local function remove_scene_ipls()
    for _, name in ipairs(_loaded_ipls) do RemoveIpl(name) end
    _loaded_ipls = {}
end

local function abort_stage()
    cleanup_camera()
    remove_scene_ipls()
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
        remove_scene_ipls()
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

        -- Cena premium: carrega o interior e posiciona o ped (VHubHSS_MovePed já espera a colisão).
        request_scene_ipls(payload.ipl)
        local ped = current_ped()
        if not ped or not VHubHSS_MovePed(ped, payload.position) then
            abort_stage()
            return
        end
        SetEntityCollision(ped, true, true)
        -- Interior não carregou a colisão a tempo → cai no void (que sempre existe), sem esperar de novo.
        if not HasCollisionLoadedAroundEntity(ped) and type(payload.fallback) == 'table' then
            remove_scene_ipls()
            if VHubHSS_MovePed(ped, payload.fallback) then
                _base_heading = tonumber(payload.fallback.heading) or _base_heading
                SetEntityCollision(ped, true, true)
            end
        end

        SetEntityVisible(ped, true, false)   -- garante ped visível ao revelar (anti-fantasma)
        -- Reaplica a aparência na entidade já assentada. Um SetPlayerModel feito no 1º apply pode
        -- NÃO renderizar head-blend/componentes no frame imediato (ped "só aparece após atualizar").
        -- Depois do MovePed (que já esperou colisão = vários frames) o modelo está pronto → reaplica.
        VHubHSS_ApplyCustomization(ped, _preview)
        _stage_ready = true   -- ped na posição e renderizado; câmera pode ser configurada
        DoScreenFadeIn(250)
    end)
end)

RegisterNetEvent(VHubHSS.E.CUSTOMIZATION_STAGE_END, function(payload)
    if type(payload) ~= 'table' then return end
    Citizen.CreateThread(function()
        cleanup_camera()
        remove_scene_ipls()
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

-- Estado orbital da câmera; recalculado só sob input (sem thread permanente, L-18).
local _cam_state = {
    bone = 24818, base_heading = 0.0,
    yaw = 0.0, pitch = 0.0,
    dist = 2.35, base_dist = 2.35, height = 0.15, fov = 38.0,
}

local PITCH_MIN, PITCH_MAX = -25.0, 35.0
local DIST_MIN_FACTOR, DIST_MAX_FACTOR = 0.55, 2.2

local function clampf(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

-- Posiciona a câmera a partir do estado orbital ao redor do bone-alvo (heading base fixo).
-- O alvo é deslocado lateralmente para o ped ficar centrado na ÁREA LIVRE (painel largo à direita).
local function apply_orbit_to(cam)
    local ped = current_ped()
    if not ped or not cam or not DoesCamExist(cam) then return false end
    local target = GetPedBoneCoords(ped, _cam_state.bone, 0.0, 0.0, 0.0)
    local ang = math.rad(_cam_state.base_heading + 180.0 + _cam_state.yaw)
    local pitch = math.rad(_cam_state.pitch)
    local horiz = _cam_state.dist * math.cos(pitch)
    local px = target.x + horiz * math.sin(ang)
    local py = target.y + horiz * math.cos(ang)
    local pz = target.z + _cam_state.height + _cam_state.dist * math.sin(pitch)
    SetCamCoord(cam, px, py, pz)
    -- vetor "direita" horizontal da câmera; mover o alvo p/ a direita joga o ped à esquerda da tela
    local dirx, diry = target.x - px, target.y - py
    local rlen = math.sqrt(dirx * dirx + diry * diry)
    local lat = _cam_state.dist * 0.12
    if rlen > 0.001 then
        PointCamAtCoord(cam, target.x + (diry / rlen) * lat, target.y - (dirx / rlen) * lat, target.z)
    else
        PointCamAtCoord(cam, target.x, target.y, target.z)
    end
    SetCamFov(cam, _cam_state.fov)
    return true
end

-- Enquadra uma região (preset) com transição suave; a câmera orbita, o ped fica parado.
exports('setCustomizationCamera', function(preset_name)
    if not invoker_ok() or not _preview_active then return { ok = false, err = 'inactive' } end
    local preset = type(preset_name) == 'string' and CAMERA_PRESETS[preset_name] or nil
    local ped = current_ped()
    if not preset or not ped then return { ok = false, err = 'invalid_camera' } end
    SetEntityVisible(ped, true, false)   -- ped visível quando a câmera engata (anti-fantasma)

    _cam_state.bone = preset.bone
    _cam_state.dist = preset.dist
    _cam_state.base_dist = preset.dist
    _cam_state.height = preset.height
    _cam_state.fov = preset.fov
    _cam_state.pitch = preset.pitch or 0.0

    if not _camera or not DoesCamExist(_camera) then
        -- primeira montagem: fixa o heading base (frente do ped) e zera a órbita.
        _cam_state.base_heading = _base_heading
        _cam_state.yaw = 0.0
        _camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        if not _camera or not DoesCamExist(_camera) then return { ok = false, err = 'native' } end
        apply_orbit_to(_camera)
        SetCamActive(_camera, true)
        RenderScriptCams(true, false, 0, true, true)
        return { ok = true }
    end

    -- troca de região: interpola da câmera atual para uma destino (yaw/base_heading preservados).
    local dest = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not dest or not DoesCamExist(dest) then
        apply_orbit_to(_camera)   -- fallback: sem interp
        return { ok = true }
    end
    apply_orbit_to(dest)
    SetCamActiveWithInterp(dest, _camera, 350, 1, 1)
    RenderScriptCams(true, false, 0, true, true)
    local previous = _camera
    _camera = dest
    Citizen.CreateThread(function()
        Citizen.Wait(400)
        if previous ~= _camera and DoesCamExist(previous) then DestroyCam(previous, false) end
    end)
    return { ok = true }
end)

-- Órbita livre por delta abstrato (drag = dyaw/dpitch, scroll = dzoom); clamps server-side.
exports('updateCustomizationCamera', function(delta)
    if not invoker_ok() or not _preview_active then return { ok = false, err = 'inactive' } end
    if type(delta) ~= 'table' or not _camera or not DoesCamExist(_camera) then
        return { ok = false, err = 'inactive' }
    end
    local dyaw = tonumber(delta.dyaw) or 0.0
    local dpitch = tonumber(delta.dpitch) or 0.0
    local dzoom = tonumber(delta.dzoom) or 0.0
    if dyaw ~= dyaw or dpitch ~= dpitch or dzoom ~= dzoom then
        return { ok = false, err = 'invalid_camera' }
    end
    -- clamp de delta por chamada (anti-spike) + clamp absoluto do estado
    _cam_state.yaw = ((_cam_state.yaw + clampf(dyaw, -30.0, 30.0) + 180.0) % 360.0) - 180.0
    _cam_state.pitch = clampf(_cam_state.pitch + clampf(dpitch, -20.0, 20.0), PITCH_MIN, PITCH_MAX)
    _cam_state.dist = clampf(_cam_state.dist - clampf(dzoom, -0.6, 0.6),
        _cam_state.base_dist * DIST_MIN_FACTOR, _cam_state.base_dist * DIST_MAX_FACTOR)
    apply_orbit_to(_camera)
    return { ok = true }
end)

-- Compat: gira a câmera em torno do ped por passo fixo (botões ↶↷) — mesmo canal de órbita.
exports('rotateCustomizationPed', function(delta)
    if not invoker_ok() or not _preview_active then return { ok = false, err = 'inactive' } end
    local number = tonumber(delta)
    if not number or number ~= number or not _camera or not DoesCamExist(_camera) then
        return { ok = false, err = 'invalid_rotation' }
    end
    number = clampf(number, -45.0, 45.0)
    _cam_state.yaw = ((_cam_state.yaw + number + 180.0) % 360.0) - 180.0
    apply_orbit_to(_camera)
    return { ok = true, yaw = _cam_state.yaw }
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
    remove_scene_ipls()
    _stage_active = false
    _preview_active = false
    _stage_failed = false
    _snapshot = nil
    _preview = nil
end)
