-- events.lua — constantes de evento do vhub_npcai (global, sem return — anti-fantasma)

VHubNpcAI     = VHubNpcAI or {}
VHubNpcAI.E   = {

    -- ============================================================
    -- SERVER-SIDE (cliente → servidor)
    -- ============================================================

    SRV_FALAR    = 'vhub_npcai:server:Falar',     -- jogador envia áudio + npc_id
    SRV_CANCEL   = 'vhub_npcai:server:Cancelar',  -- jogador cancela (saiu do raio)
    SRV_RESERVAR = 'vhub_npcai:server:Reservar',  -- reserva o NPC ao começar a gravar (warm handoff)


    -- ============================================================
    -- CLIENT-SIDE (servidor → cliente)
    -- ============================================================

    CLI_RESPOSTA       = 'vhub_npcai:client:Resposta',       -- áudio de resposta + metadados
    CLI_MURMUR         = 'vhub_npcai:client:Murmur',         -- murmúrio antecipado (reservado)
    CLI_REJECT         = 'vhub_npcai:client:Rejeitado',      -- fala rejeitada (rate, distância, HSS)


    -- ============================================================
    -- INTEGRAÇÃO (client-local) — contrato para vhub_voicePMA (ducking)
    -- ============================================================

    -- emitido no cliente quando a conversa com NPC começa/termina (bool).
    -- O vhub_voicePMA (ou qualquer resource) pode escutar para abaixar rádio/voz.
    CLI_CONVERSING = 'vhub_npcai:conversing',


    -- ============================================================
    -- NUI (SendNUIMessage keys)
    -- ============================================================

    NUI_SHOW_HINT    = 'showHint',    -- mostra "[G] Falar com <nome>"
    NUI_HIDE_HINT    = 'hideHint',    -- esconde dica
    NUI_SHOW_REC     = 'showRec',     -- mostra VU + "Gravando..."
    NUI_HIDE_REC     = 'hideRec',     -- esconde gravação
    NUI_PLAY_AUDIO   = 'playAudio',   -- reproduz áudio com posição 3D
    NUI_STOP_AUDIO   = 'stopAudio',   -- para reprodução
    NUI_SHOW_CAPTION = 'showCaption', -- legenda da fala do NPC
    NUI_HIDE_CAPTION = 'hideCaption', -- esconde legenda
    NUI_VU_LEVEL     = 'vuLevel',     -- nível do VU meter (0.0–1.0)

}
