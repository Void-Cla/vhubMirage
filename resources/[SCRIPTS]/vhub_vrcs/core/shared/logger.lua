-- core/shared/logger.lua — unico ponto de print() do vhub_vrcs (L-08).
--
-- vHub.Logger e global do Lua state do CORE e NAO cruza resource; por isso cada
-- resource externo mantem o seu (mesmo precedente do vhub_racha/vhub_lspdtool).

VRCS = VRCS or {}


-- ============================================================
-- LOGGER
-- ============================================================

local PREFIX = '^5[vhub_vrcs]^7 '

-- escreve uma linha colorida no console (unico print autorizado)
local function out(color, msg)
    print(('%s%s%s^7'):format(PREFIX, color, tostring(msg)))
end

VRCS.Log = {
    info  = function(m) out('^2', m) end,   -- verde
    warn  = function(m) out('^3', m) end,   -- amarelo
    error = function(m) out('^1', m) end,   -- vermelho
}
