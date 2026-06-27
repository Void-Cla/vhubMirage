---@diagnostic disable: undefined-global, lowercase-global

-- server/library.lua — biblioteca de replays: LISTA (DB) + DOWNLOAD sob demanda.
--
-- O /replays nao recebe mais push: o client pede a lista e baixa o .vhr so quando
-- vai assistir. Rate-limit por origem + cleanup em playerDropped.

VRCS = VRCS or {}

local Cfg = VRCS.Cfg

local _rl = {}   -- src -> ultimo ms (anti-spam)


-- true se a origem estourou o intervalo minimo entre acoes
local function throttled(src, gap)
    local now  = GetGameTimer()
    local last = _rl[src] or 0
    if now - last < (gap or 1000) then return true end
    _rl[src] = now
    return false
end


-- ============================================================
-- LISTA — metadados dos replays recentes (sem os frames)
-- ============================================================

RegisterNetEvent('vhub_vrcs:list')
AddEventHandler('vhub_vrcs:list', function()
    local src = source
    if throttled(src, 1000) then return end

    local lim = Cfg.LIBRARY_LIMIT or 50
    exports.oxmysql:query(
        'SELECT race_id, track_id, kind, duration_s, players_n, created_at ' ..
        'FROM vh_race_replays ORDER BY created_at DESC LIMIT ?',
        { lim },
        function(rows)
            TriggerClientEvent('vhub_vrcs:list:result', src, rows or {})
        end)
end)


-- ============================================================
-- DOWNLOAD — entrega o .vhr bruto (string) por race_id
-- ============================================================

RegisterNetEvent('vhub_vrcs:fetch')
AddEventHandler('vhub_vrcs:fetch', function(rid)
    local src = source
    if type(rid) ~= 'string' or not VRCS.Schema.is_uuid(rid) then return end   -- anti traversal
    if throttled(src, 1500) then return end

    local path = ('%s/%s.vhr'):format(Cfg.REPLAY_DIR or 'replays', rid)
    local data = LoadResourceFile(GetCurrentResourceName(), path)              -- nil se nao existir
    TriggerClientEvent('vhub_vrcs:fetch:result', src, rid, data)
end)


AddEventHandler('playerDropped', function()
    _rl[source] = nil
end)
