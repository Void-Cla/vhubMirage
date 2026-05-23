-- server/core.lua — vhub_groups
-- Logica principal. Toda mutacao de grupo passa por aqui:
--   - validacao (grupo existe, nivel valido, exclusividade por type)
--   - mutacao em SQL
--   - atualizacao da VRAM cache
--   - audit append
--   - notificacao ao cliente afetado (HUD/State Bag)
--
-- Nao expoe direto pra outros resources — exports.lua e a fachada.

VHubGroupsCore = {}
local Core  = VHubGroupsCore
local SQL   = VHubGroupsSQL
local Cache = VHubGroupsCache
local Perms = VHubGroupsPerms
local Cfg   = VHubGroupsCfg
local Defs  = VHubGroupsDefs

local _vHub   = nil
local _ready  = false

function Core.set_vhub(vh) _vHub = vh end
function Core.get_vhub()   return _vHub end
function Core.is_ready()   return _ready end
function Core.mark_ready() _ready = true end

-- ── Utilidades internas ─────────────────────────────────────────────────────

local function log(level, msg, meta)
  if Cfg.LOG_LEVEL <= 0 then return end
  if _vHub and _vHub.Logger then
    if level == 'error' then _vHub.Logger:error('groups', msg, meta)
    elseif level == 'warn' then _vHub.Logger:warn('groups', msg, meta)
    else _vHub.Logger:info('groups', msg, meta) end
  else
    print(("[vhub_groups][%s] %s"):format(level, msg))
  end
end

-- Resolve char_id a partir do src (via Auth do core)
local function char_id_of(src)
  if not _vHub or not _vHub.Auth then return nil end
  local user = _vHub.Auth:getUser(tonumber(src) or 0)
  return user and user.char_id or nil
end

-- Resolve src a partir do char_id (varre sessions ativas)
local function src_of(char_id)
  if not _vHub or not _vHub.Auth or not _vHub.Auth._sessions then return nil end
  for _, user in pairs(_vHub.Auth._sessions) do
    if user.char_id == char_id then return user.source end
  end
  return nil
end

-- Converte linha SQL em row VRAM (parseando timestamps)
local function sql_row_to_cache(row)
  return {
    level           = tonumber(row.level) or 1,
    added_by        = tonumber(row.added_by) or 0,
    added_at_unix   = row.added_at and (type(row.added_at) == 'number' and row.added_at or 0) or 0,
    expires_at_unix = row.expires_at and (type(row.expires_at) == 'number' and row.expires_at or nil) or nil,
    reason          = tostring(row.reason or ''),
  }
end

-- Notifica cliente afetado (State Bag + evento) quando grupos mudam
local function notify_client(entry)
  if not entry or not entry.src or entry.src <= 0 then return end
  local src = entry.src

  -- State Bag: marca presenca dos grupos em vhub_groups (read-only por outros resources)
  local list = {}
  for gid, row in pairs(entry.groups) do
    list[gid] = row.level
  end
  Player(src).state:set('vhub_groups', list, true)

  -- Evento direto pro cliente atualizar UI
  TriggerClientEvent('vhub_groups:updated', src, list)
end

-- ── Validacao ────────────────────────────────────────────────────────────────

-- Valida grupo + nivel; retorna (ok, group_id_normalizado, level_clampado, err)
local function validate(group_id, level)
  if type(group_id) ~= 'string' or group_id == '' then
    return false, nil, nil, 'group_id_invalido'
  end
  local gid = group_id:lower():gsub('[^a-z0-9_%-]', '')
  if not Defs[gid] then return false, nil, nil, 'grupo_nao_existe' end

  local lvl = Perms.clamp(gid, level or 1)
  if not lvl then return false, nil, nil, 'nivel_invalido' end

  return true, gid, lvl, nil
end

-- Lista grupos do mesmo type que devem ser removidos antes de adicionar 'group_id'.
-- Para types 'job' e 'gang': exclusividade automatica (1 ativo por type).
-- Retorna lista de group_ids a remover (vazio se nao houver conflito).
local function exclusion_list(entry, target_group_id)
  local def = Defs[target_group_id]
  if not def then return {} end
  local target_type = def.type
  if target_type ~= 'job' and target_type ~= 'gang' then return {} end

  local to_remove = {}
  for gid, _ in pairs(entry.groups) do
    if gid ~= target_group_id then
      local d = Defs[gid]
      if d and d.type == target_type then
        to_remove[#to_remove + 1] = gid
      end
    end
  end
  return to_remove
end

-- ── Carregamento ────────────────────────────────────────────────────────────

-- Carrega grupos do banco para entry VRAM. Aplica DEFAULT_GROUP se nao tiver nenhum.
-- Chamado em characterLoad (sempre) e em invalidacoes (sob demanda).
function Core.load_entry(src, char_id)
  local entry = Cache.register(src, char_id)
  if not entry then return nil end

  local rows = SQL.fetch_groups(char_id) or {}
  local groups = {}
  for _, row in ipairs(rows) do
    local gid = tostring(row.group_id or '')
    if gid ~= '' and Defs[gid] then
      groups[gid] = sql_row_to_cache(row)
    end
  end

  -- Aplica DEFAULT_GROUP se nao tiver nenhum
  if next(groups) == nil then
    local def_gid = Cfg.DEFAULT_GROUP
    if def_gid and Defs[def_gid] then
      SQL.upsert_group(char_id, def_gid, Cfg.DEFAULT_LEVEL or 1, 0, nil, 'default')
      groups[def_gid] = {
        level = Cfg.DEFAULT_LEVEL or 1,
        added_by = 0,
        added_at_unix = os.time(),
        expires_at_unix = nil,
        reason = 'default',
      }
      SQL.audit_insert(0, char_id, 'default_group', def_gid, Cfg.DEFAULT_LEVEL or 1, 'first_load')
    end
  end

  Cache.set_groups(entry, groups)
  notify_client(entry)
  return entry
end

-- Carrega entry por char_id (sem src — para uso admin offline)
function Core.load_entry_offline(char_id)
  local existing = Cache.by_char(char_id)
  if existing then return existing end

  local entry = Cache.register(-char_id, char_id)  -- src negativo = offline marker
  if not entry then return nil end
  entry.src = nil   -- sem src ativo
  Cache._by_src[-char_id] = nil

  local rows = SQL.fetch_groups(char_id) or {}
  local groups = {}
  for _, row in ipairs(rows) do
    local gid = tostring(row.group_id or '')
    if gid ~= '' and Defs[gid] then
      groups[gid] = sql_row_to_cache(row)
    end
  end
  Cache.set_groups(entry, groups)
  return entry
end

-- ── Mutacoes (API interna) ──────────────────────────────────────────────────

-- Adiciona grupo (ou atualiza nivel se ja existir). Aplica exclusividade por type.
-- Retorna (ok, err).
function Core.add_group(char_id, group_id, level, expires_unix, actor_char_id, reason)
  local ok, gid, lvl, err = validate(group_id, level)
  if not ok then return false, err end

  local entry = Cache.by_char(char_id) or Core.load_entry_offline(char_id)
  if not entry then return false, 'char_invalido' end

  -- Remove grupos conflitantes (exclusividade job/gang)
  local conflicts = exclusion_list(entry, gid)
  if #conflicts > 0 then
    SQL.delete_groups_in(char_id, conflicts)
    for _, conflict_gid in ipairs(conflicts) do
      Cache.remove_group(entry, conflict_gid)
      SQL.audit_insert(actor_char_id or 0, char_id, 'exclusion_removed',
                       conflict_gid, 0, 'replaced_by:' .. gid)
    end
  end

  -- Upsert SQL
  local affected = SQL.upsert_group(char_id, gid, lvl, actor_char_id or 0, expires_unix, reason)
  if not affected then return false, 'sql_falhou' end

  -- Atualiza VRAM
  Cache.upsert_group(entry, gid, {
    level = lvl,
    added_by = actor_char_id or 0,
    added_at_unix = os.time(),
    expires_at_unix = expires_unix,
    reason = reason or '',
  })

  -- Audit + notify
  SQL.audit_insert(actor_char_id or 0, char_id, 'add_group', gid, lvl, reason or '')
  notify_client(entry)
  return true
end

-- Remove grupo. Se for o ultimo, aplica DEFAULT_GROUP automaticamente.
function Core.remove_group(char_id, group_id, actor_char_id, reason)
  if type(group_id) ~= 'string' or group_id == '' then return false, 'group_id_invalido' end
  local gid = group_id:lower():gsub('[^a-z0-9_%-]', '')

  local entry = Cache.by_char(char_id) or Core.load_entry_offline(char_id)
  if not entry then return false, 'char_invalido' end
  if not entry.groups[gid] then return false, 'grupo_nao_atribuido' end

  SQL.delete_group(char_id, gid)
  Cache.remove_group(entry, gid)
  SQL.audit_insert(actor_char_id or 0, char_id, 'remove_group', gid, 0, reason or '')

  -- Se ficou sem grupo, aplica default
  if next(entry.groups) == nil then
    local def_gid = Cfg.DEFAULT_GROUP
    if def_gid and Defs[def_gid] then
      SQL.upsert_group(char_id, def_gid, Cfg.DEFAULT_LEVEL or 1, 0, nil, 'auto_default')
      Cache.upsert_group(entry, def_gid, {
        level = Cfg.DEFAULT_LEVEL or 1,
        added_by = 0,
        added_at_unix = os.time(),
        expires_at_unix = nil,
        reason = 'auto_default',
      })
      SQL.audit_insert(0, char_id, 'default_group', def_gid, Cfg.DEFAULT_LEVEL or 1, 'after_remove')
    end
  end

  notify_client(entry)
  return true
end

-- Altera nivel de um grupo existente
function Core.set_level(char_id, group_id, level, actor_char_id, reason)
  local ok, gid, lvl, err = validate(group_id, level)
  if not ok then return false, err end

  local entry = Cache.by_char(char_id) or Core.load_entry_offline(char_id)
  if not entry then return false, 'char_invalido' end
  if not entry.groups[gid] then return false, 'grupo_nao_atribuido' end

  local current = entry.groups[gid]
  current.level = lvl
  SQL.upsert_group(char_id, gid, lvl,
                   actor_char_id or current.added_by,
                   current.expires_at_unix,
                   reason or current.reason)
  Cache.upsert_group(entry, gid, current)
  SQL.audit_insert(actor_char_id or 0, char_id, 'set_level', gid, lvl, reason or '')
  notify_client(entry)
  return true
end

-- ── Queries (read-only) ─────────────────────────────────────────────────────

function Core.has_permission(src, permission)
  local entry = Cache.by_src(src)
  if not entry then return false end
  if entry.owner then return true end   -- char_id == OWNER_CHAR_ID
  return Perms.has(entry.perms, permission)
end

function Core.has_permission_by_char(char_id, permission)
  local entry = Cache.by_char(char_id)
  if not entry then
    entry = Core.load_entry_offline(char_id)
    if not entry then return false end
  end
  if entry.owner then return true end
  return Perms.has(entry.perms, permission)
end

function Core.has_group(src, group_id, min_level)
  local entry = Cache.by_src(src)
  if not entry then return false end
  local row = entry.groups[group_id]
  if not row then return false end
  return (tonumber(row.level) or 1) >= (tonumber(min_level) or 1)
end

function Core.get_group_level(src, group_id)
  local entry = Cache.by_src(src)
  if not entry then return nil end
  local row = entry.groups[group_id]
  return row and (tonumber(row.level) or 1) or nil
end

function Core.get_groups(src)
  local entry = Cache.by_src(src)
  if not entry then return {} end
  local result = {}
  for gid, row in pairs(entry.groups) do
    result[gid] = {
      level           = row.level,
      added_by        = row.added_by,
      added_at_unix   = row.added_at_unix,
      expires_at_unix = row.expires_at_unix,
      reason          = row.reason,
    }
  end
  return result
end

function Core.get_groups_by_char(char_id)
  local entry = Cache.by_char(char_id) or Core.load_entry_offline(char_id)
  if not entry then return {} end
  local result = {}
  for gid, row in pairs(entry.groups) do
    result[gid] = {
      level           = row.level,
      added_by        = row.added_by,
      added_at_unix   = row.added_at_unix,
      expires_at_unix = row.expires_at_unix,
      reason          = row.reason,
    }
  end
  return result
end

-- Lista sources online com determinado grupo (nivel minimo)
function Core.list_srcs_in_group(group_id, min_level)
  local result = {}
  local min = tonumber(min_level) or 1
  for src, entry in pairs(Cache._by_src) do
    if src > 0 then
      local row = entry.groups[group_id]
      if row and (tonumber(row.level) or 1) >= min then
        result[#result + 1] = src
      end
    end
  end
  return result
end

-- Lista sources online com determinada permissao
function Core.list_srcs_with_perm(permission)
  local result = {}
  for src, entry in pairs(Cache._by_src) do
    if src > 0 then
      if entry.owner or Perms.has(entry.perms, permission) then
        result[#result + 1] = src
      end
    end
  end
  return result
end

-- ── Helpers de identidade ───────────────────────────────────────────────────

Core.char_id_of = char_id_of
Core.src_of     = src_of
Core.log        = log
Core.notify     = notify_client
