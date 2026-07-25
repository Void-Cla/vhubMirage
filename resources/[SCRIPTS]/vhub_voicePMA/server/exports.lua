-- server/exports.lua — API publica default-deny do motor de voz

local Cfg = VHubVoicePMA.Cfg
local S = VHubVoicePMA.Server

local function invoker_ok()
  local caller = GetInvokingResource()
  return type(caller) == 'string' and Cfg.TRUSTED_SERVER_RESOURCES[caller] == true
end

-- Define a frequencia de radio de um jogador online.
exports('setRadioChannel', function(src, channel)
  if not invoker_ok() then return false, 'forbidden' end
  return S.setRadio(src, channel)
end)

-- Remove um jogador da frequencia atual.
exports('leaveRadio', function(src)
  if not invoker_ok() then return false, 'forbidden' end
  return S.setRadio(src, 0)
end)

-- Define a ligacao de um jogador por contrato server-side.
exports('setCallChannel', function(src, channel)
  if not invoker_ok() then return false, 'forbidden' end
  return S.setCall(src, channel)
end)

-- Remove um jogador da ligacao atual.
exports('leaveCall', function(src)
  if not invoker_ok() then return false, 'forbidden' end
  return S.setCall(src, 0)
end)

-- Retorna copia do estado efemero de voz.
exports('getVoiceState', function(src)
  if not invoker_ok() then return nil end
  return S.getState(src)
end)

-- Retorna copia ordenada dos membros de uma frequencia.
exports('getRadioMembers', function(channel)
  if not invoker_ok() then return {} end
  return S.getRadioMembers(channel)
end)

