---@diagnostic disable: undefined-global, lowercase-global

-- arrest.lua — estado de DETIDO no cliente (camada L2/HAL). O servidor é a autoridade:
-- ele decide quem é preso/solto e dispara DETAIN_APPLY/RELEASE; aqui só aplicamos a
-- experiência (animação de algema + bloqueio de controles). Sem decisão de verdade.

local cfg = VHubLspd.cfg
local E   = VHubLspd.E

local detained = false   -- estado efêmero (UI/física); a verdade vive no servidor


-- ============================================================
-- HELPERS
-- ============================================================

-- carrega um dicionário de animação com timeout (sem loop infinito — L-06)
local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 100 do Citizen.Wait(10); tries = tries + 1 end
    return HasAnimDictLoaded(dict)
end


-- ============================================================
-- DETENÇÃO (entra / sai)
-- ============================================================

-- entra no estado de detido: anima algema + thread que bloqueia controles enquanto preso
local function startDetain(dict, anim)
    if detained then return end
    detained = true

    local ped = PlayerPedId()
    if loadDict(dict) then
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0, false, false, false)
    end

    -- thread BOUNDED: roda só enquanto detained=true (condição de saída explícita, L-06)
    Citizen.CreateThread(function()
        while detained do
            Citizen.Wait(0)
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)  -- atacar
            DisableControlAction(0, 25, true)  -- mirar
            DisableControlAction(0, 47, true)  -- arma
            DisableControlAction(0, 58, true)  -- arma (alt)
            DisableControlAction(0, 23, true)  -- entrar em veículo
            DisableControlAction(0, 21, true)  -- correr
            DisableControlAction(0, 22, true)  -- pular

            local p = PlayerPedId()
            if not IsEntityPlayingAnim(p, dict, anim, 3) then
                TaskPlayAnim(p, dict, anim, 8.0, -8.0, -1, 49, 0, false, false, false)
            end
        end
    end)
end


-- sai do estado de detido: encerra a thread (flag) e limpa a animação
local function stopDetain()
    if not detained then return end
    detained = false
    ClearPedTasks(PlayerPedId())
end


-- ============================================================
-- NET (servidor é a autoridade)
-- ============================================================

RegisterNetEvent(E.DETAIN_APPLY, function(data)
    data = (type(data) == 'table') and data or {}
    startDetain(data.dict or cfg.arrest.dict, data.anim or cfg.arrest.anim)
end)

RegisterNetEvent(E.DETAIN_RELEASE, function() stopDetain() end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if detained then detained = false; ClearPedTasks(PlayerPedId()) end
end)
