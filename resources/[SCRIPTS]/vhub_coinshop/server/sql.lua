-- server/sql.lua — wrappers promise-based para exports.oxmysql (nunca S:prepare cross-resource, §3.6)

local function _pquery(sql, args)
    local p = promise.new()
    exports.oxmysql:query(sql, args or {}, function(r) p:resolve(r or {}) end)
    return Citizen.Await(p)
end

local function _pexecute(sql, args)
    local p = promise.new()
    exports.oxmysql:execute(sql, args or {}, function(r) p:resolve(r or 0) end)
    return Citizen.Await(p)
end

local function _pscalar(sql, args)
    local p = promise.new()
    exports.oxmysql:scalar(sql, args or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
end

local function _pinsert(sql, args)
    local p = promise.new()
    exports.oxmysql:insert(sql, args or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
end


-- SQL — API local do recurso (escopo server)
SQL = {
    query   = _pquery,    -- SELECT (retorna array de rows)
    execute = _pexecute,  -- INSERT/UPDATE/DELETE (retorna affected rows)
    scalar  = _pscalar,   -- SELECT de um valor único
    insert  = _pinsert,   -- INSERT com RETURNING (retorna insertId)
}
