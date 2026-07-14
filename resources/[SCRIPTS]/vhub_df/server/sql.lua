-- server/sql.lua — wrappers promise-based para exports.oxmysql (nunca S:prepare cross-resource)

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

-- SQL — API local do resource (escopo server)
SQL = {
    query   = _pquery,    -- SELECT → array de rows
    execute = _pexecute,  -- INSERT/UPDATE/DELETE → affected rows
    scalar  = _pscalar,   -- SELECT de valor único
    insert  = _pinsert,   -- INSERT → insertId
}
