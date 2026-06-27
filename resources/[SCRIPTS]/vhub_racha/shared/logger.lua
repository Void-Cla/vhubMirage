---@diagnostic disable: undefined-global, lowercase-global

-- shared/logger.lua — logger próprio do racha. O vHub.Logger do core é global do
-- Lua state do CORE e NÃO cruza resource (mesmo motivo do vhub_lspdtool).
-- ÚNICO arquivo do resource autorizado a usar print() (L-08). Carrega 1º nos
-- shared_scripts, então VHubRachaLog existe em todos os módulos (client + server).
--
-- API: VHubRachaLog.info/warn/error(fmt, ...)  — fmt + args opcionais (string.format)

VHubRachaLog = VHubRachaLog or {}

-- emite uma linha com nível e prefixo do resource (formata só se houver args — evita
-- erro quando a mensagem tem '%' literal e nenhum argumento)
local function emit(level, fmt, ...)
  local msg = (select('#', ...) > 0) and string.format(fmt, ...) or tostring(fmt)
  print(('[vhub_racha][%s] %s'):format(level, msg))
end

function VHubRachaLog.info(fmt, ...)  emit('info',  fmt, ...) end
function VHubRachaLog.warn(fmt, ...)  emit('warn',  fmt, ...) end
function VHubRachaLog.error(fmt, ...) emit('error', fmt, ...) end
