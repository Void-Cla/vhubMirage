---@diagnostic disable: undefined-global, lowercase-global

-- client/cache.lua — cache LOCAL de replays baixados (KVP).
--
-- On-demand: a LISTA vem do servidor (/replays); ao assistir, baixa o .vhr 1x e
-- guarda aqui (string bruta) p/ nao rebaixar. Mantem os ultimos N (evict FIFO).

VRCS = VRCS or {}

local Cfg = VRCS.Cfg

local C = {}; VRCS.Cache = C

local IDX_KEY = 'vrcs:dl_index'
local function rp_key(rid) return 'vrcs:rp:' .. tostring(rid) end


-- ============================================================
-- INDICE
-- ============================================================

local function read_index()
    local raw = GetResourceKvpString(IDX_KEY)
    if not raw or raw == '' then return {} end
    local ok, t = pcall(json.decode, raw)
    return (ok and type(t) == 'table') and t or {}
end

local function write_index(list)
    SetResourceKvp(IDX_KEY, json.encode(list))
end


-- ============================================================
-- API
-- ============================================================

-- guarda o .vhr BRUTO (string) baixado; mantem os ultimos N (evict FIFO)
function C.save_raw(rid, data)
    if type(rid) ~= 'string' or type(data) ~= 'string' then return end
    SetResourceKvp(rp_key(rid), data)

    local list = read_index()
    for i = #list, 1, -1 do
        if list[i] == rid then table.remove(list, i) end
    end
    table.insert(list, 1, rid)

    local cap = (Cfg.VIEWER and Cfg.VIEWER.CACHE_MAX) or 5
    while #list > cap do
        local old = table.remove(list)
        if old then DeleteResourceKvp(rp_key(old)) end
    end
    write_index(list)
end


-- replay esta no cache local?
function C.has(rid)
    local raw = GetResourceKvpString(rp_key(rid))
    return raw ~= nil and raw ~= ''
end


-- retorna o replay DECODIFICADO do cache (ou nil)
function C.get(rid)
    local raw = GetResourceKvpString(rp_key(rid))
    if not raw or raw == '' then return nil end
    local ok, t = pcall(json.decode, raw)
    return (ok and type(t) == 'table') and t or nil
end
