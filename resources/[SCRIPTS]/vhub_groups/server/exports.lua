-- server/exports.lua — vhub_groups
-- API publica para outros resources. Mutacoes sao protegidas por _invoker_allowed().
--
-- Read-only (publicos):
--   hasGroup(src, group_id, [min_level])         → bool
--   hasPermission(src, permission)               → bool
--   getGroups(src)                               → { [group_id] = {level, ...}, ... }
--   getGroupLevel(src, group_id)                 → number | nil
--   getUsersByGroup(group_id, [min_level])       → { src, src, ... }
--   getUsersByPermission(permission)             → { src, src, ... }
--   isOwner(src)                                 → bool
--   getCatalog()                                 → lista de groups definidos
--
-- Por char_id (offline + online):
--   hasPermissionByChar(char_id, permission)     → bool
--   getGroupsByChar(char_id)                     → { [group_id] = {level, ...}, ... }
--
-- Mutacoes (TRUSTED — _invoker_allowed):
--   addGroup(src_or_char, group_id, level, [expires_days], [reason]) → ok, err
--   removeGroup(src_or_char, group_id, [reason])                     → ok, err
--   setGroupLevel(src_or_char, group_id, level, [reason])            → ok, err
--   addGroupByChar(char_id, ...)  / removeGroupByChar / setLevelByChar
--
-- Auditoria:
--   getAuditLog(filters, [limit])  → rows  (apenas TRUSTED)

local Cfg   = VHubGroupsCfg
local Core  = VHubGroupsCore
local SQL   = VHubGroupsSQL
local Cache = VHubGroupsCache
local Defs  = VHubGroupsDefs

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return true end   -- chamada local
  local trusted = Cfg.TRUSTED_RESOURCES
  if type(trusted) ~= 'table' or next(trusted) == nil then
    return true   -- lista vazia = publico
  end
  return trusted[caller] == true
end

-- Resolve para char_id: aceita src (number positivo) ou char_id (number qualquer)
-- Heuristica: src > 0 e < 1000 e PROVAVEL src; > 1000 e char_id. Para resolver
-- ambiguidade real, exports tem variantes ByChar explicitas.
local function to_char_id(src_or_char)
  local n = tonumber(src_or_char)
  if not n or n <= 0 then return nil end
  -- Tenta como src primeiro (cache hit O(1))
  local entry = Cache.by_src(n)
  if entry then return entry.char_id end
  -- Senao, trata como char_id
  return n
end

-- ── Read-only (publicos) ────────────────────────────────────────────────────

exports('hasGroup', function(src, group_id, min_level)
  return Core.has_group(tonumber(src) or 0, group_id, min_level)
end)

exports('hasPermission', function(src, permission)
  return Core.has_permission(tonumber(src) or 0, permission)
end)

exports('getGroups', function(src)
  return Core.get_groups(tonumber(src) or 0)
end)

exports('getGroupLevel', function(src, group_id)
  return Core.get_group_level(tonumber(src) or 0, group_id)
end)

exports('getUsersByGroup', function(group_id, min_level)
  return Core.list_srcs_in_group(group_id, min_level)
end)

exports('getUsersByPermission', function(permission)
  return Core.list_srcs_with_perm(permission)
end)

exports('isOwner', function(src)
  local entry = Cache.by_src(tonumber(src) or 0)
  return entry and entry.owner == true or false
end)

exports('getCatalog', function()
  local out = {}
  for gid, def in pairs(Defs) do
    out[#out + 1] = {
      id    = gid,
      label = def.label,
      type  = def.type,
      color = def.color,
      icon  = def.icon,
      max_level = #(def.levels or {}),
    }
  end
  return out
end)

-- ── Por char_id (publicos para read, online+offline) ────────────────────────

exports('hasPermissionByChar', function(char_id, permission)
  return Core.has_permission_by_char(tonumber(char_id) or 0, permission)
end)

exports('getGroupsByChar', function(char_id)
  return Core.get_groups_by_char(tonumber(char_id) or 0)
end)

-- ── Mutacoes (TRUSTED) ──────────────────────────────────────────────────────

exports('addGroup', function(src_or_char, group_id, level, expires_days, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  local char_id = to_char_id(src_or_char)
  if not char_id then return false, 'target_invalido' end
  local exp = nil
  local days = tonumber(expires_days)
  if days and days > 0 then exp = os.time() + math.floor(days * 86400) end
  return Core.add_group(char_id, group_id, level or 1, exp, 0, reason or 'export')
end)

exports('removeGroup', function(src_or_char, group_id, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  local char_id = to_char_id(src_or_char)
  if not char_id then return false, 'target_invalido' end
  return Core.remove_group(char_id, group_id, 0, reason or 'export')
end)

exports('setGroupLevel', function(src_or_char, group_id, level, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  local char_id = to_char_id(src_or_char)
  if not char_id then return false, 'target_invalido' end
  return Core.set_level(char_id, group_id, level, 0, reason or 'export')
end)

-- Variantes explicitas por char_id (sem heuristica)
exports('addGroupByChar', function(char_id, group_id, level, expires_days, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  local cid = tonumber(char_id)
  if not cid or cid <= 0 then return false, 'char_id_invalido' end
  local exp = nil
  local days = tonumber(expires_days)
  if days and days > 0 then exp = os.time() + math.floor(days * 86400) end
  return Core.add_group(cid, group_id, level or 1, exp, 0, reason or 'export_char')
end)

exports('removeGroupByChar', function(char_id, group_id, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  local cid = tonumber(char_id)
  if not cid or cid <= 0 then return false, 'char_id_invalido' end
  return Core.remove_group(cid, group_id, 0, reason or 'export_char')
end)

exports('setLevelByChar', function(char_id, group_id, level, reason)
  if not _invoker_allowed() then return false, 'forbidden' end
  local cid = tonumber(char_id)
  if not cid or cid <= 0 then return false, 'char_id_invalido' end
  return Core.set_level(cid, group_id, level, 0, reason or 'export_char')
end)

-- Auditoria (apenas TRUSTED)
exports('getAuditLog', function(filters, limit)
  if not _invoker_allowed() then return {} end
  return SQL.audit_fetch(filters or {}, limit or Cfg.AUDIT_LIMIT_DEFAULT)
end)

-- Diagnostico
exports('status', function()
  return {
    sql_ready  = SQL.ready,
    core_ready = Core.is_ready(),
    cache      = Cache.status(),
  }
end)
