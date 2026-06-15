-- main.lua — LSPD Tool server-authoritative (camada L1/Kernel do resource)
-- Pipeline de scan: autorização do policial -> validação da placa -> anti-flood -> dedup
--   -> coords autênticas -> checagem de BOLO (nativo) -> alerta às unidades -> auditoria.
-- Também: helpers compartilhados (perm/plate/uid/log/notify) e radar automático.
-- Verdade crítica (quem é policial, onde está, se há BOLO) é sempre decidida no servidor.

local cfg = VHubLspd.cfg
local E   = VHubLspd.E


-- ============================================================
-- LOGGER
-- ============================================================
-- Definido em shared/logger.lua (único arquivo do resource com print() — L-08).

local Log = VHubLspd.Log


-- ============================================================
-- STATE (caches em memória — sem segunda fonte de verdade)
-- ============================================================

local _perm  = {}  -- [src]   = { val = bool, exp = ms }   permissão de scan cacheada
local _rate  = {}  -- [src]   = { last, windowStart, count } anti-flood por policial
local _dedup = {}  -- [plate] = ms (último processamento)     dedup global por placa
local _radarReq = {}  -- [src]  = ms (último pedido de radar)  anti-spam do REQ_RADAR


-- ============================================================
-- HELPERS COMPARTILHADOS (expostos em VHubLspd.*)
-- ============================================================

-- retorna o uid do player ou nil (pcall — exports do core podem não estar prontos)
function VHubLspd.getUid(src)
    local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
    return (ok and type(uid) == 'number') and uid or nil
end


-- envia uma notificação de texto simples ao policial (thefeed no cliente)
function VHubLspd.notify(src, msg)
    if src and tonumber(src) and tonumber(src) > 0 then
        TriggerClientEvent(E.NOTIFY, src, tostring(msg or ''))
    end
end


local _platePattern = '^[' .. cfg.plate.charset .. ']+$'

-- normaliza e valida a placa (uppercase, trim, charset, tamanho); nil se inválida
function VHubLspd.normalizePlate(raw)
    if type(raw) ~= 'string' then return nil end

    local p = raw:upper():gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')

    if #p < cfg.plate.minLen or #p > cfg.plate.maxLen then return nil end
    if not p:match(_platePattern) then return nil end

    return p
end


-- verdade de permissão (owner -> ACE -> grupo -> duty opcional), tudo sob pcall — sem cache
function VHubLspd.hasPerm(src, perm)
    if cfg.police.ownerBypass and VHubLspd.getUid(src) == 1 then return true end

    if cfg.police.acePermission and IsPlayerAceAllowed(src, cfg.police.acePermission) then
        return true
    end

    local okG, allowed = pcall(function()
        return exports.vhub_groups:hasPermission(src, perm)
    end)
    if not (okG and allowed == true) then return false end

    if cfg.police.dutyExport then
        local d = cfg.police.dutyExport
        local okD, onDuty = pcall(function() return exports[d.resource][d.fn](src) end)
        return okD and onDuty == true
    end

    return true
end


-- whitelist de invocadores para exports mutadores (chamada local = ok)
function VHubLspd.invokerAllowed()
    local r = GetInvokingResource()
    if not r then return true end
    return cfg.trusted[r] == true
end


-- entrega um evento direcionado a cada policial em serviço (nunca broadcast -1).
-- Reaproveitado por BOLO/procurados/dispatch. Retorna nº de unidades alcançadas.
function VHubLspd.dispatchUnits(event, payload)
    local ok, units = pcall(function()
        return exports.vhub_groups:getUsersByPermission(cfg.police.permScan)
    end)
    if not ok or type(units) ~= 'table' then return 0 end

    local sent = 0
    for _, dst in ipairs(units) do
        dst = tonumber(dst)
        if dst and dst > 0 and GetPlayerName(dst) then
            TriggerClientEvent(event, dst, payload)
            sent = sent + 1
        end
    end
    return sent
end


-- resolve o char_id do personagem ativo do src (verdade do core; nil se não carregado)
function VHubLspd.getCharId(src)
    local ok, user = pcall(function() return exports.vhub:getUser(src) end)
    return (ok and user and tonumber(user.char_id)) or nil
end


-- ============================================================
-- AUTORIZAÇÃO DE SCAN (cache com TTL no caminho quente)
-- ============================================================

-- retorna se o src pode operar o radar/scan, usando cache com TTL (invalida em group change/drop)
local function canScan(src)
    local now = GetGameTimer()
    local c   = _perm[src]
    if c and now < c.exp then return c.val end

    local val = VHubLspd.hasPerm(src, cfg.police.permScan)
    _perm[src] = { val = val, exp = now + cfg.police.cacheTtlMs }
    return val
end


-- ============================================================
-- ANTI-FLOOD + DEDUP
-- ============================================================

-- aplica intervalo mínimo e teto por minuto para um policial; true se o scan é aceito
local function rateOk(src)
    local now = GetGameTimer()
    local r   = _rate[src]
    if not r then r = { last = 0, windowStart = now, count = 0 }; _rate[src] = r end

    if (now - r.last) < cfg.rate.minIntervalMs then return false end
    if (now - r.windowStart) >= 60000 then r.windowStart = now; r.count = 0 end
    if r.count >= cfg.rate.maxPerMinute then return false end

    r.last  = now
    r.count = r.count + 1
    return true
end


-- dedup global por placa com GC preguiçoso (sem thread); true se a placa pode ser processada
local function dedupOk(plate)
    local now = GetGameTimer()

    for p, ts in pairs(_dedup) do
        if (now - ts) >= cfg.dedupTtlMs then _dedup[p] = nil end
    end

    if _dedup[plate] and (now - _dedup[plate]) < cfg.dedupTtlMs then return false end

    _dedup[plate] = now
    return true
end


-- ============================================================
-- DISPATCH (broadcast nativo às unidades policiais online)
-- ============================================================

-- entrega o alerta de BOLO a cada policial em serviço (evento direcionado, nunca broadcast geral)
local function broadcastAlert(plate, coords, bolo, kind)
    local ok, units = pcall(function()
        return exports.vhub_groups:getUsersByPermission(cfg.police.permScan)
    end)
    if not ok or type(units) ~= 'table' then return 0 end

    local payload = {
        plate  = plate,
        coords = coords,
        reason = bolo.reason,
        level  = bolo.level,
        kind   = kind,
    }

    local sent = 0
    for _, dst in ipairs(units) do
        dst = tonumber(dst)
        if dst and dst > 0 and GetPlayerName(dst) then
            TriggerClientEvent(E.BOLO_ALERT, dst, payload)
            sent = sent + 1
        end
    end
    return sent
end


-- ============================================================
-- SQL (auditoria própria de scans via oxmysql — decisão #8)
-- ============================================================

-- grava o scan na tabela de auditoria (não é segunda fonte de verdade de BOLO)
local function logScan(src, plate, flagged, kind, coords)
    exports.oxmysql:execute(
        'INSERT INTO vhub_lspd_scans (scanner_uid, plate, flagged, src_kind, pos_x, pos_y, pos_z) ' ..
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        { VHubLspd.getUid(src), plate, flagged and 1 or 0, kind, coords.x, coords.y, coords.z }
    )
end


-- retorna os scans mais recentes (somente leitura; usa Await → exige thread no chamador)
local function recentScans(limit)
    limit = tonumber(limit) or 50
    if limit < 1 then limit = 1 elseif limit > 200 then limit = 200 end

    local p = promise.new()
    exports.oxmysql:query(
        'SELECT id, scanner_uid, plate, flagged, src_kind, pos_x, pos_y, pos_z, created_at ' ..
        'FROM vhub_lspd_scans ORDER BY id DESC LIMIT ?',
        { limit },
        function(rows) p:resolve(rows or {}) end
    )
    return Citizen.Await(p)
end


-- ============================================================
-- PIPELINE DE SCAN
-- ============================================================

-- processa um scan completo: valida, autoriza, deduz coords reais, checa BOLO e alerta
local function processScan(src, payload)
    if type(payload) ~= 'table' then return end

    -- 1) autorização do scanner (verdade crítica decidida no servidor)
    if not canScan(src) then
        Log('info', 'scan negado: src %s sem permissao', tostring(src))
        return
    end

    -- 2) validar placa (dado hostil do cliente)
    local plate = VHubLspd.normalizePlate(payload.plate)
    if not plate then return end

    -- 3) anti-flood por policial
    if not rateOk(src) then return end

    -- 4) dedup global por placa
    if not dedupOk(plate) then return end

    -- 5) coords autênticas server-side (ignora coords enviadas pelo cliente)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)

    local kind = (payload.kind == 'air') and 'air' or 'ground'

    -- 6) consulta o BOLO nativo (cache VRAM — sem round-trip no caminho quente)
    local bolo = VHubLspd.Bolo and VHubLspd.Bolo.check(plate) or nil

    -- 7) se sinalizada, encaminha o alerta às unidades policiais
    if bolo then
        local sent = broadcastAlert(plate, coords, bolo, kind)
        Log('info', 'BOLO: placa %s sinalizada (scanner %s, %s) -> %d unidades', plate, tostring(src), kind, sent)
    end

    -- 8) auditoria própria
    if cfg.log.enabled and (bolo or not cfg.log.onlyFlagged) then
        logScan(src, plate, bolo ~= nil, kind, coords)
    end
end


-- ============================================================
-- NET
-- ============================================================

-- recebe a placa lida do cliente; isola o pipeline em thread e pcall (nunca derruba o tick)
RegisterNetEvent(E.PLATE_SCANNED, function(data)
    local src = source
    Citizen.CreateThread(function()
        local ok, err = pcall(processScan, src, data)
        if not ok then Log('error', 'processScan falhou: %s', tostring(err)) end
    end)
end)


-- pedido de radar automático: só autoriza quem o servidor confirma como policial
RegisterNetEvent(E.REQ_RADAR, function()
    local src = source
    local now = GetGameTimer()
    if _radarReq[src] and (now - _radarReq[src]) < 1000 then return end  -- anti-spam
    _radarReq[src] = now

    if canScan(src) then
        TriggerClientEvent(E.ENABLE_RADAR, src)
    end
end)


-- ============================================================
-- EXPORTS (scan)
-- ============================================================

-- reporta uma placa como lida por um src (passa pelo mesmo pipeline; valida policial)
exports('reportPlate', function(src, plate, opts)
    if not VHubLspd.invokerAllowed() then return false end
    src = tonumber(src)
    if not src then return false end

    Citizen.CreateThread(function()
        local ok, err = pcall(processScan, src, { plate = plate, kind = opts and opts.kind or 'ground' })
        if not ok then Log('error', 'reportPlate falhou: %s', tostring(err)) end
    end)
    return true
end)


-- retorna os scans mais recentes (somente leitura; chamar dentro de Citizen.CreateThread)
exports('getRecentScans', function(limit)
    if not VHubLspd.invokerAllowed() then return {} end
    return recentScans(limit)
end)


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- aplica o schema próprio, carrega BOLOs em cache e avisa se o radar não está presente
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Citizen.CreateThread(function()
        local schema = LoadResourceFile(res, 'sql/schema.sql')
        if schema and schema ~= '' then
            -- schema MULTI-statement: usar :query (o :execute do oxmysql não aplica
            -- lotes multi-statement de forma confiável — mesmo padrão do CORE bootstrap)
            exports.oxmysql:query(schema, {}, function()
                Log('info', 'schema aplicado')
                if VHubLspd.Bolo   then VHubLspd.Bolo.loadAll()   end
                if VHubLspd.Wanted then VHubLspd.Wanted.loadAll() end
            end)
        else
            if VHubLspd.Bolo   then VHubLspd.Bolo.loadAll()   end
            if VHubLspd.Wanted then VHubLspd.Wanted.loadAll() end
        end
    end)
end)


-- libera caches do player que saiu
AddEventHandler('playerDropped', function()
    local src = source
    _perm[src]     = nil
    _rate[src]     = nil
    _radarReq[src] = nil
end)


-- invalida o cache de permissão quando o grupo do player muda (padrão do manual 4.3)
AddEventHandler('vhub_groups:changed', function(src)
    if src ~= nil then
        _perm[tonumber(src) or src] = nil
    else
        _perm = {}
    end
end)
