---@diagnostic disable: undefined-global, lowercase-global

-- wanted.lua — domínio PROCURADOS (pessoas) server-authoritative. Mandado por char_id,
-- distinto do BOLO (que é por placa). Cache VRAM dos procurados ativos (check O(1)) +
-- persistência via oxmysql. Ao criar, dispara alerta dirigido às unidades policiais.

local cfg = VHubLspd.cfg
local E   = VHubLspd.E

local Wanted = {}
VHubLspd.Wanted = Wanted


-- ============================================================
-- STATE (cache em VRAM — sem segunda fonte de verdade)
-- ============================================================

local _cache = {}  -- [char_id] = { id, name, reason, level, by }
local _count = 0   -- nº de procurados ativos (teto cfg.wanted.maxActive)

local function Log(level, fmt, ...) if VHubLspd.Log then VHubLspd.Log(level, fmt, ...) end end


-- ============================================================
-- QUERIES / CACHE
-- ============================================================

-- carrega todos os procurados ativos para o cache VRAM (boot, após o schema)
function Wanted.loadAll()
    exports.oxmysql:query(
        'SELECT id, target_char_id, target_name, reason, level, created_by_uid ' ..
        'FROM vhub_lspd_wanted WHERE active = 1',
        {},
        function(rows)
            _cache, _count = {}, 0
            for _, r in ipairs(rows or {}) do
                _cache[r.target_char_id] = {
                    id = r.id, name = r.target_name, reason = r.reason,
                    level = r.level, by = r.created_by_uid,
                }
                _count = _count + 1
            end
            Log('info', 'procurados ativos carregados: %d', _count)
        end
    )
end


-- retorna o registro de procura do char_id (consulta de cache, sem SQL) ou nil
function Wanted.check(char_id)
    return _cache[tonumber(char_id) or 0]
end


-- retorna a lista de procurados ativos (cópia plana, sem expor created_by_uid)
function Wanted.list()
    local out = {}
    for cid, w in pairs(_cache) do
        out[#out + 1] = { char_id = cid, name = w.name, reason = w.reason, level = w.level }
    end
    return out
end


-- ============================================================
-- MUTATIONS (validadas, server-side)
-- ============================================================

-- cria um mandado para o char_id; retorna (true) ou (false, motivo). Cache otimista.
function Wanted.create(uid, target_char_id, name, reason, level)
    target_char_id = tonumber(target_char_id)
    if not target_char_id then return false, 'char_invalido' end
    if _cache[target_char_id] then return false, 'existe' end
    if _count >= cfg.wanted.maxActive then return false, 'limite' end

    name   = tostring(name or ''):gsub('[%c]', ''):sub(1, cfg.wanted.nameMaxLen)
    reason = tostring(reason or ''):gsub('[%c]', ''):sub(1, cfg.wanted.reasonMaxLen)
    if reason == '' then reason = 'Sem motivo informado' end
    level  = tonumber(level) or cfg.wanted.defaultLevel
    level  = math.max(1, math.min(#cfg.wanted.levels, math.floor(level)))

    _cache[target_char_id] = { id = 0, name = name, reason = reason, level = level, by = uid }
    _count = _count + 1

    exports.oxmysql:insert(
        'INSERT INTO vhub_lspd_wanted (target_char_id, target_name, reason, level, created_by_uid, active) ' ..
        'VALUES (?, ?, ?, ?, ?, 1)',
        { target_char_id, name, reason, level, uid },
        function(id)
            if not id then
                if _cache[target_char_id] then _cache[target_char_id] = nil; _count = _count - 1 end
                Log('error', 'INSERT procurado falhou para char_id %s', tostring(target_char_id))
            elseif _cache[target_char_id] then
                _cache[target_char_id].id = id
            end
        end
    )

    -- alerta dirigido às unidades policiais (dispatch)
    VHubLspd.dispatchUnits(E.WANTED_ALERT, {
        char_id = target_char_id, name = name, reason = reason, level = level,
    })
    return true
end


-- remove (desativa) o mandado do char_id; retorna ok
function Wanted.remove(target_char_id)
    target_char_id = tonumber(target_char_id)
    if not target_char_id or not _cache[target_char_id] then return false, 'inexistente' end

    _cache[target_char_id] = nil
    _count = _count - 1
    exports.oxmysql:execute(
        'UPDATE vhub_lspd_wanted SET active = 0 WHERE target_char_id = ? AND active = 1',
        { target_char_id }
    )
    return true
end


-- ============================================================
-- EXPORTS (todos sob _invoker_allowed)
-- ============================================================

-- consulta o mandado de um char_id (resources confiáveis)
exports('checkWanted', function(char_id)
    if not VHubLspd.invokerAllowed() then return nil end
    return Wanted.check(char_id)
end)

-- lista procurados ativos (resources confiáveis)
exports('listWanted', function()
    if not VHubLspd.invokerAllowed() then return {} end
    return Wanted.list()
end)
