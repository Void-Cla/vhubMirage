-- server/exports.lua — API publica + TRUSTED.

local Cfg = VHubRachaCfg
local ST  = VHubRachaState
local L   = VHubRachaLobby
local R   = VHubRachaRanking
local SQL = VHubRachaSQL

-- N0-2 default-DENY (#32): sem caller identificavel ou sem whitelist => NAO passa.
local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return false end
  local trusted = Cfg.TRUSTED_RESOURCES
  if type(trusted) ~= 'table' or next(trusted) == nil then return false end
  return trusted[caller] == true
end

-- ── Read-only ───────────────────────────────────────────────────────────────

exports('catalog', function()
  local out = {}
  for id, t in pairs(ST.catalog()) do
    out[#out + 1] = {
      id = id, label = t.label, district = t.district, kind = t.kind,
      illegal = t.illegal, alerts_police = t.alerts_police,
      laps = t.laps, min_players = t.min_players, max_players = t.max_players,
      vehicle_class = t.vehicle_class, default_fee = t.default_fee,
      limit_seconds = t.limit_seconds, source = t.source,
      cps = #(t.checkpoints or {}),
    }
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end)

exports('lobbies', function()        return ST.public_lobbies() end)
exports('isInRace', function(src)    return ST.instance_by_src(tonumber(src) or 0) ~= nil end)
exports('isReady',  function()       return VHubRachaBoot and VHubRachaBoot.READY == true end)
exports('Status',   function()       return ST.status_snapshot() end)

-- ── Ranking ─────────────────────────────────────────────────────────────────

exports('topRanking',     function(kind, mode, limit) return R.top(kind or 'sprint', mode or 'wins', limit or 50) end)
exports('historyRecent',  function(filters, limit)    return R.recent(filters or {}, limit or 30) end)
exports('resultsOf',      function(history_id)        return R.results_of(history_id) end)
exports('statsOfChar',    function(char_id)           return R.stats_of_char(tonumber(char_id) or 0) end)
exports('recordsOfChar',  function(char_id, limit)    return R.records_of_char(tonumber(char_id) or 0, limit or 30) end)
-- Perfil COMPLETO export-ready (versionado, JSON-friendly) — consumivel pelo
-- futuro site da cidade (feed/perfil social). Dado publico, sem gate.
exports('rankedLadder',   function(limit)             return R.ranked_ladder(limit or 50) end)
exports('profile',        function(char_id)           return R.profile_of(tonumber(char_id) or 0) end)

-- ── Mutacoes (TRUSTED) ──────────────────────────────────────────────────────

exports('createLobby', function(src, payload)
  if not _invoker_allowed() then return false, 'forbidden' end
  return L.create(tonumber(src) or 0, payload or {})
end)

exports('cancelLobby', function(inst_id, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  return L.cancel(inst_id, reason or 'admin')
end)

exports('deleteTrack', function(track_id)
  if not _invoker_allowed() then return false, 'forbidden' end
  if not track_id then return false, 'track_id_obrigatorio' end
  SQL.delete_track(track_id, true)
  ST._catalog[track_id] = nil
  return true
end)
