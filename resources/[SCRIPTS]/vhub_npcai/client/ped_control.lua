---@diagnostic disable: undefined-global
-- ped_control.lua — criação e controle dos peds de NPC (client-side, isNetwork=false)
-- Ownership: vhub_npcai (L-07). Não conflita com L-16 pois não é ped de jogador.

local cfg   = VHubNpcAI.cfg

-- registry: npc_id → { ped, blip, relationGroup }
VHubNpcAI.peds = {}
local Peds = VHubNpcAI.peds


-- ============================================================
-- RELATIONSHIP GROUP ÚNICO (impede NPCs se atacarem mutuamente)
-- ============================================================

local REL_GROUP_NAME = 'VHUB_NPCAI'
local PLAYER_GROUP = GetHashKey('PLAYER')
local _relGroup = nil

local function _getRelGroup()
    if _relGroup then return _relGroup end
    AddRelationshipGroup(REL_GROUP_NAME)
    _relGroup = GetHashKey(REL_GROUP_NAME)
    -- relacionamento amistoso entre todos os NPCs do sistema
    SetRelationshipBetweenGroups(0, _relGroup, _relGroup)
    -- relacionamento neutro com o jogador
    SetRelationshipBetweenGroups(3, _relGroup, PLAYER_GROUP)
    SetRelationshipBetweenGroups(3, PLAYER_GROUP, _relGroup)
    return _relGroup
end


-- ============================================================
-- SPAWN DE PED
-- ============================================================

-- carrega modelo e aguarda (com timeout de 5s)
local function _loadModel(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 5000 do
        Wait(100); t = t + 100
    end
    return HasModelLoaded(hash) and hash or nil
end

-- cria ped de NPC em posição fixa; retorna handle ou nil
local function _spawnPed(npc)
    local hash = _loadModel(npc.model)
    if not hash then
        VHubNpcAI.Log.warn('modelo nao carregado: ' .. npc.model)
        return nil
    end

    local c   = npc.coords
    -- isNetwork=false → ped local, sem broadcast OneSync (zero cost de rede)
    local ped = CreatePed(4, hash, c.x, c.y, c.z, npc.heading, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(ped) then return nil end

    -- ── comportamento estático ──────────────────────────────
    SetEntityInvincible(ped, true)           -- imortal
    SetBlockingOfNonTemporaryEvents(ped, true) -- ignora explosão, sirene, etc.
    SetPedFleeAttributes(ped, 0, false)       -- não foge
    SetPedCombatAttributes(ped, 17, false)    -- não ataca
    SetPedDiesWhenInjured(ped, false)
    FreezeEntityPosition(ped, false)          -- pode animar mas não se move
    SetPedCanRagdoll(ped, false)
    SetPedConfigFlag(ped, 32, true)           -- não reage a colisão de veículo
    SetPedConfigFlag(ped, 281, true)          -- sem diálogo ambiental do GTA

    -- ── relationship group ─────────────────────────────────
    local rg = _getRelGroup()
    SetPedRelationshipGroupHash(ped, rg)

    -- ── facial idle ────────────────────────────────────────
    if npc.idle_face then
        SetFacialIdleAnimOverride(ped, npc.idle_face, nil)
    end

    -- ── scenario de idle ───────────────────────────────────
    if npc.scenario then
        TaskStartScenarioInPlace(ped, npc.scenario, 0, true)
    end

    return ped
end

-- cria blip no minimapa para o NPC
local function _spawnBlip(npc, ped)
    local blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, npc.blip_sprite or 280)
    SetBlipColour(blip, npc.blip_color  or 3)
    SetBlipScale(blip,  npc.blip_scale  or 0.8)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(npc.nome or npc.id)
    EndTextCommandSetBlipName(blip)
    return blip
end


-- ============================================================
-- SPAWN DE TODOS OS NPCS CONFIGURADOS
-- ============================================================

-- constrói lista de opções de alvo para um NPC (closures capturam npcId e direct_text)
local function _buildTargetOpts(npcId, npc)
    local opts = {}
    for _, opt in ipairs(npc.target_options or {}) do
        local dt  = opt.direct_text   -- nil = abre microfone
        local nm  = 'npcai_' .. npcId .. '_' .. (opt.name or 'talk')
        local lbl = opt.label or 'Falar'
        table.insert(opts, {
            name = nm,
            label = lbl,
            canInteract = function()
                if VHubNpcAI.state.recording then return false end
                -- permite interromper enquanto o NPC FALA; bloqueia em pensamento/espera
                if VHubNpcAI.state.conversing and not VHubNpcAI.state.npcSpeaking then
                    return false
                end
                return true
            end,
            onSelect = function()
                VHubNpcAI.startTalk(npcId, dt)
            end,
        })
    end
    return opts
end


-- ============================================================
-- API PÚBLICA (usada por proximity e playback)
-- ============================================================

-- retorna handle do ped de um npc_id (ou nil)
function VHubNpcAI.getPed(npcId)
    local entry = Peds[npcId]
    return entry and entry.ped or nil
end

-- ativa lip-sync "falando" no ped
function VHubNpcAI.pedStartTalk(npcId)
    local ped = VHubNpcAI.getPed(npcId)
    if not ped then return end
    local npc = cfg.npcs[npcId]
    if npc and npc.talk_anim then
        local d, n = npc.talk_anim.dict, npc.talk_anim.name
        if not HasAnimDictLoaded(d) then RequestAnimDict(d) end
        PlayFacialAnim(ped, n, d)
    end
end

-- para lip-sync e volta ao idle
function VHubNpcAI.pedStopTalk(npcId)
    local ped = VHubNpcAI.getPed(npcId)
    if not ped then return end
    local npc = cfg.npcs[npcId]
    if npc and npc.idle_face then
        SetFacialIdleAnimOverride(ped, npc.idle_face, nil)
    end
end

-- faz ped olhar para o jogador (head tracking durante conversa)
function VHubNpcAI.pedLookAtPlayer(npcId)
    local ped       = VHubNpcAI.getPed(npcId)
    local playerPed = PlayerPedId()
    if ped and playerPed then
        TaskLookAtEntity(ped, playerPed, 5000, 2048, 3)
    end
end

-- cancela look-at e volta ao cenário idle
function VHubNpcAI.pedLookReset(npcId)
    local ped = VHubNpcAI.getPed(npcId)
    if not ped then return end
    ClearPedTasks(ped)
    local npc = cfg.npcs[npcId]
    if npc and npc.scenario then
        TaskStartScenarioInPlace(ped, npc.scenario, 0, true)
    end
end


-- ============================================================
-- COMPORTAMENTO AMBIENTE (perimeter patrol + animações de trabalho)
-- ============================================================

-- pontos de patrulha locais ao NPC: offsets relativos à posição base (em metros)
local _PATROL_OFFSETS = {
    { x =  2.0, y =  0.0 },
    { x =  2.0, y =  2.0 },
    { x =  0.0, y =  2.0 },
    { x = -2.0, y =  0.0 },
    { x =  0.0, y =  0.0 },  -- volta ao centro
}

-- cenários de trabalho alternados nas pausas (faz o NPC "fingir que trabalha")
local _WORK_SCENARIOS = {
    'WORLD_HUMAN_CLIPBOARD',
    'WORLD_HUMAN_STAND_MOBILE',
    'WORLD_HUMAN_STAND_IMPATIENT',
    'WORLD_HUMAN_SMOKING',
    'WORLD_HUMAN_DRINKING',
}

-- caminha até ponto relativo e espera chegar (ou timeout de 5s)
local function _walkTo(ped, tx, ty, tz)
    TaskGoStraightToCoord(ped, tx, ty, tz, 1.0, 5000, 0.0, 0.1)
    local deadline = GetGameTimer() + 5000
    while GetGameTimer() < deadline do
        local px, py, pz = GetEntityCoords(ped)
        if GetDistanceBetweenCoords(px, py, pz, tx, ty, tz, true) < 0.8 then break end
        Wait(200)
    end
end

-- ciclo de patrulha para um NPC; só roda quando não está em conversa
local function _startAmbient(_, npc, ped)
    if not npc.patrol then return end  -- desligado por NPC sem patrol=true

    Citizen.CreateThread(function()
        local base    = npc.coords
        local basePos = vector3(base.x, base.y, base.z)  -- uso LOCAL (L-19)
        local step    = 0

        while DoesEntityExist(ped) do
            -- longe do NPC: ninguém vê a patrulha → hiberna barato (sem walkTo em idle)
            if #(GetEntityCoords(PlayerPedId()) - basePos) > 60.0 then
                Wait(3000)
                goto continue
            end

            -- aguarda não estar em conversa
            if VHubNpcAI.state.conversing then
                Wait(1000)
                goto continue
            end

            step = (step % #_PATROL_OFFSETS) + 1
            local off = _PATROL_OFFSETS[step]
            local tx = base.x + off.x
            local ty = base.y + off.y
            local tz = base.z

            _walkTo(ped, tx, ty, tz)

            if VHubNpcAI.state.conversing then goto continue end

            -- pausa com cenário de trabalho aleatório
            local scenario = _WORK_SCENARIOS[math.random(#_WORK_SCENARIOS)]
            TaskStartScenarioAtPosition(ped, scenario, tx, ty, tz, math.random(0, 360), math.random(4000, 9000), true, true)
            Wait(math.random(5000, 12000))

            if not DoesEntityExist(ped) then break end
            ClearPedTasks(ped)
            Wait(500)

            ::continue::
        end
    end)
end


-- ============================================================
-- SPAWN DE TODOS OS NPCS CONFIGURADOS (agora com ambient)
-- ============================================================

Citizen.CreateThread(function()
    if not cfg.enabled then return end
    Wait(2000)
    for id, npc in pairs(cfg.npcs) do
        if npc.enabled and not Peds[id] then
            local ped = _spawnPed(npc)
            if ped then
                local blip = _spawnBlip(npc, ped)
                local targetOpts = _buildTargetOpts(id, npc)
                if #targetOpts > 0 then
                    pcall(function()
                        exports.vhub_target:addLocalEntity({ ped }, targetOpts)
                    end)
                end
                Peds[id] = { ped = ped, blip = blip, targetOpts = targetOpts }
                _startAmbient(id, npc, ped)
            end
        end
    end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, entry in pairs(Peds) do
        -- remove opções de alvo antes de destruir a entidade
        if entry.targetOpts and #entry.targetOpts > 0 then
            pcall(function()
                exports.vhub_target:removeLocalEntity({ entry.ped })
            end)
        end
        if DoesEntityExist(entry.ped) then DeleteEntity(entry.ped) end
        if DoesBlipExist(entry.blip) then RemoveBlip(entry.blip) end
    end
    if _relGroup then
        RemoveRelationshipGroup(_relGroup)
        _relGroup = nil
    end
end)
