---@diagnostic disable: undefined-global
-- mic.lua — captura de áudio e despacho de intenção ao servidor

local cfg   = VHubNpcAI.cfg
local E     = VHubNpcAI.E
local state = VHubNpcAI.state

-- debounce (evita disparos duplos via target)
local _lastPush = 0
-- flag de gravação em curso
local _recording = false
-- marca que a próxima fala é uma interrupção (viaja até o micAudioReady)
local _pendingInterrupt = false


-- ============================================================
-- API PÚBLICA — chamada pelo vhub_target ao selecionar opção
-- ============================================================

-- inicia conversa com npcId; directText=nil abre o microfone, string envia direto ao servidor
function VHubNpcAI.startTalk(npcId, directText)
    if not npcId or _recording then return end

    -- interrupção: só reentra se o NPC está de fato FALANDO a resposta; senão
    -- (pensando/aguardando) ignora o disparo duplo.
    local interrupting = false
    if state.conversing then
        if not state.npcSpeaking then return end
        interrupting          = true
        state.npcSpeaking     = false
        state._ignoreAudioEnded = true
        VHubNpcAI.sendNui(E.NUI_STOP_AUDIO, {})
        VHubNpcAI.pedStopTalk(npcId)
        VHubNpcAI.sendNui(E.NUI_HIDE_CAPTION, {})
        -- rede de segurança: se o audioEnded cortado não chegar, não engole o próximo
        Citizen.SetTimeout(500, function() state._ignoreAudioEnded = false end)
    end

    local now = GetGameTimer()
    if (now - _lastPush) < cfg.rates.push then return end
    _lastPush = now

    VHubNpcAI.setConversing(true)

    -- toca thinking WAV local do NPC (murmur=true → não bloqueia audioEnded)
    -- WAVs gerados por sidecar/gerar_audio_npcs.py; contagem deriva do JSON do NPC
    do
        local npcCfg  = cfg.npcs[npcId]
        local count   = npcCfg and #(npcCfg.thinking_frases or {}) or 0
        if count > 0 then
            local idx = math.random(0, count - 1)
            local src = ('audio/thinking/%s/thinking_%02d.wav'):format(npcId, idx)
            VHubNpcAI.pedStartTalk(npcId)
            VHubNpcAI.sendNui(E.NUI_PLAY_AUDIO, { src = src, murmur = true })
        end
    end

    if directText then
        -- intenção pré-definida: envia texto direto sem abrir microfone
        TriggerServerEvent(E.SRV_FALAR, {
            npc_id      = npcId,
            direct_text = directText,
            interrupted = interrupting or nil,
        })
    else
        -- warm handoff: reserva o NPC ANTES do upload (server nega cedo se ocupado)
        TriggerServerEvent(E.SRV_RESERVAR, { npc_id = npcId })
        -- fala livre: abre gravação de microfone
        _pendingInterrupt = interrupting
        _recording        = true
        state.recording   = true
        VHubNpcAI.sendNui(E.NUI_SHOW_REC, { max_ms = cfg.talk_max_ms })
    end
end


-- ============================================================
-- CALLBACK NUI — recebe base64 do MediaRecorder
-- ============================================================

RegisterNUICallback('micAudioReady', function(data, cb)
    cb({ ok = true })

    if not _recording then return end

    local audio = data and data.audio
    local npcId = state.nearNpc

    _recording      = false
    state.recording = false
    VHubNpcAI.sendNui(E.NUI_HIDE_REC, {})

    local interrupting  = _pendingInterrupt
    _pendingInterrupt   = false

    if type(audio) ~= 'string' or #audio < 10 or not npcId then
        VHubNpcAI.setConversing(false)
        return
    end

    TriggerServerEvent(E.SRV_FALAR, {
        npc_id      = npcId,
        audio       = audio,
        interrupted = interrupting or nil,
    })
end)

-- callback de erro ou cancelamento do recorder
RegisterNUICallback('micError', function(data, cb)
    cb({ ok = true })
    _recording      = false
    state.recording = false
    VHubNpcAI.sendNui(E.NUI_HIDE_REC, {})
    VHubNpcAI.setConversing(false)
    VHubNpcAI.Log.warn('mic error: ' .. tostring(data and data.err))
end)


-- ============================================================
-- REJECT DO SERVIDOR
-- ============================================================

RegisterNetEvent(E.CLI_REJECT)
AddEventHandler(E.CLI_REJECT, function(data)
    _recording      = false
    state.recording = false
    VHubNpcAI.setConversing(false)
    VHubNpcAI.sendNui(E.NUI_HIDE_REC, {})
    VHubNpcAI.camRelease()

    local npcId = state.nearNpc
    if npcId then VHubNpcAI.pedStopTalk(npcId) end

    local reason = data and data.reason or 'unknown'
    local detail = data and data.detail
    if type(detail) == 'string' and #detail > 0 then
        reason = reason .. ' (' .. detail:sub(1, 64) .. ')'
    end
    VHubNpcAI.Log.warn('reject: ' .. reason)
end)
