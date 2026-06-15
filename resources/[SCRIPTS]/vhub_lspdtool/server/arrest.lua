---@diagnostic disable: undefined-global, lowercase-global

-- arrest.lua — prisão (detenção RP) + apreensão de veículo, server-authoritative.
-- "Prender mais próximo": o SERVER acha o jogador mais próximo do policial (coords
-- autênticas), valida o alcance e aplica o estado de detido no cliente do alvo.
-- "Apreender": reusa o pátio do vhub_garage (sem segunda fonte de verdade de veículo).

local cfg = VHubLspd.cfg
local E   = VHubLspd.E

local Arrest = {}
VHubLspd.Arrest = Arrest

local _detained = {}  -- [targetSrc] = { by = officerSrc, since = ms }

local function Log(level, fmt, ...) if VHubLspd.Log then VHubLspd.Log(level, fmt, ...) end end


-- ============================================================
-- ALVO MAIS PRÓXIMO (verdade de posição é do servidor)
-- ============================================================

-- acha o player mais próximo do policial dentro do alcance; pred filtra candidatos
local function nearestPlayer(officer, maxRange, pred)
    local ped = GetPlayerPed(officer)
    if not ped or ped == 0 then return nil end
    local origin = GetEntityCoords(ped)

    local best, bestDist
    for _, pid in ipairs(GetPlayers()) do
        local s = tonumber(pid)
        if s and s ~= officer and GetPlayerName(s) and (not pred or pred(s)) then
            local tped = GetPlayerPed(s)
            if tped and tped ~= 0 then
                local d = #(origin - GetEntityCoords(tped))
                if d <= maxRange and (not bestDist or d < bestDist) then
                    best, bestDist = s, d
                end
            end
        end
    end
    return best
end


-- ============================================================
-- DETENÇÃO
-- ============================================================

-- detém o jogador mais próximo do policial; retorna (true, info) ou (false, motivo)
function Arrest.arrestNearest(officer)
    local target = nearestPlayer(officer, cfg.arrest.rangeM, function(s) return not _detained[s] end)
    if not target then return false, 'sem_alvo' end

    _detained[target] = { by = officer, since = GetGameTimer() }
    TriggerClientEvent(E.DETAIN_APPLY, target, { dict = cfg.arrest.dict, anim = cfg.arrest.anim })
    Log('info', 'detido: src %s por src %s', tostring(target), tostring(officer))
    return true, { target = target, name = GetPlayerName(target) }
end


-- solta o detido mais próximo do policial; retorna (true, info) ou (false, motivo)
function Arrest.releaseNearest(officer)
    local target = nearestPlayer(officer, cfg.arrest.rangeM, function(s) return _detained[s] ~= nil end)
    if not target then return false, 'sem_alvo' end

    _detained[target] = nil
    TriggerClientEvent(E.DETAIN_RELEASE, target)
    Log('info', 'liberado: src %s por src %s', tostring(target), tostring(officer))
    return true, { target = target, name = GetPlayerName(target) }
end


-- ============================================================
-- APREENSÃO DE VEÍCULO (reusa o pátio do vhub_garage)
-- ============================================================

-- apreende um veículo por placa; retorna (true, info) ou (false, motivo)
function Arrest.seize(officer, plate, reason)
    local p = VHubLspd.normalizePlate(plate)
    if not p then return false, 'placa_invalida' end

    local res = cfg.seize.garageResource
    if GetResourceState(res) ~= 'started' then return false, 'patio_indisponivel' end

    -- confere existência/estado no pátio antes de mandar apreender (exports declarados)
    local okGet, v = pcall(function() return exports[res]:getVehicle(p) end)
    if not okGet or not v then return false, 'veiculo_nao_registrado' end

    local okImp, imp = pcall(function() return exports[res]:isImpound(p) end)
    if okImp and imp == true then return false, 'ja_apreendido' end

    reason = tostring(reason or cfg.seize.defaultReason):gsub('[%c]', ''):sub(1, 120)
    -- forceImpound = porta declarada p/ terceiros (gateada por _invoker_allowed no garage)
    local okCall, ret = pcall(function()
        return exports[res]:forceImpound(p, reason, cfg.seize.feeExtra)
    end)
    if not okCall or ret == false then return false, 'falha_apreensao' end

    Log('info', 'apreensão: placa %s por src %s', p, tostring(officer))
    return true, { plate = p }
end


-- ============================================================
-- CONSULTA / CLEANUP
-- ============================================================

-- true se o src está detido (consulta de cache)
function Arrest.isDetained(src) return _detained[tonumber(src) or 0] ~= nil end


-- libera caches do player que saiu (e solta quem ele havia prendido)
AddEventHandler('playerDropped', function()
    local src = source
    _detained[src] = nil
    for t, info in pairs(_detained) do
        if info.by == src then
            _detained[t] = nil
            TriggerClientEvent(E.DETAIN_RELEASE, t)
        end
    end
end)


-- solta todos os detidos ao parar o resource (evita jogador travado algemado)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for t in pairs(_detained) do TriggerClientEvent(E.DETAIN_RELEASE, t) end
    _detained = {}
end)
