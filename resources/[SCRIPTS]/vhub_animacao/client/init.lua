-- client/init.lua — motor de animação/emote client-side

local E       = VHubAnimacao.E
local Catalog = VHubAnimacao.Cfg.CATALOG

local _current_prop   = nil   -- handle do objeto anexado
local _current_entry  = nil   -- entrada ativa do catálogo
local _running        = true


-- ============================================================
-- STOP
-- ============================================================

-- Para toda animação em curso e remove o prop anexado.
local function stop_emote()
    if _current_prop and DoesEntityExist(_current_prop) then
        DetachEntity(_current_prop, true, true)
        DeleteEntity(_current_prop)
    end
    _current_prop  = nil
    _current_entry = nil

    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        ClearPedTasksImmediately(ped)
    end
end


-- ============================================================
-- PROP
-- ============================================================

-- Anexa prop ao osso indicado; aguarda modelo carregar (máx 5 s).
local function attach_prop(entry, ped)
    if not entry.prop then return end
    local model = GetHashKey(entry.prop)
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) and t < 5000 do
        Citizen.Wait(50); t = t + 50
    end
    if not HasModelLoaded(model) then return end

    local obj = CreateObject(model, 0, 0, 0, false, false, false)
    if not DoesEntityExist(obj) then SetModelAsNoLongerNeeded(model); return end

    local bone = entry.hand or 28422
    local bone_idx = GetPedBoneIndex(ped, bone)
    AttachEntityToEntity(obj, ped, bone_idx, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    _current_prop = obj
end


-- ============================================================
-- ANIMAÇÃO
-- ============================================================

-- Determina flag de TaskPlayAnim pela entrada do catálogo.
local function resolve_flag(entry)
    if entry.flag then return entry.flag end
    if entry.loop and entry.andar then return 49 end -- loop + upper body additive
    if entry.loop then return 1 end                  -- loop simples
    return 0                                         -- play once
end

-- Carrega dict e toca animação; aguarda máx 5 s.
local function play_anim_dict(entry, ped)
    RequestAnimDict(entry.dict)
    local t = 0
    while not HasAnimDictLoaded(entry.dict) and t < 5000 do
        Citizen.Wait(50); t = t + 50
    end
    if not HasAnimDictLoaded(entry.dict) then
        RemoveAnimDict(entry.dict)
        return
    end

    local flag = resolve_flag(entry)
    TaskPlayAnim(ped, entry.dict, entry.anim, 8.0, -8.0, -1, flag, 0, false, false, false)
    RemoveAnimDict(entry.dict)
end


-- ============================================================
-- PLAY
-- ============================================================

-- Executa emote completo: stop → validar → animar + prop.
local function play_emote(nome)
    stop_emote()

    local entry = Catalog[nome]
    if not entry then return end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    -- validação de veículo no client (confirmação do server)
    local in_vehicle = IsPedInAnyVehicle(ped, false)
    if entry.carros and not in_vehicle then return end
    if not entry.carros and in_vehicle then return end

    _current_entry = entry

    Citizen.CreateThread(function()
        if not _running or _current_entry ~= entry then return end

        local p = PlayerPedId()

        -- anexar prop (se houver)
        if entry.prop then
            attach_prop(entry, p)
            if _current_entry ~= entry then return end -- cancelado durante carregamento
        end

        -- tipo de animação
        if entry.dict then
            play_anim_dict(entry, p)
        elseif entry.anim then
            TaskStartScenarioInPlace(p, entry.anim, 0, true)
        end
        -- sem dict e sem anim = prop-only, nada a fazer

        -- cancelamento por movimento (somente loop sem carros e andar=false)
        if entry.loop and not entry.carros and not entry.andar then
            Citizen.CreateThread(function()
                while _running and _current_entry == entry do
                    Citizen.Wait(500)
                    local vx, vy, vz = table.unpack(GetEntityVelocity(PlayerPedId()))
                    local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
                    if speed > 0.8 then
                        stop_emote()
                        return
                    end
                end
            end)
        end
    end)
end


-- ============================================================
-- EVENTOS DE REDE
-- ============================================================

RegisterNetEvent(E.PLAY_EMOTE, function(nome)
    play_emote(nome)
end)

RegisterNetEvent(E.STOP_EMOTE, function()
    stop_emote()
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    _running = false
    stop_emote()
end)
