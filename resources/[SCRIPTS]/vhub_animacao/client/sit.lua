-- client/sit.lua — sentar em qualquer superfície via raycast (portado do dynamic-sit)
-- Funciona com props do target E com o comando /sentar livre (paredes, bordas, chão)
---@diagnostic disable: undefined-global

local Sit = VHubAnimacao.Sit

local isSitting   = false
local seatProp    = 0        -- prop do target ativo (0 = livre/comando)
local _occupied   = {}       -- props ocupados por este client
local _sitData    = nil      -- dados da sessão atual (para cancelamento e sync)
local _cooldown   = false


-- ============================================================
-- UTILITÁRIOS
-- ============================================================

local function vecNorm(v)
    local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if m < 0.0001 then return vector3(0, 0, 0) end
    return vector3(v.x / m, v.y / m, v.z / m)
end


-- ============================================================
-- RAYCAST — detecção de superfície
-- ============================================================

-- Varre o ambiente ao redor do jogador com múltiplos raycasts para encontrar
-- a melhor superfície para sentar (prop/parede/borda/chão).
-- Retorna tabela com hitCoords, edge, normal, isGround, isFallLedge, style hint.
local function detectSurface()
    local ped     = PlayerPedId()
    local coords  = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local bestHit = nil

    -- 1. SWEEP VERTICAL — vários ângulos de altura para pegar props/paredes na frente
    local highestHitZOff = 0.0
    local shortestDist   = 999.0
    local sweepFound     = nil
    local heights = { -0.5, -0.4, -0.3, -0.2, -0.1, 0.0, 0.1, 0.2, 0.3, 0.5, 0.7, 1.0, 1.5 }
    local right   = vector3(-forward.y, forward.x, 0.0)

    for _, zOff in ipairs(heights) do
        for _, hOff in ipairs({ 0.0, -0.15, 0.15 }) do
            local s = vector3(coords.x + right.x * hOff, coords.y + right.y * hOff, coords.z + zOff)
            local e = s + (forward * 0.8)
            local ray = StartShapeTestRay(s.x, s.y, s.z, e.x, e.y, e.z, 31, ped, 0)
            local _, hit, hitC, norm, ent = GetShapeTestResult(ray)
            if hit == 1 then
                if zOff > highestHitZOff then highestHitZOff = zOff end
                local dist = #(coords - hitC)
                if dist < shortestDist then
                    shortestDist = dist
                    sweepFound = { hitCoords = hitC, normal = norm, entity = ent, zOff = zOff }
                end
            end
        end
    end
    if sweepFound then
        bestHit = sweepFound
        bestHit.highestHitZOff = highestHitZOff
        bestHit.cameFromSweep  = true
    end

    -- 2. EDGE-STANDING — muros baixos diagonais
    if not bestHit then
        local s = vector3(coords.x, coords.y, coords.z + 0.5)
        local e = s + (forward * 0.7) + vector3(0, 0, -1.0)
        local ray = StartShapeTestRay(s.x, s.y, s.z, e.x, e.y, e.z, 31, ped, 0)
        local _, hit, hitC, _, ent = GetShapeTestResult(ray)
        if hit == 1 then
            local gs = s + (forward * 1.0)
            local ge = gs + vector3(0, 0, -2.0)
            local gr = StartShapeTestRay(gs.x, gs.y, gs.z, ge.x, ge.y, ge.z, 31, ped, 0)
            local _, gHit = GetShapeTestResult(gr)
            if not gHit or gHit == 0 then
                bestHit = { hitCoords = hitC, edge = hitC, normal = -forward, entity = ent,
                            highestHitZOff = 0.0, cameFromSweep = false, cameFromStanding = true }
            end
        end
    end

    -- 3. EDGE-LOOKOUT — bordas/telhados (scan longitudinal em busca de drop)
    if not bestHit then
        local foundFloorOnce = false
        for i = -10, 15 do
            local dist  = i * 0.1
            local ss    = coords + (forward * dist) + vector3(0, 0, 0.45)
            local se    = ss + vector3(0, 0, -2.2)
            local ray   = StartShapeTestRay(ss.x, ss.y, ss.z, se.x, se.y, se.z, 31, ped, 0)
            local _, hit = GetShapeTestResult(ray)
            if hit == 1 then
                foundFloorOnce = true
            elseif hit == 0 and foundFloorOnce then
                if dist >= 0.05 then
                    local exact = false
                    for back = 1, 10 do
                        local sd  = dist - (back * 0.01)
                        local sub = coords + (forward * sd) + vector3(0, 0, 0.45)
                        local sue = sub + vector3(0, 0, -1.2)
                        local sr  = StartShapeTestRay(sub.x, sub.y, sub.z, sue.x, sue.y, sue.z, 31, ped, 0)
                        local _, sh = GetShapeTestResult(sr)
                        if sh == 1 then
                            local fe = coords + (forward * sd)
                            bestHit = { hitCoords = fe, edge = fe, normal = -forward, entity = 0,
                                        highestHitZOff = 0.0, cameFromSweep = false }
                            exact = true; break
                        end
                    end
                    if not exact then
                        local fe = coords + (forward * (dist - 0.1))
                        bestHit = { hitCoords = fe, edge = fe, normal = -forward, entity = 0,
                                    highestHitZOff = 0.0, cameFromSweep = false }
                    end
                    break
                end
            end
        end
    end

    -- 4. FALLBACK — chão diretamente abaixo
    local isGround = false
    if not bestHit then
        local gs = coords + vector3(0, 0, 0.5)
        local ge = coords + vector3(0, 0, -1.0)
        local gr = StartShapeTestRay(gs.x, gs.y, gs.z, ge.x, ge.y, ge.z, 31, ped, 0)
        local _, gHit, gHitC = GetShapeTestResult(gr)
        if gHit == 1 then
            bestHit  = { hitCoords = gHitC, normal = forward * -1.0, entity = 0,
                         edge = gHitC, highestHitZOff = 0.0, cameFromSweep = false }
            isGround = true
        else
            return nil
        end
    end

    local hitCoords  = bestHit.hitCoords
    local normal     = bestHit.normal
    local entity     = bestHit.entity or 0
    highestHitZOff   = bestHit.highestHitZOff or 0.0

    -- 5. EDGE SCAN — encontra o topo real da superfície (Z mais alto acima do hit)
    local bestTop = bestHit.edge
    if not isGround and not bestTop then
        local highestZ = -99.0
        for i = 0, 18 do
            local depth = (i - 3) * 0.04
            local tp    = hitCoords + (forward * depth)
            local ds    = vector3(tp.x, tp.y, hitCoords.z + 1.5)
            local de    = vector3(tp.x, tp.y, hitCoords.z - 1.0)
            local ray2  = StartShapeTestRay(ds.x, ds.y, ds.z, de.x, de.y, de.z, 31, ped, 0)
            local _, hit2, topC = GetShapeTestResult(ray2)
            if hit2 == 1 then
                local hDiff = topC.z - hitCoords.z
                if topC.z > highestZ and hDiff < 0.8 and hDiff > -0.4 then
                    highestZ = topC.z
                    bestTop  = topC
                end
            end
        end
    end

    local isLeanFallback = false
    if not bestTop then
        if #(coords - hitCoords) < 1.0 then
            bestTop      = vector3(hitCoords.x, hitCoords.y, hitCoords.z)
            isLeanFallback = true
        else
            return nil
        end
    end

    -- 6. FALL-CHECK — verifica se há vazio abaixo do topo (borda com queda)
    local isFallLedge = false
    if not isGround then
        local drs = vector3(bestTop.x, bestTop.y, bestTop.z + 0.1)
        local dre = vector3(bestTop.x, bestTop.y, bestTop.z - 2.5)
        local dr  = StartShapeTestRay(drs.x, drs.y, drs.z, dre.x, dre.y, dre.z, 31, ped, 0)
        local _, hitDown, hitDownC = GetShapeTestResult(dr)
        local fallDist = (hitDown == 1) and #(drs - hitDownC) or 3.0
        if hitDown == 0 or fallDist > 0.9 then isFallLedge = true end
    end

    return {
        hitCoords       = hitCoords,
        edge            = bestTop,
        normal          = normal,
        entity          = entity,
        isLeanFallback  = isLeanFallback,
        highestHitZOff  = highestHitZOff,
        isFallLedge     = isFallLedge,
        cameFromSweep   = bestHit.cameFromSweep   or false,
        cameFromStanding = bestHit.cameFromStanding or false,
        isGround        = isGround,
    }
end


-- ============================================================
-- CLASSIFICAÇÃO E POSICIONAMENTO
-- ============================================================

-- Offsets calibrados por estilo (portados do dynamic-sit).
-- z = quanto subtrair do Z do topo detectado; forward = recuo do ponto de hit.
local OFFSETS = {
    edge_fall = { forward = -0.03, z = 2.0  },
    ledge     = { forward = -0.3,  z = 1.05 },
    lean      = { forward =  0.1,  z = 0.0  },
    ground    = { forward =  0.1,  z = -0.95 },
}

-- Cenários para ledge/bancos — seleção aleatória para variedade.
local SCENARIOS_LEDGE = {
    'WORLD_HUMAN_SEAT_WALL', 'WORLD_HUMAN_SEAT_LEDGE',
    'PROP_HUMAN_SEAT_BENCH', 'PROP_HUMAN_SEAT_CHAIR',
    'PROP_HUMAN_SEAT_BUS_STOP_WAIT', 'PROP_HUMAN_SEAT_ARMCHAIR',
    'PROP_HUMAN_SEAT_STRIP_WATCH',
}

-- Calcula posição final e chama as natives corretas para cada estilo.
-- Retorna dados do sit para sync e cancelamento, ou nil se abortado.
local function executeSit(data, prop)
    local ped          = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local playerHead   = GetEntityHeading(ped)
    local hitCoords    = data.hitCoords
    local edge         = data.edge

    -- direção normal ao jogador (para ou longe da superfície)
    local diff   = vector3(playerCoords.x - hitCoords.x, playerCoords.y - hitCoords.y, 0.0)
    local normal = vecNorm(diff)
    if #diff < 0.01 then normal = GetEntityForwardVector(ped) * -1.0 end

    -- classificação de estilo
    local style
    if not data.isGround and not data.isFallLedge and data.highestHitZOff >= 1.0 then
        style = 'lean'
    elseif data.cameFromSweep or data.cameFromStanding then
        style = 'ledge'
    elseif data.isFallLedge then
        style = 'edge_fall'
    elseif data.isGround then
        style = 'ground'
    else
        style = 'ledge'
    end

    -- se veio de prop do target, forçar style ledge (já sabemos que é um assento)
    if prop and prop ~= 0 then style = 'ledge' end

    local offset = OFFSETS[style] or OFFSETS.ledge
    local fwd    = (style == 'lean') and 0.12 or offset.forward
    if style == 'edge_fall' then fwd = 0.25 end

    local spawnPos = vector3(
        hitCoords.x + (normal.x * fwd),
        hitCoords.y + (normal.y * fwd),
        edge.z - (offset.z or 0.0)
    )
    if style == 'lean' then
        spawnPos = vector3(spawnPos.x, spawnPos.y, playerCoords.z)
    end

    local finalHead = GetHeadingFromVector_2d(normal.x, normal.y)
    if style == 'edge_fall' then
        finalHead = (finalHead + 180.0) % 360.0
    end

    local scenario
    if style == 'ledge' or style == 'edge_fall' then
        -- para props registrados no target usa o cenário por modelo; senão aleatório
        if prop and prop ~= 0 then
            scenario = Sit.getScenario(prop)
        else
            scenario = SCENARIOS_LEDGE[math.random(#SCENARIOS_LEDGE)]
        end
        -- freeze antes de teleportar: impede que a física reposicione o ped
        FreezeEntityPosition(ped, true)
        SetEntityCollision(ped, false, false)
        SetEntityHeading(ped, finalHead)
        SetEntityCoords(ped, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, false)
        Wait(50)
        TaskStartScenarioInPlace(ped, scenario, 0, true)
        SetEntityCollision(ped, true, true)

    elseif style == 'lean' then
        scenario = 'WORLD_HUMAN_LEANING'
        TaskStartScenarioAtPosition(ped, scenario, spawnPos.x, spawnPos.y, spawnPos.z, finalHead, 0, true, true)

    else -- ground
        scenario = 'WORLD_HUMAN_PICNIC'
        TaskStartScenarioAtPosition(ped, scenario, spawnPos.x, spawnPos.y, spawnPos.z, finalHead, 0, true, true)
    end

    return {
        style       = style,
        scenario    = scenario,
        spawnPos    = spawnPos,
        finalHead   = finalHead,
        origCoords  = playerCoords,
        origHead    = playerHead,
    }
end


-- ============================================================
-- SENTAR EM PROP CONHECIDO (caminho do target — sem raycast)
-- ============================================================

-- Detecta o Z do assento do prop via raycasts verticais centrados na entidade.
-- Usa os hits MAIS BAIXOS no prop (assento < encosto); retorna nil se nenhum hit.
local function detectPropSeatZ(prop)
    local pc  = GetEntityCoords(prop)
    local ign = PlayerPedId()
    -- 5 pontos: centro + 4 laterais curtos (assento costuma estar perto do centro)
    local offsets = { {0,0}, {0.15,0}, {-0.15,0}, {0,0.15}, {0,-0.15} }
    local lowestZ = nil
    for _, o in ipairs(offsets) do
        local s = vector3(pc.x + o[1], pc.y + o[2], pc.z + 1.5)
        local e = vector3(pc.x + o[1], pc.y + o[2], pc.z - 0.2)
        local ray = StartShapeTestRay(s.x, s.y, s.z, e.x, e.y, e.z, 31, ign, 0)
        local _, hit, hitC, _, ent = GetShapeTestResult(ray)
        -- pega Z mais baixo (assento); ignora encosto (parte mais alta do prop)
        if hit == 1 and ent == prop then
            if lowestZ == nil or hitC.z < lowestZ then lowestZ = hitC.z end
        end
    end
    return lowestZ
end

-- Executa sentar diretamente em um prop do target (entidade conhecida, sem raycast de superfície).
local function sitOnProp(prop, ped)
    local propCoords = GetEntityCoords(prop)
    local propHead   = GetEntityHeading(prop)
    local scenario   = Sit.getScenario(prop)

    -- Z do assento: raycast vertical no prop; fallback = origem + offset calibrado
    local seatZ = detectPropSeatZ(prop)
    if not seatZ then
        seatZ = propCoords.z + Sit.getZOffset(prop)
    end

    -- heading: prop aponta para a frente → ped senta virado para a frente (+180 fica de costas)
    -- PROP_HUMAN_SEAT_BENCH/LEDGE espera heading da direção em que o ped olha
    -- Cenários de banco: ped olha para fora do banco (mesmo heading do prop)
    -- Cenários de cadeira/armchair: idem
    local finalHead  = propHead
    local spawnPos   = vector3(propCoords.x, propCoords.y, seatZ)
    local origCoords = GetEntityCoords(ped)
    local origHead   = GetEntityHeading(ped)

    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityHeading(ped, finalHead)
    SetEntityCoords(ped, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, false)
    Wait(50)
    ClearPedTasks(ped)
    Wait(50)
    TaskStartScenarioInPlace(ped, scenario, 0, true)
    SetEntityCollision(ped, true, true)

    return {
        style      = 'ledge',
        scenario   = scenario,
        spawnPos   = spawnPos,
        finalHead  = finalHead,
        origCoords = origCoords,
        origHead   = origHead,
    }
end


-- ============================================================
-- AÇÕES
-- ============================================================

local standUp  -- forward-declaration

local function sit(prop)
    if isSitting  then return end
    if _cooldown  then return end
    if prop and _occupied[prop] then return end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local session

    -- caminho do target: prop conhecido → usa geometria da entidade, sem raycast
    if prop and prop ~= 0 and DoesEntityExist(prop) then
        session = sitOnProp(prop, ped)

    -- caminho livre: /sentar em qualquer superfície → raycast do dynamic-sit
    else
        local data = detectSurface()
        if not data then return end
        ClearPedTasks(ped)
        Wait(50)
        session = executeSit(data, nil)
    end

    if not session then return end

    isSitting  = true
    seatProp   = prop or 0
    _sitData   = session
    _cooldown  = true
    if prop then _occupied[prop] = true end

    SetTimeout(1500, function() _cooldown = false end)

    -- sync: outros jogadores veem a posição via State Bag
    LocalPlayer.state:set('sitData', {
        coords   = { x = session.spawnPos.x, y = session.spawnPos.y, z = session.spawnPos.z },
        heading  = session.finalHead,
        scenario = session.scenario,
    }, true)

    -- cancela ao pressionar WASD (igual ao dynamic-sit original)
    CreateThread(function()
        while isSitting do
            Wait(300)
            if IsControlPressed(0, 32) or IsControlPressed(0, 33)
            or IsControlPressed(0, 34) or IsControlPressed(0, 35) then
                standUp()
            end
        end
    end)
end

standUp = function()
    if not isSitting then return end

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)

    -- para edge_fall volta para coords originais (segurança contra queda)
    if _sitData and _sitData.style == 'edge_fall' and _sitData.origCoords then
        local oc = _sitData.origCoords
        SetEntityCoords(ped, oc.x, oc.y, oc.z, false, false, false, false)
        if _sitData.origHead then SetEntityHeading(ped, _sitData.origHead) end
    end

    ClearPedTasks(ped)

    if seatProp ~= 0 then _occupied[seatProp] = nil end
    isSitting = false
    seatProp  = 0

    LocalPlayer.state:set('sitData', nil, true)
    _sitData = nil
end

-- comando livre: /sentar — funciona em qualquer superfície (parede, borda, chão)
RegisterCommand('sentar', function()
    if isSitting then
        standUp()
    else
        sit(nil)
    end
end, false)

RegisterCommand('levantar', function()
    if isSitting then standUp() end
end, false)


-- ============================================================
-- REGISTRO NO vhub_target — props da lista SeatableProps
-- ============================================================

CreateThread(function()
    while not exports['vhub_target'] do Wait(500) end

    exports['vhub_target']:addModel(SeatableProps, {
        {
            name        = 'animacao:sentar',
            label       = 'Sentar',
            icon        = 'fa-solid fa-chair',
            distance    = 2.0,
            canInteract = function(entity)
                return not (isSitting and seatProp == entity)
            end,
            onSelect    = function(data) sit(data.entity) end,
        },
        {
            name        = 'animacao:levantar',
            label       = 'Levantar',
            icon        = 'fa-solid fa-person-walking',
            distance    = 3.0,
            canInteract = function(entity)
                return isSitting and seatProp == entity
            end,
            onSelect    = function(_) standUp() end,
        },
    })
end)


-- ============================================================
-- SYNC MULTI-JOGADOR — outros veem a animação via State Bag
-- ============================================================

AddStateBagChangeHandler('sitData', nil, function(bagName, _, value)
    local playerID = GetPlayerFromStateBagName(bagName)
    if playerID == 0 then return end
    local player = GetPlayerFromServerId(playerID)
    if player == -1 then return end
    local ped = GetPlayerPed(player)
    if not DoesEntityExist(ped) then return end
    if ped == PlayerPedId() then return end  -- ignora próprio ped

    if value then
        SetEntityCoords(ped, value.coords.x, value.coords.y, value.coords.z, false, false, false, false)
        SetEntityHeading(ped, value.heading)
        TaskStartScenarioInPlace(ped, value.scenario, 0, true)
    else
        ClearPedTasks(ped)
    end
end)


-- ============================================================
-- EVENTO DE REDE — force-stand pelo server (algemado, desmaiado)
-- ============================================================

RegisterNetEvent(VHubAnimacao.E.SIT_FORCE_STAND, function()
    if isSitting then standUp() end
end)


-- ============================================================
-- LIMPEZA
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isSitting then standUp() end
end)
