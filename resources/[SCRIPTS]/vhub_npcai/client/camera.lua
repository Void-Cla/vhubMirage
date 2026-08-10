---@diagnostic disable: undefined-global
-- camera.lua — câmera cinematic over-the-shoulder durante conversa com NPC

-- câmera desativada por decisão de UX (conversa natural sem prender câmera do jogador).
-- Mantém assinatura para compatibilidade com chamadas existentes em mic.lua e playback.lua.

-- no-op: câmera scripted removida
function VHubNpcAI.camFocusNpc(_) end

-- no-op: sem câmera scripted para soltar
function VHubNpcAI.camRelease() end
