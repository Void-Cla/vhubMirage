---@diagnostic disable: undefined-global, lowercase-global

-- server/grid.lua — geometria de largada (grid + ready-zone).
--
-- Responsabilidade unica: TUDO que envolve coordenada de start, slot de
-- grid, e verificacao "o player esta na ready-zone do totem?".
--
-- Extraido de lobby.lua para isolar concerns geometricos da maquina de
-- estados. Lobby orquestra; Grid mede.
--
-- API publica:
--   Grid.compute_ready_zone(track) → { x, y, z, radius, z_tol }
--   Grid.in_ready_zone(src, zone)  → bool
--   Grid.alloc_slot(inst)          → number | nil
--   Grid.free_slot(inst, slot)


VHubRachaGrid = {}
local G   = VHubRachaGrid
local Cfg = VHubRachaCfg
local MA  = VHubRachaMath


-- ============================================================
-- READY ZONE — area circular ao redor do start onde o player
-- precisa estar para confirmar presenca no totem.
-- ============================================================

-- Calcula a ready-zone para uma track. Aceita override em track.ready_zone.
function G.compute_ready_zone(track)
    local cfg = Cfg.READY_ZONE or {}
    local s   = (track and track.start) or { x = 0, y = 0, z = 0 }

    -- Override por track (track.ready_zone tem precedencia)
    if track and type(track.ready_zone) == 'table' then
        return {
            x      = tonumber(track.ready_zone.x)      or s.x,
            y      = tonumber(track.ready_zone.y)      or s.y,
            z      = tonumber(track.ready_zone.z)      or s.z,
            radius = tonumber(track.ready_zone.radius) or (cfg.RADIUS_M    or 18.0),
            z_tol  = tonumber(track.ready_zone.z_tol)  or (cfg.Z_TOLERANCE or 5.0),
        }
    end

    -- Default: centrada no start da pista
    return {
        x      = s.x, y = s.y, z = s.z,
        radius = cfg.RADIUS_M    or 18.0,
        z_tol  = cfg.Z_TOLERANCE or 5.0,
    }
end


-- Verifica se o ped do player esta dentro da ready-zone (X-Y dentro do raio
-- e Z dentro da tolerancia vertical). Server-authoritative — usa native
-- GetEntityCoords no servidor (zero confianca no cliente).
function G.in_ready_zone(src, zone)
    if not zone then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local pos = GetEntityCoords(ped)
    if not pos then return false end

    if math.abs(pos.z - zone.z) > (zone.z_tol or 5.0) then return false end

    return MA.point_in_circle(pos.x, pos.y, zone.x, zone.y, zone.radius or 18.0)
end


-- ============================================================
-- SLOTS — alocacao de posicao de largada na grid.
-- ============================================================

-- Aloca o proximo slot livre (1..max_players). Retorna nil se esgotado.
-- Marca como ocupado pelo src dentro de inst.grid_used.
function G.alloc_slot(inst)
    local max = (inst.max_players or 8)

    for i = 1, max do
        if not inst.grid_used[i] then
            return i
        end
    end

    return nil
end


-- Libera slot ocupado por um player que saiu do lobby.
function G.free_slot(inst, slot)
    if not slot then return end
    inst.grid_used[slot] = nil
end


-- Retorna a coordenada de spawn correspondente ao slot do player. Cai para
-- o start da track se a track nao tiver grid explicita.
function G.spawn_for(track, slot)
    if track.grid and track.grid[slot] then
        return track.grid[slot]
    end
    return track.start
end
