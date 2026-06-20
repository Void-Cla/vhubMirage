-- shared/logger.lua — wrapper de log centralizado (L-08: print só aqui)
---@diagnostic disable: undefined-global, lowercase-global

VHubCustom     = VHubCustom or {}

-- loga mensagem com prefixo do resource
function VHubCustom.log(msg)
  print('[vhub_custom] ' .. tostring(msg))
end
