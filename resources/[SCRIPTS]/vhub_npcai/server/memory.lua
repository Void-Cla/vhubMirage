---@diagnostic disable: undefined-global
-- memory.lua — escritor único de memória NPC (L-13); VRAM + SQL

VHubNpcAI        = VHubNpcAI or {}
VHubNpcAI.Memory = {}
local Mem        = VHubNpcAI.Memory
local S          = VHubNpcAI.sql


-- ============================================================
-- VRAM CACHE — dois níveis: _cache[charId][npcId] = { [mkey]={val,weight,dirty} }
-- ------------------------------------------------------------
-- Dois níveis (charId → npcId) para que evict(charId) seja O(1) (drop do nó do
-- char) em vez de varredura O(n) por padrão de string em todas as chaves.
-- ============================================================

local _cache = {}  -- evicted por playerDropped ou wipe

-- retorna o nó de um char (cria se preciso)
local function _charNode(charId)
    local node = _cache[charId]
    if not node then node = {}; _cache[charId] = node end
    return node
end

-- retorna (ou cria) o bucket de cache para um par (charId, npcId)
local function _bucket(charId, npcId)
    local node = _charNode(charId)
    local b = node[npcId]
    if not b then b = {}; node[npcId] = b end
    return b
end

-- true se o par já foi carregado do SQL para o cache
local function _isLoaded(charId, npcId)
    local node = _cache[charId]
    return node ~= nil and node[npcId] ~= nil
end


-- ============================================================
-- LOAD (lazy — só vai ao SQL se não estiver em cache)
-- ============================================================

-- carrega memória do SQL para o cache (idempotente)
function Mem.load(charId, npcId)
    if _isLoaded(charId, npcId) then return end  -- já carregado
    local rows = S.loadMemory(charId, npcId)
    _charNode(charId)[npcId] = rows or {}
end


-- ============================================================
-- GET (leitura — retorna tabela shallow copy para o sidecar)
-- ============================================================

-- retorna snapshot plana { [mkey]=mval } para incluir no prompt do LLM
function Mem.get(charId, npcId)
    Mem.load(charId, npcId)
    local bucket   = _bucket(charId, npcId)
    local snapshot = {}
    for k, v in pairs(bucket) do
        snapshot[k] = v.val
    end
    return snapshot
end


-- ============================================================
-- SET (escrita — VRAM + marca dirty para flush)
-- ============================================================

-- aplica delta de memória recebido do sidecar
function Mem.applyDelta(charId, npcId, delta)
    if type(delta) ~= 'table' then return end
    Mem.load(charId, npcId)
    local bucket = _bucket(charId, npcId)
    for mkey, entry in pairs(delta) do
        if type(mkey) == 'string' and #mkey <= 64 then
            local mval   = tostring(entry.val or '')
            local weight = tonumber(entry.weight) or 1
            if #mval <= 255 then
                bucket[mkey] = { val = mval, weight = weight, dirty = true }
                -- persiste imediatamente (memória importante, sem batch)
                S.upsertMemory(charId, npcId, mkey, mval, weight)
            end
        end
    end
end


-- ============================================================
-- EVICT (limpa cache ao deslogar — não apaga SQL) — O(1)
-- ============================================================

function Mem.evict(charId)
    _cache[charId] = nil  -- drop do nó inteiro do char (O(1))
end


-- ============================================================
-- WIPE (apaga SQL + cache — admin only, via exports gateado)
-- ============================================================

function Mem.wipeChar(charId)
    Mem.evict(charId)
    S.wipeCharMemory(charId)
end

function Mem.wipeNpc(charId, npcId)
    local node = _cache[charId]
    if node then node[npcId] = nil end
    S.wipeNpcMemory(charId, npcId)
end
