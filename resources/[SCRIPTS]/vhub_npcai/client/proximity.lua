---@diagnostic disable: undefined-global
-- proximity.lua — detecção de proximidade e hint "[G] Falar" (cold/warm threads)
-- Budget: cold 1Hz (1000ms), warm 10Hz (100ms) — L-18

local cfg   = VHubNpcAI.cfg
local E     = VHubNpcAI.E
local state = VHubNpcAI.state
local U     = VHubNpcAI.utils


-- ============================================================
-- GREET AMBIENTAL — cue sonoro pré-cacheado ao chegar perto do NPC
-- ------------------------------------------------------------
-- Reusa os WAVs nui/audio/greet/<npc>/greet_default_NN.wav (já no fxmanifest).
-- Zero STT, zero sidecar: toca localmente. Cooldown evita spam ao entrar/sair.
-- ============================================================

local GREET_COUNT    = 2       -- greet_default_00 / _01 por NPC
local GREET_COOLDOWN = 300000  -- 5 min: só re-cumprimenta após ausência longa
local _greetTs = {}            -- npcId → último greet (ms)

-- toca o cumprimento local do NPC (se não estiver em conversa e fora do cooldown)
local function _maybeGreet(npcId)
    if not npcId then return end
    if state.conversing or state.recording then return end

    local now  = GetGameTimer()
    local last = _greetTs[npcId] or 0
    if (now - last) < GREET_COOLDOWN then return end
    _greetTs[npcId] = now

    local idx = math.random(0, GREET_COUNT - 1)
    local src = ('audio/greet/%s/greet_default_%02d.wav'):format(npcId, idx)

    VHubNpcAI.pedStartTalk(npcId)
    VHubNpcAI.sendNui(E.NUI_PLAY_AUDIO, { src = src, murmur = true })
    -- encerra o lip-sync do cumprimento (murmur não dispara audioEnded)
    Citizen.SetTimeout(1600, function() VHubNpcAI.pedStopTalk(npcId) end)
end


-- ============================================================
-- COLD THREAD — 1Hz, detecta proximidade (marca flag)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local px, py, pz = table.unpack(GetEntityCoords(playerPed, true))

        local closest     = nil
        local closestDist = math.huge

        for id, npc in pairs(cfg.npcs) do
          if npc.enabled then
            local nc = npc.coords
            local d  = U.dist3(px, py, pz, nc.x, nc.y, nc.z)
            if d < npc.raio and d < closestDist then
                -- LOS exige que o ped do NPC EXISTA (senão o alvo cairia no próprio
                -- player → HasEntityClearLosToEntity(self,self) sempre true — bug).
                local npcPed = VHubNpcAI.getPed(id)
                local losOk  = (not cfg.los_required)
                            or (npcPed ~= nil and HasEntityClearLosToEntity(playerPed, npcPed, 17))
                if losOk then
                    closest     = id
                    closestDist = d
                end
            end
          end
        end

        local prev = state.nearNpc
        state.nearNpc = closest

        -- transição entrou no raio de um NPC novo → cumprimento ambiental
        if closest and closest ~= prev then
            _maybeGreet(closest)
        end

        -- transição saiu do raio → cancela look-at do NPC anterior
        if prev and prev ~= closest then
            VHubNpcAI.pedLookReset(prev)
        end

        Wait(cfg.budgets.cold_wait)
    end
end)


-- ============================================================
-- WARM THREAD — 10Hz, só quando near (head tracking)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        local npcId = state.nearNpc

        if npcId then
            -- head tracking: NPC olha para o jogador
            VHubNpcAI.pedLookAtPlayer(npcId)

            Wait(cfg.budgets.warm_wait)
        else
            -- sem NPC próximo: suspende thread quente barata
            Wait(cfg.budgets.cold_wait)
        end
    end
end)
