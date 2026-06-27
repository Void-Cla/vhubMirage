-- server/ranking.lua — leitura agregada para a NUI.

VHubRachaRanking = {}
local R = VHubRachaRanking
local SQL = VHubRachaSQL

local function resolve_nicks(char_ids)
  local out = {}
  if type(char_ids) ~= 'table' or #char_ids == 0 then return out end
  -- Dedupe
  local seen = {}
  local list = {}
  for _, cid in ipairs(char_ids) do
    cid = tonumber(cid) or 0
    if cid > 0 and not seen[cid] then seen[cid] = true; list[#list + 1] = cid end
  end
  if #list == 0 then return out end

  local placeholders = {}
  for _ = 1, #list do placeholders[#placeholders + 1] = '?' end
  local rows = SQL.query(
    "SELECT char_id, firstname, lastname FROM vh_identity WHERE char_id IN (" ..
    table.concat(placeholders, ',') .. ")", list)
  for _, row in ipairs(rows or {}) do
    out[tonumber(row.char_id)] =
      ((row.firstname or '') .. ' ' .. (row.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
  end
  for _, cid in ipairs(list) do
    if not out[cid] or out[cid] == '' then out[cid] = 'char_' .. cid end
  end
  return out
end

function R.top(kind, mode, limit)
  local rows = SQL.ranking_kind(kind, mode, limit) or {}
  local ids = {}
  for i, r in ipairs(rows) do ids[i] = tonumber(r.char_id) end
  local nicks = resolve_nicks(ids)
  for _, r in ipairs(rows) do
    r.nick = nicks[tonumber(r.char_id)] or ('char_' .. r.char_id)
  end
  return rows
end

function R.recent(filters, limit)
  local rows = SQL.history_recent(filters, limit) or {}
  local ids = {}
  for i, r in ipairs(rows) do ids[i] = tonumber(r.winner_char) end
  local nicks = resolve_nicks(ids)
  for _, r in ipairs(rows) do
    r.winner_nick = nicks[tonumber(r.winner_char)] or ('char_' .. r.winner_char)
  end
  return rows
end

function R.results_of(history_id) return SQL.results_of(history_id) or {} end
function R.stats_of_char(char_id)  return SQL.stats_of_char(char_id) or {} end
function R.records_of_char(char_id, limit) return SQL.records_of_char(char_id, limit) or {} end


-- ── Ranqueado / Perfil ──────────────────────────────────────────────────────

-- Leaderboard PDL (cross-kind) com nick resolvido. So leitura — o dominio de
-- escrita vive em server/ranked.lua (VHubRachaRanked).
function R.ranked_ladder(limit)
  local rows = VHubRachaRanked.top(limit)
  local ids = {}
  for i, r in ipairs(rows) do ids[i] = tonumber(r.char_id) end
  local nicks = resolve_nicks(ids)
  for _, r in ipairs(rows) do
    r.nick = nicks[tonumber(r.char_id)] or ('char_' .. r.char_id)
  end
  return rows
end

-- Perfil COMPOSTO export-ready de um corredor (reuso, SEM 2a fonte): identidade
-- (vh_identity via resolve_nicks), ranqueado (VHubRachaRanked), stats por modo,
-- records, AGREGADOS de carreira e atividade recente. Payload versionado e
-- JSON-friendly (sem vec/funcao) — pronto p/ o site da cidade (feed/perfil).
function R.profile_of(char_id)
  local cid     = tonumber(char_id) or 0
  local ranked  = VHubRachaRanked.get(cid)
  local nicks   = resolve_nicks({ cid })
  local stats   = SQL.stats_of_char(cid) or {}
  local records = SQL.records_of_char(cid, 30) or {}

  -- Agregados de carreira (somatorio cross-kind) — alimenta o cartao + export.
  local tot = { runs = 0, wins = 0, podiums = 0, dnf = 0,
                total_payout = 0, total_drift = 0, top_speed = 0, best_time_ms = 0 }
  local fav_kind, fav_runs = nil, -1
  for _, s in ipairs(stats) do
    local runs = tonumber(s.runs) or 0
    tot.runs         = tot.runs + runs
    tot.wins         = tot.wins + (tonumber(s.wins) or 0)
    tot.podiums      = tot.podiums + (tonumber(s.podiums) or 0)
    tot.dnf          = tot.dnf + (tonumber(s.dnf) or 0)
    tot.total_payout = tot.total_payout + (tonumber(s.total_payout) or 0)
    tot.total_drift  = tot.total_drift + (tonumber(s.total_drift) or 0)
    tot.top_speed    = math.max(tot.top_speed, tonumber(s.top_speed) or 0)
    local bt = tonumber(s.best_time_ms) or 0
    if bt > 0 and (tot.best_time_ms == 0 or bt < tot.best_time_ms) then tot.best_time_ms = bt end
    if runs > fav_runs then fav_runs = runs; fav_kind = s.kind end
  end
  tot.winrate = (tot.runs > 0) and math.floor((tot.wins / tot.runs) * 100) or 0

  return {
    schema  = 'vhub_racha.profile.v1',   -- versionado p/ o site (estabilidade do contrato)
    char_id = cid,
    nick    = nicks[cid] or ('char_' .. cid),
    ranked  = {
      pdl         = ranked.pdl,
      peak_pdl    = ranked.peak_pdl,
      matches     = ranked.matches,
      wins        = ranked.wins,
      provisional = ranked.provisional == true,
      division    = VHubRachaRanked.division(ranked.pdl),
    },
    career        = tot,
    favorite_kind = fav_kind,
    stats         = stats,
    records       = records,
    recent        = SQL.history_recent({ char_id = cid }, 8),   -- atividade recente
  }
end
