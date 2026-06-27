---@diagnostic disable: undefined-global, lowercase-global

-- server/init.lua — composicao: aplica schema, expoe os exports sensiveis e faz
--                   o cleanup no stop. ULTIMO a carregar (ver fxmanifest).

VRCS = VRCS or {}

local Cfg = VRCS.Cfg
local Log = VRCS.Log
local B   = VRCS.Bindings.Racha


-- ============================================================
-- FRONTEIRA — exports sensiveis (N0-2 default-DENY)
-- ============================================================

-- so resources na whitelist (Cfg.TRUSTED_RESOURCES) podem empurrar telemetria.
-- sem caller ou sem whitelist => NAO passa.
local function _invoker_allowed()
    local caller = GetInvokingResource()
    if not caller then return false end
    local trusted = Cfg.TRUSTED_RESOURCES
    if type(trusted) ~= 'table' or next(trusted) == nil then return false end
    return trusted[caller] == true
end


-- abre um replay para uma corrida (chamado pelo vhub_racha no begin_racing)
exports('onRaceStart', function(meta)
    if not _invoker_allowed() then return false, 'forbidden' end
    return B.on_race_start(meta)
end)


-- fecha o replay com o desfecho (chamado pelo vhub_racha no finish)
exports('onRaceClose', function(inst_id, finalMeta)
    if not _invoker_allowed() then return false, 'forbidden' end
    return B.on_race_close(inst_id, finalMeta)
end)


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- aplica o schema (multipleStatements=true habilita o batch num unico execute)
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end

    local sql = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
    if sql and sql ~= '' then
        exports.oxmysql:execute(sql, {}, function()
            Log.info('schema aplicado (vh_race_replays + vh_vrcs_jobs).')
        end)
    end

    Log.info(('pronto. gravacao: %s'):format(
        Cfg.RECORD.ranked_only and 'somente ranqueada' or 'todas as categorias'))
end)


-- descarta buffers pendentes no stop (replay parcial e perdido — residual aceito)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if B and B.flush_all then B.flush_all() end
end)
