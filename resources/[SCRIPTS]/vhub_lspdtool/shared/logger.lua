---@diagnostic disable: undefined-global, lowercase-global

-- logger.lua — logger próprio do LSPD Tool (o vHub.Logger do core não é acessível
-- cross-resource). Exposto em VHubLspd.Log para todos os módulos reaproveitarem.
-- Único arquivo do resource autorizado a usar print() (L-08).

VHubLspd = VHubLspd or {}


-- registra uma linha de log no console com nível e prefixo do resource.
-- Nível 'info' só aparece quando cfg.debug = true (silencioso em produção).
function VHubLspd.Log(level, fmt, ...)
    local cfg = VHubLspd.cfg
    if cfg and not cfg.debug and level == 'info' then return end
    print(('[vhub_lspdtool][%s] '):format(level) .. string.format(fmt, ...))
end
