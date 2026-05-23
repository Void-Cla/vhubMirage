-- shared/permissions.lua — vhub_groups
-- Helpers de permissao puros. Sem side-effects, sem SQL, sem IO.
-- Centraliza calculo de:
--   - permission set hierarquico (nivel N herda 1..N-1)
--   - merge de sets de multiplos grupos
--   - check com suporte a wildcards: '*' (super) e 'prefix.*'
--   - extracao de wildcards uma unica vez (cache lazy por set)

VHubGroupsPerms = {}
local M = VHubGroupsPerms

-- Le levels do grupo das definitions; retorna tabela ou nil
local function get_levels(group_id)
  local def = VHubGroupsDefs and VHubGroupsDefs[group_id]
  if type(def) ~= 'table' or type(def.levels) ~= 'table' then return nil end
  return def.levels
end

-- Retorna nivel maximo definido do grupo (0 se nao houver)
function M.max_level(group_id)
  local levels = get_levels(group_id)
  if not levels then return 0 end
  local max = 0
  for k, _ in pairs(levels) do
    local n = tonumber(k) or 0
    if n > max then max = n end
  end
  return max
end

-- Clampa nivel ao range valido do grupo (1..max). Retorna nil se grupo invalido.
function M.clamp(group_id, level)
  local max = M.max_level(group_id)
  if max <= 0 then return nil end
  local n = math.floor(tonumber(level) or 1)
  if n < 1   then n = 1 end
  if n > max then n = max end
  return n
end

-- Constroi set de permissoes acumuladas para nivel N do grupo.
-- Retorna tabela { ['perm.id'] = true, ... } incluindo herdadas dos niveis inferiores.
function M.build_set(group_id, level)
  local levels = get_levels(group_id)
  if not levels then return {} end

  local n = M.clamp(group_id, level)
  if not n then return {} end

  local result = {}
  for idx = 1, n do
    local row = levels[idx]
    if type(row) == 'table' and type(row.permissions) == 'table' then
      for _, perm in ipairs(row.permissions) do
        if type(perm) == 'string' and perm ~= '' then
          result[perm] = true
        end
      end
    end
  end
  return result
end

-- Combina sets in-place: source → target.
function M.merge(target, source)
  if type(target) ~= 'table' then target = {} end
  if type(source) == 'table' then
    for perm, allowed in pairs(source) do
      if allowed == true then target[perm] = true end
    end
  end
  return target
end

-- Extrai wildcards de prefixo do set ('foo.*' → 'foo.'). Retorna lista de prefixos.
-- O resultado e armazenado no proprio set como _wildcards (computado 1x).
local function extract_wildcards(set)
  if set._wildcards then return set._wildcards end
  local wl = {}
  for key, allowed in pairs(set) do
    if allowed == true and type(key) == 'string'
       and #key > 2 and key:sub(-2) == '.*' then
      wl[#wl + 1] = key:sub(1, #key - 1)   -- mantem ponto final ('foo.')
    end
  end
  set._wildcards = wl
  return wl
end

-- Verifica permissao no set. Suporta:
--   '*' como super-permissao
--   'prefix.*' como wildcard de prefixo
--   match exato como ultimo recurso
function M.has(set, permission)
  if type(set) ~= 'table' then return false end
  local perm = tostring(permission or '')
  if perm == '' then return false end

  -- Super-permissao
  if set['*'] == true then return true end

  -- Match exato
  if set[perm] == true then return true end

  -- Wildcards de prefixo
  local wl = extract_wildcards(set)
  if #wl == 0 then return false end
  for i = 1, #wl do
    local prefix = wl[i]
    if perm:sub(1, #prefix) == prefix then return true end
  end
  return false
end

-- Constroi set consolidado a partir de uma lista de grupos { [group_id]={level=N} }
-- Aplica owner_permission se o flag is_owner == true (atalho para char_id==1).
function M.compile(groups, is_owner)
  local final = {}
  if is_owner == true then
    final[VHubGroupsCfg.OWNER_PERMISSION or '*'] = true
  end
  if type(groups) ~= 'table' then return final end

  for group_id, row in pairs(groups) do
    if type(row) == 'table' then
      local level = tonumber(row.level) or 1
      local set = M.build_set(group_id, level)
      M.merge(final, set)
    end
  end
  return final
end
