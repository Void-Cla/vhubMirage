-- mdt.lua — Central de Despacho / MDT (server-authoritative). Entrega BOLOs + scans recentes ao
-- policial (gated por permScan) e gerencia BOLOs pela UI (gated por permManageBolo). REUSA o domínio
-- BOLO (VHubLspd.Bolo) — sem segunda fonte de verdade. Toda decisão crítica é decidida aqui (L-01).

local cfg = VHubLspd.cfg
local E   = VHubLspd.E

local _req = {}   -- [src] = ms — anti-spam do REQ_MDT


-- ============================================================
-- HELPERS
-- ============================================================

-- anti-spam do pedido de MDT (1s por policial)
local function reqThrottle(src)
    local now = GetGameTimer()
    if _req[src] and (now - _req[src]) < 1000 then return true end
    _req[src] = now
    return false
end

-- envia o snapshot do MDT (bolos + scans recentes + se pode gerenciar) ao policial
local function sendData(src)
    local canManage = VHubLspd.hasPerm(src, cfg.police.permManageBolo)
    exports.oxmysql:query(
        'SELECT plate, flagged, src_kind, created_at FROM vhub_lspd_scans ORDER BY id DESC LIMIT ?',
        { cfg.mdt.scanLimit },
        function(rows)
            TriggerClientEvent(E.MDT_DATA, src, {
                bolos     = (VHubLspd.Bolo and VHubLspd.Bolo.list()) or {},
                scans     = rows or {},
                canManage = canManage,
                levels    = cfg.bolo.levels,
            })
        end
    )
end


-- ============================================================
-- NET (entrada hostil — permissão + sanitização server-side)
-- ============================================================

-- pedido de abertura do MDT — só responde a policiais (permScan)
RegisterNetEvent(E.REQ_MDT, function()
    local src = source
    if reqThrottle(src) then return end
    if not VHubLspd.hasPerm(src, cfg.police.permScan) then return end   -- silencioso (L-01)
    sendData(src)
end)

-- criar BOLO pela UI (gated permManageBolo; a sanitização final mora no domínio Bolo)
RegisterNetEvent(E.MDT_ADD, function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not VHubLspd.hasPerm(src, cfg.police.permManageBolo) then
        VHubLspd.notify(src, 'Sem permissao para criar BOLO.')
        return
    end

    local plate = VHubLspd.normalizePlate(data.plate)
    if not (plate and VHubLspd.Bolo) then return end

    local reason = tostring(data.reason or ''):gsub('[%c]', ''):sub(1, cfg.bolo.reasonMaxLen)
    if reason == '' then reason = 'Sem motivo informado' end

    -- clampa o nível ao range válido de cfg.bolo.levels (entrada do cliente é hostil)
    local level = tonumber(data.level)
    if level then level = math.max(1, math.min(#cfg.bolo.levels, math.floor(level))) end

    local ok = VHubLspd.Bolo.create(VHubLspd.getUid(src), plate, reason, level)
    VHubLspd.notify(src, ok and ('BOLO criado: %s'):format(plate)
                              or 'BOLO nao criado (ja existe ou limite atingido).')
    sendData(src)   -- refresca o painel do solicitante
end)

-- remover BOLO pela UI (gated permManageBolo)
RegisterNetEvent(E.MDT_DEL, function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not VHubLspd.hasPerm(src, cfg.police.permManageBolo) then
        VHubLspd.notify(src, 'Sem permissao para remover BOLO.')
        return
    end

    local plate = VHubLspd.normalizePlate(data.plate)
    if not (plate and VHubLspd.Bolo) then return end

    local ok = VHubLspd.Bolo.remove(plate)
    VHubLspd.notify(src, ok and ('BOLO removido: %s'):format(plate)
                              or 'Nenhum BOLO ativo para essa placa.')
    sendData(src)
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('playerDropped', function() _req[source] = nil end)
