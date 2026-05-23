-- server/admin.lua — vhub_groups
-- Net events para o painel NUI admin. Toda chamada revalida permissao no servidor.
-- L-D8 (designer): NUI nao decide regra — apenas relay de intencao.

local Cfg   = VHubGroupsCfg
local Core  = VHubGroupsCore
local SQL   = VHubGroupsSQL
local Cache = VHubGroupsCache
local Defs  = VHubGroupsDefs

-- ── Permissao admin (centralizada) ──────────────────────────────────────────

local function is_admin(src)
  src = tonumber(src) or 0
  if src <= 0 then return true end   -- console
  -- ACE direto
  if IsPlayerAceAllowed(src, Cfg.ADMIN_ACE) then return true end
  -- Owner (char_id == 1)
  local entry = Cache.by_src(src)
  if entry and entry.owner then return true end
  -- Permissao via grupo
  if Core.has_permission(src, Cfg.ADMIN_PERMISSION) then return true end
  return false
end

-- ── Snapshots para o NUI (read-only) ────────────────────────────────────────

-- Catalogo de grupos (sem dados de jogadores). Pode ser cacheado no cliente.
local function catalog()
  local out = {}
  for gid, def in pairs(Defs) do
    local levels = {}
    for lvl, row in pairs(def.levels or {}) do
      levels[#levels + 1] = {
        level       = tonumber(lvl) or 1,
        label       = tostring(row.label or ''),
        permissions = row.permissions or {},
      }
    end
    table.sort(levels, function(a, b) return a.level < b.level end)
    out[#out + 1] = {
      id     = gid,
      label  = def.label,
      type   = def.type,
      color  = def.color,
      icon   = def.icon,
      levels = levels,
      max_level = #levels,
    }
  end
  table.sort(out, function(a, b)
    if a.type ~= b.type then return a.type < b.type end
    return a.label < b.label
  end)
  return out
end

-- Lista jogadores online com seus grupos atuais
local function players_online()
  local out = {}
  for src, entry in pairs(Cache._by_src) do
    if src > 0 then
      local groups = {}
      for gid, row in pairs(entry.groups) do
        groups[#groups + 1] = {
          id    = gid,
          level = row.level,
          expires_at_unix = row.expires_at_unix,
          label = Defs[gid] and Defs[gid].label or gid,
          type  = Defs[gid] and Defs[gid].type  or 'system',
        }
      end
      table.sort(groups, function(a, b) return a.id < b.id end)
      out[#out + 1] = {
        src     = src,
        char_id = entry.char_id,
        owner   = entry.owner == true,
        name    = GetPlayerName(src) or ('player_' .. src),
        groups  = groups,
      }
    end
  end
  table.sort(out, function(a, b) return a.src < b.src end)
  return out
end

-- ── Net events ──────────────────────────────────────────────────────────────

RegisterNetEvent('vhub_groups:admin:open', function()
  local src = source
  if not is_admin(src) then return end
  -- Envia snapshot completo
  TriggerClientEvent('vhub_groups:admin:opened', src, {
    catalog = catalog(),
    players = players_online(),
    owner_char_id = Cfg.OWNER_CHAR_ID,
  })
end)

-- Atualiza lista de players (sem reload do catalog)
RegisterNetEvent('vhub_groups:admin:refresh_players', function()
  local src = source
  if not is_admin(src) then return end
  TriggerClientEvent('vhub_groups:admin:players', src, players_online())
end)

-- Adicionar grupo (payload: { target_char_id, group_id, level, expires_days?, reason? })
RegisterNetEvent('vhub_groups:admin:add', function(payload)
  local src = source
  if not is_admin(src) then return end
  if type(payload) ~= 'table' then return end

  local target = tonumber(payload.target_char_id)
  if not target or target <= 0 then
    TriggerClientEvent('vhub_groups:admin:result', src, { ok = false, err = 'target_invalido' })
    return
  end

  local expires_unix = nil
  local days = tonumber(payload.expires_days)
  if days and days > 0 then
    expires_unix = os.time() + math.floor(days * 86400)
  end

  local actor = Core.char_id_of(src) or 0
  local ok, err = Core.add_group(
    target,
    payload.group_id,
    payload.level or 1,
    expires_unix,
    actor,
    tostring(payload.reason or 'admin_panel')
  )
  TriggerClientEvent('vhub_groups:admin:result', src, {
    ok = ok, err = err,
    target_char_id = target,
    action = 'add',
  })
  -- Refresh do painel (snapshot incremental)
  TriggerClientEvent('vhub_groups:admin:players', src, players_online())
end)

-- Remover grupo
RegisterNetEvent('vhub_groups:admin:remove', function(payload)
  local src = source
  if not is_admin(src) then return end
  if type(payload) ~= 'table' then return end

  local target = tonumber(payload.target_char_id)
  if not target or target <= 0 then return end

  local actor = Core.char_id_of(src) or 0
  local ok, err = Core.remove_group(
    target,
    payload.group_id,
    actor,
    tostring(payload.reason or 'admin_panel')
  )
  TriggerClientEvent('vhub_groups:admin:result', src, {
    ok = ok, err = err,
    target_char_id = target,
    action = 'remove',
  })
  TriggerClientEvent('vhub_groups:admin:players', src, players_online())
end)

-- Mudar nivel
RegisterNetEvent('vhub_groups:admin:set_level', function(payload)
  local src = source
  if not is_admin(src) then return end
  if type(payload) ~= 'table' then return end

  local target = tonumber(payload.target_char_id)
  if not target or target <= 0 then return end

  local actor = Core.char_id_of(src) or 0
  local ok, err = Core.set_level(
    target,
    payload.group_id,
    payload.level,
    actor,
    tostring(payload.reason or 'admin_panel')
  )
  TriggerClientEvent('vhub_groups:admin:result', src, {
    ok = ok, err = err,
    target_char_id = target,
    action = 'set_level',
  })
  TriggerClientEvent('vhub_groups:admin:players', src, players_online())
end)

-- Audit log (read-only)
RegisterNetEvent('vhub_groups:admin:audit', function(filters)
  local src = source
  if not is_admin(src) then return end
  local rows = SQL.audit_fetch(filters or {}, Cfg.AUDIT_LIMIT_DEFAULT)
  TriggerClientEvent('vhub_groups:admin:audit_data', src, rows)
end)

-- Status do sistema (cache, sql, metricas)
RegisterNetEvent('vhub_groups:admin:status', function()
  local src = source
  if not is_admin(src) then return end
  TriggerClientEvent('vhub_groups:admin:status_data', src, {
    sql_ready = SQL.ready == true,
    core_ready = Core.is_ready(),
    cache = Cache.status(),
    owner_char_id = Cfg.OWNER_CHAR_ID,
    expire_interval_ms = Cfg.EXPIRE_CHECK_INTERVAL_MS,
  })
end)

-- Resposta a /meusgrupos (jogador comum — ve apenas os proprios)
RegisterNetEvent('vhub_groups:self:get', function()
  local src = source
  local entry = Cache.by_src(src)
  if not entry then
    TriggerClientEvent('vhub_groups:self:data', src, { groups = {}, owner = false })
    return
  end
  local groups = {}
  for gid, row in pairs(entry.groups) do
    groups[#groups + 1] = {
      id    = gid,
      level = row.level,
      label = Defs[gid] and Defs[gid].label or gid,
      type  = Defs[gid] and Defs[gid].type  or 'system',
      color = Defs[gid] and Defs[gid].color or '#d9c19a',
      icon  = Defs[gid] and Defs[gid].icon  or 'fa-solid fa-user',
      expires_at_unix = row.expires_at_unix,
    }
  end
  table.sort(groups, function(a, b) return a.label < b.label end)
  TriggerClientEvent('vhub_groups:self:data', src, {
    groups = groups,
    owner  = entry.owner == true,
  })
end)

-- ── Comandos de console (admin offline / debug) ─────────────────────────────

RegisterCommand('vhub_groups_status', function(src)
  if src ~= 0 and not is_admin(src) then return end
  local st = Cache.status()
  print(("[vhub_groups] entries=%d hits=%d misses=%d loads=%d invals=%d"):format(
    st.entries, st.metrics.hits, st.metrics.misses, st.metrics.loads, st.metrics.invalidations))
end, true)

RegisterCommand('vhub_setgroup', function(src, args)
  if src ~= 0 and not is_admin(src) then return end
  local char_id  = tonumber(args[1])
  local group_id = args[2]
  local level    = tonumber(args[3]) or 1
  if not char_id or not group_id then
    print('[vhub_groups] Uso: vhub_setgroup <char_id> <grupo> [nivel] [dias_expira]')
    return
  end
  local days = tonumber(args[4])
  local exp  = days and days > 0 and (os.time() + math.floor(days * 86400)) or nil
  local actor = src > 0 and (Core.char_id_of(src) or 0) or 0
  local ok, err = Core.add_group(char_id, group_id, level, exp, actor, 'console_cmd')
  print(("[vhub_groups] add %s lvl=%d → char=%d: %s"):format(
    group_id, level, char_id, ok and 'OK' or ('FAIL: ' .. tostring(err))))
end, true)

RegisterCommand('vhub_unsetgroup', function(src, args)
  if src ~= 0 and not is_admin(src) then return end
  local char_id  = tonumber(args[1])
  local group_id = args[2]
  if not char_id or not group_id then
    print('[vhub_groups] Uso: vhub_unsetgroup <char_id> <grupo>')
    return
  end
  local actor = src > 0 and (Core.char_id_of(src) or 0) or 0
  local ok, err = Core.remove_group(char_id, group_id, actor, 'console_cmd')
  print(("[vhub_groups] remove %s → char=%d: %s"):format(
    group_id, char_id, ok and 'OK' or ('FAIL: ' .. tostring(err))))
end, true)
