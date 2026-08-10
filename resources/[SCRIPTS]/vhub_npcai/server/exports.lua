---@diagnostic disable: undefined-global
-- exports.lua — API pública gated do vhub_npcai (export-first, L-07, L-13)

local Core  = VHubNpcAI.Core
local Mem   = VHubNpcAI.Memory
local Relay = VHubNpcAI.Relay
local cfg   = VHubNpcAI.cfg

-- verifica se o resource invocador tem permissão (default-deny)
local function _allowed()
    local invoker = GetInvokingResource()
    if not invoker then return true end  -- chamada interna (console/server)
    local trusted = GetConvar('vhub_trusted_resources', '')
    for res in trusted:gmatch('[^,]+') do
        if res:match('^%s*(.-)%s*$') == invoker then return true end
    end
    return false
end


-- ============================================================
-- LEITURA DE MEMÓRIA
-- ============================================================

-- retorna snapshot de memória de um par char×npc (gated)
exports('getNpcMemory', function(charId, npcId)
    if not _allowed() then return nil end
    if type(charId) ~= 'number' or type(npcId) ~= 'string' then return nil end
    return Mem.get(charId, npcId)
end)


-- ============================================================
-- ESCRITA DE MEMÓRIA (L-13 — escritor único)
-- ============================================================

-- aplica delta de memória externamente (gated — só resources confiáveis)
exports('setNpcMemory', function(charId, npcId, delta)
    if not _allowed() then return false end
    if type(charId) ~= 'number' or type(npcId) ~= 'string' then return false end
    if type(delta) ~= 'table' then return false end
    Mem.applyDelta(charId, npcId, delta)
    return true
end)

-- apaga toda memória de um personagem (admin only)
exports('wipeCharMemory', function(charId)
    if not _allowed() then return false end
    if type(charId) ~= 'number' then return false end
    Mem.wipeChar(charId)
    return true
end)

-- apaga memória de um par char×npc (admin only)
exports('wipeNpcMemory', function(charId, npcId)
    if not _allowed() then return false end
    if type(charId) ~= 'number' or type(npcId) ~= 'string' then return false end
    Mem.wipeNpc(charId, npcId)
    return true
end)


-- ============================================================
-- LISTAGEM
-- ============================================================

-- lista NPCs configurados (id, nome, coords primitivas, raio)
exports('listNpcs', function()
    if not _allowed() then return nil end
    local out = {}
    for id, npc in pairs(cfg.npcs) do
        out[#out+1] = {
            id        = id,
            nome      = npc.nome,
            profissao = npc.profissao,
            x         = npc.coords.x,
            y         = npc.coords.y,
            z         = npc.coords.z,
            raio      = npc.raio,
        }
    end
    return out
end)

-- lista srcs com sessão NPC ativa
exports('listActiveSrcs', function()
    if not _allowed() then return nil end
    return Core.listActiveSrcs()
end)


-- ============================================================
-- ADMINISTRAÇÃO
-- ============================================================

-- recarrega configs de NPC no sidecar Python sem restart
exports('reloadNpcConfig', function()
    if not _allowed() then return false end
    Relay.reloadNpcs(function(ok, data)
        if ok then
            VHubNpcAI.Log.info('sidecar recarregado')
        else
            VHubNpcAI.Log.warn('reload falhou: ' .. tostring(data and data.err))
        end
    end)
    return true
end)

-- health check do sidecar (admin, assíncrono — result chega via Logger)
exports('sidecarHealth', function()
    if not _allowed() then return false end
    Relay.health(function(ok, data)
        VHubNpcAI.Log.info('health=' .. tostring(ok) .. ' ' .. json.encode(data))
    end)
    return true
end)
