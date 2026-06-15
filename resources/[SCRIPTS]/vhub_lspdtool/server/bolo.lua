-- bolo.lua — domínio BOLO server-authoritative (fonte de verdade própria do LSPD Tool)
-- Cache VRAM dos BOLOs ativos (check O(1) no caminho quente) + persistência via oxmysql.
-- Comandos policiais /bolo /bolos /delbolo gatekeados por permissão server-side.

local cfg = VHubLspd.cfg
local E   = VHubLspd.E

local Bolo = {}
VHubLspd.Bolo = Bolo


-- ============================================================
-- STATE
-- ============================================================

local _cache    = {}  -- [plate] = { id, reason, level, by }   BOLOs ativos (VRAM)
local _count    = 0   -- nº de BOLOs ativos (teto cfg.bolo.maxActive)
local _cooldown = {}  -- [src]   = ms (último /bolo)            anti-flood de comando


-- atalho de log do resource
local function Log(level, fmt, ...)
    if VHubLspd.Log then VHubLspd.Log(level, fmt, ...) end
end


-- ============================================================
-- QUERIES / CACHE
-- ============================================================

-- carrega todos os BOLOs ativos para o cache VRAM (chamado no boot, após o schema)
function Bolo.loadAll()
    exports.oxmysql:query(
        'SELECT id, plate, reason, level, created_by_uid FROM vhub_lspd_bolos WHERE active = 1',
        {},
        function(rows)
            _cache, _count = {}, 0
            for _, r in ipairs(rows or {}) do
                _cache[r.plate] = { id = r.id, reason = r.reason, level = r.level, by = r.created_by_uid }
                _count = _count + 1
            end
            Log('info', 'BOLOs ativos carregados: %d', _count)
        end
    )
end


-- retorna o BOLO ativo da placa (consulta de cache, sem SQL) ou nil
function Bolo.check(plate)
    return _cache[plate]
end


-- retorna a lista de BOLOs ativos (cópia plana, sem expor created_by_uid)
function Bolo.list()
    local out = {}
    for plate, b in pairs(_cache) do
        out[#out + 1] = { plate = plate, reason = b.reason, level = b.level }
    end
    return out
end


-- ============================================================
-- MUTATIONS (validadas, server-side)
-- ============================================================

-- cria um BOLO para a placa; retorna ok, err. Cache otimista + backfill do id.
function Bolo.create(uid, plate, reason, level)
    if _cache[plate] then return false, 'existe' end
    if _count >= cfg.bolo.maxActive then return false, 'limite' end

    level = tonumber(level) or cfg.bolo.defaultLevel
    _cache[plate] = { id = 0, reason = reason, level = level, by = uid }
    _count = _count + 1

    exports.oxmysql:insert(
        'INSERT INTO vhub_lspd_bolos (plate, reason, level, created_by_uid, active) VALUES (?, ?, ?, ?, 1)',
        { plate, reason, level, uid },
        function(id)
            if not id then
                if _cache[plate] then _cache[plate] = nil; _count = _count - 1 end  -- rollback
                Log('error', 'INSERT BOLO falhou para placa %s', plate)
            elseif _cache[plate] then
                _cache[plate].id = id
            end
        end
    )
    return true
end


-- remove (desativa) o BOLO da placa; retorna ok, err
function Bolo.remove(plate)
    if not _cache[plate] then return false, 'inexistente' end

    _cache[plate] = nil
    _count = _count - 1
    exports.oxmysql:execute('UPDATE vhub_lspd_bolos SET active = 0 WHERE plate = ? AND active = 1', { plate })
    return true
end


-- ============================================================
-- COMMANDS (entrada hostil — perm + sanitização server-side)
-- ============================================================

-- aplica cooldown anti-flood por src; true se o comando pode prosseguir
local function cmdOk(src)
    local now  = GetGameTimer()
    local last = _cooldown[src] or 0
    if (now - last) < cfg.bolo.cmdCooldownMs then return false end
    _cooldown[src] = now
    return true
end


-- /bolo <placa> <motivo> — cria um BOLO (requer permManageBolo)
RegisterCommand('bolo', function(src, args)
    if src == 0 then return end  -- console não tem identidade policial
    if not VHubLspd.hasPerm(src, cfg.police.permManageBolo) then
        VHubLspd.notify(src, 'Sem permissao para criar BOLO.')
        return
    end

    local plate = VHubLspd.normalizePlate(args[1])
    if not plate then
        VHubLspd.notify(src, 'Uso: /bolo <placa> <motivo>')
        return
    end

    table.remove(args, 1)
    local reason = table.concat(args, ' '):gsub('[%c]', ''):sub(1, cfg.bolo.reasonMaxLen)
    if reason == '' then reason = 'Sem motivo informado' end

    if not cmdOk(src) then
        VHubLspd.notify(src, 'Aguarde antes de criar outro BOLO.')
        return
    end

    local ok, err = Bolo.create(VHubLspd.getUid(src), plate, reason, cfg.bolo.defaultLevel)
    if ok then
        VHubLspd.notify(src, ('BOLO criado para a placa %s.'):format(plate))
        Log('info', 'BOLO criado: %s por src %s (uid %s)', plate, tostring(src), tostring(VHubLspd.getUid(src)))
    elseif err == 'existe' then
        VHubLspd.notify(src, 'Ja existe um BOLO para essa placa.')
    elseif err == 'limite' then
        VHubLspd.notify(src, ('Limite de %d BOLOs ativos atingido.'):format(cfg.bolo.maxActive))
    end
end, false)


-- /delbolo <placa> — remove um BOLO (requer permManageBolo)
RegisterCommand('delbolo', function(src, args)
    if src == 0 then return end
    if not VHubLspd.hasPerm(src, cfg.police.permManageBolo) then
        VHubLspd.notify(src, 'Sem permissao para remover BOLO.')
        return
    end

    local plate = VHubLspd.normalizePlate(args[1])
    if not plate then
        VHubLspd.notify(src, 'Uso: /delbolo <placa>')
        return
    end

    local ok = Bolo.remove(plate)
    if ok then
        VHubLspd.notify(src, ('BOLO removido da placa %s.'):format(plate))
        Log('info', 'BOLO removido: %s por src %s', plate, tostring(src))
    else
        VHubLspd.notify(src, 'Nenhum BOLO ativo para essa placa.')
    end
end, false)


-- /bolos — lista os BOLOs ativos para o policial (requer permScan)
RegisterCommand('bolos', function(src)
    if src == 0 then return end
    if not VHubLspd.hasPerm(src, cfg.police.permScan) then
        VHubLspd.notify(src, 'Sem permissao para consultar BOLOs.')
        return
    end

    local list = Bolo.list()
    if #list == 0 then
        VHubLspd.notify(src, 'Nenhum BOLO ativo.')
        return
    end

    VHubLspd.notify(src, ('--- BOLOs ativos (%d) ---'):format(#list))
    for _, b in ipairs(list) do
        VHubLspd.notify(src, ('%s — %s'):format(b.plate, b.reason))
    end
end, false)


-- ============================================================
-- EXPORTS (mutadores e leitura — todos sob _invoker_allowed)
-- ============================================================

-- cria um BOLO programaticamente (resources confiáveis)
exports('addBolo', function(plate, reason, opts)
    if not VHubLspd.invokerAllowed() then return false end
    local p = VHubLspd.normalizePlate(plate)
    if not p then return false end
    local r = tostring(reason or 'Sem motivo'):gsub('[%c]', ''):sub(1, cfg.bolo.reasonMaxLen)
    local ok = Bolo.create((opts and tonumber(opts.uid)) or nil, p, r, opts and opts.level)
    return ok == true
end)


-- remove um BOLO programaticamente (resources confiáveis)
exports('removeBolo', function(plate)
    if not VHubLspd.invokerAllowed() then return false end
    local p = VHubLspd.normalizePlate(plate)
    if not p then return false end
    return Bolo.remove(p) == true
end)


-- consulta o BOLO de uma placa (resources confiáveis)
exports('checkBolo', function(plate)
    if not VHubLspd.invokerAllowed() then return nil end
    local p = VHubLspd.normalizePlate(plate)
    return p and _cache[p] or nil
end)


-- lista BOLOs ativos (resources confiáveis)
exports('listBolos', function()
    if not VHubLspd.invokerAllowed() then return {} end
    return Bolo.list()
end)
