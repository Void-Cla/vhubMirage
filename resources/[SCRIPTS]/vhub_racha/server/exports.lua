-- server/exports.lua - API publica do vhub_racha.

local Core, SQL, Cfg = VHubRachaCore, VHubRachaSQL, VHubRachaCfg

local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return true end
  local trusted = Cfg.TRUSTED_RESOURCES
  if type(trusted) ~= 'table' or next(trusted) == nil then return true end
  return trusted[caller] == true
end

exports('Status', function() return Core.status() end)
exports('getTrackRanking', function(track_id, limit) return SQL.track_ranking(track_id, limit or 20) end)
exports('getGeneralRanking', function(limit) return SQL.general_ranking(limit or 20) end)
exports('getTrackHistory', function(track_id, limit) return SQL.track_history(track_id, limit or 30) end)
exports('getRunResults', function(run_id) return SQL.run_results(run_id) end)

exports('cancelTrackLobby', function(track_id)
  if not _invoker_allowed() then return false, 'forbidden' end
  local lobby = Core._lobbies and Core._lobbies[track_id]
  if not lobby then return false, 'lobby_inexistente' end
  return Core.cancel_lobby(lobby.organizer_src or 0, { track_id = track_id })
end)
