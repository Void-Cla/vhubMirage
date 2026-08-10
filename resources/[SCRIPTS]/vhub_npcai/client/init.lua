---@diagnostic disable: undefined-global
-- init.lua — bootstrap client-side do vhub_npcai

local cfg = VHubNpcAI.cfg
local E   = VHubNpcAI.E

-- estado local (nunca é fonte de verdade crítica — L-02)
VHubNpcAI.state = {
    nuiFocused        = false,
    recording         = false,
    conversing        = false,  -- em conversa com NPC (para ducking voicePMA)
    npcSpeaking       = false,  -- NPC reproduzindo a RESPOSTA agora (habilita interrupção)
    _ignoreAudioEnded = false,  -- guarda contra audioEnded da fala cortada por interrupção
    nearNpc           = nil,    -- id do NPC em proximidade atual (ou nil)
    nearNpcPed        = nil,    -- handle do ped desse NPC
}


-- ============================================================
-- NUI FOCUS — abre/fecha NUI (jamais rouba cursor durante HUD passivo)
-- ============================================================

-- abre overlay NUI sem bloquear câmera (HUD overlay — não input modal)
function VHubNpcAI.nuiOpen()
    if VHubNpcAI.state.nuiFocused then return end
    SetNuiFocus(false, false)  -- overlay passivo: câmera livre, sem cursor
    VHubNpcAI.state.nuiFocused = true
end

-- fecha overlay NUI
function VHubNpcAI.nuiClose()
    if not VHubNpcAI.state.nuiFocused then return end
    SetNuiFocus(false, false)
    VHubNpcAI.state.nuiFocused = false
end

-- abre com foco total (push-to-talk gravando: bloqueia movimento)
function VHubNpcAI.nuiFocusLock()
    SetNuiFocus(true, false)  -- captura input mas sem cursor
    VHubNpcAI.state.nuiFocused = true
end

function VHubNpcAI.nuiFocusUnlock()
    SetNuiFocus(false, false)
    VHubNpcAI.state.nuiFocused = false
end


-- ============================================================
-- HELPER: SEND NUI MESSAGE
-- ============================================================

function VHubNpcAI.sendNui(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end


-- ============================================================
-- INTEGRAÇÃO voicePMA — publica estado de conversa (ducking)
-- ============================================================

-- anuncia início/fim de conversa; consumidor (vhub_voicePMA) escuta CLI_CONVERSING
function VHubNpcAI.setConversing(active)
    if VHubNpcAI.state.conversing == active then return end
    VHubNpcAI.state.conversing = active
    if cfg.voice_integration and cfg.voice_integration.enabled then
        TriggerEvent(E.CLI_CONVERSING, active, cfg.voice_integration.duck_mode)
    end
end
