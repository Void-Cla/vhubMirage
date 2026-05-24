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
