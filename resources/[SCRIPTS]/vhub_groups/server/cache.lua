-- server/cache.lua — vhub_groups
-- VRAM-first: estado em memoria como source of truth runtime. SQL e backup.
-- Indexacao DUAL para O(1) tanto via src quanto via char_id:
--   _by_src     [src]     → entry
--   _by_char    [char_id] → entry
-- Onde entry = {
--   src, char_id, owner, groups, perms, _wildcards (em perms), loaded_ms
-- }
-- groups = { [group_id] = { level, added_by, added_at_unix, expires_at_unix, reason } }
-- perms  = set computado via VHubGroupsPerms.compile (com _wildcards lazy)
--
-- Invalidacao: explicita via Cache.invalidate(char_id) — toda mutacao reseta o set.
-- TTL: cron opcional limpa entries de chars cuja loaded_ms estourou (raro: drop
--      ja invalida; TTL e para chars carregados offline via NUI admin).

VHubGroupsCache = {
  _by_src  = {},
  _by_char = {},
  metrics  = { hits = 0, misses = 0, loads = 0, invalidations = 0 },
}
local C = VHubGroupsCache

local function ms() return GetGameTimer() end

-- Cria entry vazio (sem grupos carregados ainda)
local function new_entry(src, char_id)
  local owner = (tonumber(char_id) == tonumber(VHubGroupsCfg.OWNER_CHAR_ID))
  return {
    src       = tonumber(src) or 0,
    char_id   = tonumber(char_id),
    owner     = owner,
    groups    = {},
    perms     = owner and { ['*'] = true } or {},
    loaded_ms = ms(),
  }
end

-- ── Registro / desregistro de sessao ────────────────────────────────────────

-- Registra entry vazio (sem grupos) — chamado em characterLoad antes do load SQL
function C.register(src, char_id)
  local char = tonumber(char_id)
  if not char or char <= 0 then return nil end
  local entry = new_entry(src, char)
  C._by_src[src]   = entry
  C._by_char[char] = entry
  return entry
end

-- Remove entry da VRAM (em playerDropped ou character switch)
function C.unregister_src(src)
  local entry = C._by_src[src]
  if not entry then return end
  C._by_src[src] = nil
  if entry.char_id then C._by_char[entry.char_id] = nil end
end

function C.unregister_char(char_id)
  local entry = C._by_char[char_id]
  if not entry then return end
  C._by_char[char_id] = nil
  if entry.src then C._by_src[entry.src] = nil end
end

-- ── Acesso ──────────────────────────────────────────────────────────────────

function C.by_src(src)
  local e = C._by_src[src]
  if e then C.metrics.hits = C.metrics.hits + 1
  else      C.metrics.misses = C.metrics.misses + 1 end
  return e
end

function C.by_char(char_id)
  local e = C._by_char[char_id]
  if e then C.metrics.hits = C.metrics.hits + 1
  else      C.metrics.misses = C.metrics.misses + 1 end
  return e
end

-- ── Mutacao do estado ───────────────────────────────────────────────────────

-- Substitui grupos do entry e recomputa perms set.
-- groups: { [group_id] = { level, added_by, added_at_unix, expires_at_unix, reason } }
function C.set_groups(entry, groups)
  if not entry then return end
  entry.groups = type(groups) == 'table' and groups or {}
  entry.perms  = VHubGroupsPerms.compile(entry.groups, entry.owner == true)
  entry.loaded_ms = ms()
  C.metrics.loads = C.metrics.loads + 1
end

-- Adiciona/atualiza UM grupo no entry (mais barato que recompilar tudo)
function C.upsert_group(entry, group_id, row)
  if not entry or not group_id then return end
  entry.groups[group_id] = {
    level           = tonumber(row.level) or 1,
    added_by        = tonumber(row.added_by) or 0,
    added_at_unix   = tonumber(row.added_at_unix) or os.time(),
    expires_at_unix = tonumber(row.expires_at_unix) or nil,
    reason          = tostring(row.reason or ''),
  }
  -- Recompila perms (low-cost: max ~10 grupos por char no pior caso)
  entry.perms = VHubGroupsPerms.compile(entry.groups, entry.owner == true)
end

function C.remove_group(entry, group_id)
  if not entry or not group_id then return end
  if entry.groups[group_id] == nil then return end
  entry.groups[group_id] = nil
  entry.perms = VHubGroupsPerms.compile(entry.groups, entry.owner == true)
end

-- Invalida (apaga) entry pelo char_id — forca recarregar do SQL no proximo acesso
function C.invalidate(char_id)
  local e = C._by_char[char_id]
  if not e then return end
  C._by_char[char_id] = nil
  if e.src then C._by_src[e.src] = nil end
  C.metrics.invalidations = C.metrics.invalidations + 1
end

-- ── Diagnostico ─────────────────────────────────────────────────────────────

function C.status()
  local total = 0
  for _ in pairs(C._by_char) do total = total + 1 end
  return {
    entries     = total,
    by_src      = next(C._by_src) ~= nil,
    by_char     = next(C._by_char) ~= nil,
    metrics     = C.metrics,
  }
end

function C.clear_all()
  C._by_src  = {}
  C._by_char = {}
end
