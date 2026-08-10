---@diagnostic disable: undefined-global
-- playback.lua — reprodução da resposta do NPC (áudio + legenda + lip-sync)

local cfg   = VHubNpcAI.cfg
local E     = VHubNpcAI.E
local state = VHubNpcAI.state


-- ============================================================
-- RESPOSTA DO SERVIDOR — CLI_RESPOSTA
-- ============================================================

RegisterNetEvent(E.CLI_RESPOSTA)
AddEventHandler(E.CLI_RESPOSTA, function(data)
    if type(data) ~= 'table' then return end

    local npcId = data.npc_id
    if not npcId then return end

    -- para gravação se ainda ativa
    state.recording = false
    VHubNpcAI.sendNui(E.NUI_HIDE_REC, {})
    VHubNpcAI.nuiFocusUnlock()

    -- ── lip-sync do NPC ──────────────────────────────────────
    VHubNpcAI.pedStartTalk(npcId)

    -- ── legenda ───────────────────────────────────────────────
    if data.text and #data.text > 0 then
        VHubNpcAI.sendNui(E.NUI_SHOW_CAPTION, {
            nome = data.npc_nome or npcId,
            text = data.text,
        })
    end

    -- ── áudio espacial 3D ────────────────────────────────────
    if data.audio_b64 and #data.audio_b64 > 0 then
        -- NPC agora está falando a resposta → habilita interrupção
        state.npcSpeaking = true
        -- coordenadas do NPC como primitivo para o NUI (L-19)
        VHubNpcAI.sendNui(E.NUI_PLAY_AUDIO, {
            b64    = data.audio_b64,
            npc_x  = data.npc_x or 0,
            npc_y  = data.npc_y or 0,
            npc_z  = data.npc_z or 0,
            murmur = false,
        })
    else
        -- sem áudio: libera conversa imediatamente (audioEnded não vai disparar)
        state.npcSpeaking = false
        VHubNpcAI.pedStopTalk(data.npc_id)
        VHubNpcAI.sendNui(E.NUI_HIDE_CAPTION, {})
        VHubNpcAI.camRelease()
        VHubNpcAI.setConversing(false)
    end
end)


-- ============================================================
-- CALLBACK NUI — fim da reprodução
-- ============================================================

RegisterNUICallback('audioEnded', function(data, cb)
    cb({ ok = true })

    -- interrupção em curso: a fala cortada disparou este audioEnded — ignorar
    -- para não derrubar a NOVA conversa que o jogador acabou de iniciar.
    if state._ignoreAudioEnded then
        state._ignoreAudioEnded = false
        return
    end

    state.npcSpeaking = false

    local npcId = data and data.npc_id or state.nearNpc
    if npcId then
        VHubNpcAI.pedStopTalk(npcId)
    end
    VHubNpcAI.sendNui(E.NUI_HIDE_CAPTION, {})
    VHubNpcAI.camRelease()
    VHubNpcAI.setConversing(false)  -- fim de conversa (resposta concluída)
end)


-- ============================================================
-- THREAD DE ATUALIZAÇÃO DE POSIÇÃO DO JOGADOR (áudio espacial)
-- Budget: 100ms (10Hz) — só quando NUI tem áudio ativo
-- ============================================================

local _audioActive = false

-- NUI avisa quando começa/termina reprodução
RegisterNUICallback('audioStarted', function(_, cb)
    cb({ ok = true }); _audioActive = true
end)
RegisterNUICallback('audioStopped', function(_, cb)
    cb({ ok = true }); _audioActive = false
end)

Citizen.CreateThread(function()
    while true do
        if _audioActive then
            local playerPed  = PlayerPedId()
            local pedCoords  = GetEntityCoords(playerPed, true)
            local fwdVec     = GetEntityForwardVector(playerPed)

            -- primitivos explícitos: vec3 vira {} vazio no json.encode (L-19)
            VHubNpcAI.sendNui('playerPos', {
                x   = pedCoords.x, y = pedCoords.y, z = pedCoords.z,
                fwd = { x = fwdVec.x, y = fwdVec.y },
            })
            Wait(100)
        else
            Wait(cfg.budgets.cold_wait)
        end
    end
end)
