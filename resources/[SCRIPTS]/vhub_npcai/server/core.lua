---@diagnostic disable: undefined-global
-- core.lua — sessões, rate-limit e validações server-side do vhub_npcai

VHubNpcAI      = VHubNpcAI or {}
VHubNpcAI.Core = {}
local Core     = VHubNpcAI.Core
local cfg      = VHubNpcAI.cfg


-- ============================================================
-- SESSIONS — estado por jogador (limpas em playerDropped)
-- ============================================================

-- sessions[src] = { charId, charName, talking=false, lastTalk=0, lastMem=0, lastAudit=0 }
local sessions = {}

-- inicia sessão para um src (chamado em characterLoad)
function Core.openSession(src, charId, charName)
    sessions[src] = {
        charId    = charId,
        charName  = charName,
        talking   = false,
        lastTalk  = 0,
        lastMem   = 0,
        lastAudit = 0,
    }
end

-- encerra sessão (playerDropped / characterUnload)
function Core.closeSession(src)
    sessions[src] = nil
end

-- retorna sessão ou nil
function Core.getSession(src)
    return sessions[src]
end

-- marca/desmarca flag de fala ativa (lock por NPC — impede dupla conversa)
function Core.setTalking(src, value)
    local s = sessions[src]
    if s then s.talking = value end
end

-- lista todos os srcs com sessão ativa (para exportar)
function Core.listActiveSrcs()
    local out = {}
    for src in pairs(sessions) do out[#out+1] = src end
    return out
end


-- ============================================================
-- RATE-LIMIT (O(1), ms monotônico — manual_dev_vhub §4.4)
-- ============================================================

-- verifica e consome rate-limit; retorna true se passou, false se bloqueado
function Core.rate(src, key, limitMs)
    local s = sessions[src]
    if not s then return false end
    local field  = 'rate_' .. key
    local now    = GetGameTimer()
    local last   = s[field] or 0
    if (now - last) < limitMs then return false end
    s[field] = now
    return true
end


-- ============================================================
-- GATE HSS — verifica se char_id pode falar (não está inconsciente/algemado)
-- ============================================================

-- retorna true se o HSS reportar que o jogador está livre para interagir.
-- Gate real (isConscious + isHandcuffed — leitura aberta do vhub_hss). O antigo
-- canInteract nunca existiu no HSS (pcall sempre falhava → fail-open silencioso).
-- Agora é FAIL-CLOSED: HSS indisponível (reiniciando) = sem fala. Perda temporária
-- de funcionalidade é aceitável; degradação de segurança não é (L-01).
function Core.canTalk(src)
    local s = sessions[src]
    if not s then return false end
    if s.talking then return false end  -- já falando

    -- consciente? (export falhando OU estado desconhecido = fail-closed estrito)
    local okC, conscious = pcall(function() return exports.vhub_hss:isConscious(src) end)
    if not okC or conscious ~= true then return false end  -- só true consciente passa

    -- algemado? (export falhando = fail-closed)
    local okH, cuffed = pcall(function() return exports.vhub_hss:isHandcuffed(src) end)
    if not okH then return false end
    if cuffed == true then return false end                -- algemado não fala

    return true
end


-- ============================================================
-- VALIDAÇÃO DE PAYLOAD DO CLIENTE
-- ============================================================

-- true se `text` for EXATAMENTE um dos direct_text declarados no target_options do NPC
function Core.isAllowedDirectText(npcId, text)
    local npc = cfg.npcs[npcId]
    if not npc or type(npc.target_options) ~= 'table' then return false end
    for _, opt in ipairs(npc.target_options) do
        if opt.direct_text ~= nil and opt.direct_text == text then
            return true
        end
    end
    return false
end

-- valida shape e conteúdo do payload SRV_FALAR (aceita áudio OU texto direto via target)
function Core.validateFalarPayload(payload)
    if type(payload) ~= 'table' then return false, 'payload_invalido' end

    local npcId = payload.npc_id
    if type(npcId) ~= 'string' or #npcId < 1 or #npcId > 48 then
        return false, 'npc_id_invalido'
    end
    -- slug seguro: apenas [a-z0-9_]
    if npcId:find('[^a-z0-9_]') then return false, 'npc_id_invalido' end
    -- npc_id deve estar no cfg
    if not cfg.npcs[npcId] then return false, 'npc_desconhecido' end

    local audio      = payload.audio
    local directText = payload.direct_text

    if directText ~= nil then
        -- caminho via target: texto pré-definido, skip do STT
        if type(directText) ~= 'string' or #directText < 1 or #directText > 300 then
            return false, 'direct_text_invalido'
        end
        -- ZERO-TRUST: direct_text pula o STT e vira intenção — precisa ser EXATAMENTE
        -- uma das opções declaradas no target_options deste NPC (servidor é o dono da
        -- whitelist). Impede o cliente de injetar texto arbitrário como intenção válida.
        if not Core.isAllowedDirectText(npcId, directText) then
            return false, 'direct_text_nao_autorizado'
        end
    elseif audio ~= nil then
        -- caminho via microfone: áudio base64 webm
        if type(audio) ~= 'string' then return false, 'audio_invalido' end
        if #audio < 10             then return false, 'audio_curto'    end
        if #audio > 270000         then return false, 'audio_longo'    end
    else
        return false, 'sem_audio_ou_texto'
    end

    return true, nil
end


-- ============================================================
-- VALIDAÇÃO DE PROXIMIDADE SERVER-SIDE (L-01)
-- ============================================================

-- valida que src está dentro do raio do npc (autoridade servidor)
function Core.validateProximity(src, npcId)
    local npc = cfg.npcs[npcId]
    if not npc then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local coords = GetEntityCoords(ped)
    local px, py, pz = coords.x, coords.y, coords.z
    local nc = npc.coords
    local U  = VHubNpcAI.utils
    local d  = U.dist3(px, py, pz, nc.x, nc.y, nc.z)

    -- tolerância +20% para lag de rede
    return d <= (npc.raio * 1.2)
end
