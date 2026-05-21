-- vhub_groups/server.lua
-- Responsabilidade: grupos e permissões por personagem.
-- Integração vHub: grupos ficam em user.data.groups (persistido no datatable).
--   Permissões são mapeadas para vHub.Kernel:grantPerm/revokePerm.
-- Autoridade: servidor — cliente jamais concede permissões.

local _vHub   = nil
local _pronto = false
local function vHub() return _vHub end

-- ── Configuração ──────────────────────────────────────────────────────────────

local CFG = {
  grupos_padrao = { "usuario" },   -- aplicados a todos no primeiro acesso

  -- uid → lista de grupos forçados (uid=1 = primeiro user criado)
  grupos_por_uid = {
    [1] = { "superadmin", "admin" },
  },

  -- _config: { title, gtype, onjoin(user), onleave(user), onspawn(user) }
  -- gtype: mutuamente exclusivo (ex: só 1 grupo com gtype="trabalho" por vez)
  -- permissão negativa: "-perm" bloqueia mesmo que outro grupo conceda
  grupos = {
    ["superadmin"] = {
      _config = { title = "Super Admin" },
      "admin.full",
      "player.group.add", "player.group.remove",
      "player.givemoney",  "player.giveitem",
      "player.kick",       "player.ban",     "player.unban",
      "player.tptome",     "player.tpto",    "player.coords",
      "player.noclip",     "player.list",
      "player.whitelist",  "player.unwhitelist",
    },
    ["admin"] = {
      _config = { title = "Admin" },
      "admin.tickets", "admin.announce",
      "player.list",   "player.kick",
      "player.ban",    "player.unban",
      "player.whitelist", "player.unwhitelist",
      "player.noclip", "player.coords",
      "player.tptome", "player.tpto",
      "player.custom_model",
    },
    ["usuario"] = {
      _config = { title = "Usuário" },
      "player.characters",
      "police.seizable",
    },
    ["policia"] = {
      _config = {
        title  = "Polícia",
        gtype  = "trabalho",
        onjoin = function(user)
          -- Equipamentos ao entrar no grupo de polícia
          if exports.vhub_player_state then
            exports.vhub_player_state:giveWeapons({
              WEAPON_STUNGUN       = { ammo = 1000 },
              WEAPON_COMBATPISTOL  = { ammo = 100  },
              WEAPON_NIGHTSTICK    = { ammo = 0    },
              WEAPON_FLASHLIGHT    = { ammo = 0    },
            }, true)
            exports.vhub_player_state:setArmour(user.source, 100)
          end
        end,
        onleave = function(user)
          -- Remove equipamentos ao sair
          if exports.vhub_player_state then
            exports.vhub_player_state:giveWeapons(user.source, {}, true)
            exports.vhub_player_state:setArmour(user.source, 0)
          end
        end,
        onspawn = function(user)
          -- Reequipa ao spawnar (persistência de armas fica no player_state)
        end,
      },
      "police.menu", "police.askid",   "police.handcuff",
      "police.check","police.wanted",  "police.fine",
      "police.jail", "police.vehicle", "police.seize",
      "-police.seizable",          -- policial não pode ser revistado
      "-player.store_weapons",     -- policial não guarda armas normalmente
    },
    ["emergencia"] = {
      _config = { title = "Emergência", gtype = "trabalho" },
      "emergency.revive", "emergency.shop", "emergency.vehicle",
    },
    ["mecanico"] = {
      _config = { title = "Mecânico", gtype = "trabalho" },
      "vehicle.repair", "vehicle.replace",
    },
    ["taxi"] = {
      _config = { title = "Taxista", gtype = "trabalho" },
      "taxi.service", "taxi.vehicle",
    },
    ["cidadao"] = {
      _config = { title = "Cidadão", gtype = "trabalho" },
    },
  },
}

-- ── Inicialização ─────────────────────────────────────────────────────────────

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    local tentativas = 0
    while tentativas < 50 do
      local ok, vh = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(vh) == "table" and vh.Auth then
        _vHub   = vh
        _pronto = true
        print("[vhub_groups] Pronto.")
        return
      end
      Citizen.Wait(200); tentativas = tentativas + 1
    end
    print("[vhub_groups][ERRO] vHub não disponível após 10s")
  end)
end)

-- ── Helpers internos ──────────────────────────────────────────────────────────

local function ensureGroups(user)
  if not user.data.groups then user.data.groups = {} end
  return user.data.groups
end

local function temGrupo(user, nome)
  return ensureGroups(user)[nome] == true
end

-- Remove todos os grupos do mesmo gtype (exclusividade)
local function limparGtype(user, gtype)
  if not gtype then return end
  local grupos = ensureGroups(user)
  for nome in pairs(grupos) do
    local gcfg = CFG.grupos[nome]
    if gcfg and gcfg._config and gcfg._config.gtype == gtype then
      if gcfg._config.onleave then pcall(gcfg._config.onleave, user) end
      -- Remove permissões do grupo saído
      for _, perm in ipairs(gcfg) do
        if type(perm) == "string" and perm:sub(1,1) ~= "-" then
          vHub().Kernel:revokePerm(user.id, perm)
        end
      end
      grupos[nome] = nil
    end
  end
end

local function adicionarGrupo(user, nome)
  if temGrupo(user, nome) then return false end
  local gcfg = CFG.grupos[nome]
  if not gcfg then
    print(("[vhub_groups] Grupo não definido: '%s'"):format(tostring(nome)))
    return false
  end

  -- Remove grupos conflitantes (mesmo gtype)
  if gcfg._config then limparGtype(user, gcfg._config.gtype) end

  -- Marca grupo ativo
  ensureGroups(user)[nome] = true

  -- Aplica permissões positivas no Kernel do vHub
  for _, perm in ipairs(gcfg) do
    if type(perm) == "string" and perm:sub(1,1) ~= "-" then
      vHub().Kernel:grantPerm(user.id, perm)
    end
  end

  -- Callback onjoin
  if gcfg._config and gcfg._config.onjoin then
    pcall(gcfg._config.onjoin, user)
  end

  return true
end

local function removerGrupo(user, nome)
  if not temGrupo(user, nome) then return false end
  local gcfg = CFG.grupos[nome]
  ensureGroups(user)[nome] = nil

  if gcfg then
    -- Remove permissões
    for _, perm in ipairs(gcfg) do
      if type(perm) == "string" and perm:sub(1,1) ~= "-" then
        vHub().Kernel:revokePerm(user.id, perm)
      end
    end
    -- Callback onleave
    if gcfg._config and gcfg._config.onleave then
      pcall(gcfg._config.onleave, user)
    end
  end
  return true
end

-- Verifica permissão respeitando negativos de qualquer grupo
local function temPermissao(user, perm)
  local grupos = ensureGroups(user)

  -- 1. Verifica permissões negativas — prioridade absoluta
  local nperm = "-" .. perm
  for nome in pairs(grupos) do
    local gcfg = CFG.grupos[nome]
    if gcfg then
      for _, p in ipairs(gcfg) do
        if p == nperm then return false end
      end
    end
  end

  -- 2. Verifica permissões positivas nos grupos
  for nome in pairs(grupos) do
    local gcfg = CFG.grupos[nome]
    if gcfg then
      for _, p in ipairs(gcfg) do
        if p == perm then return true end
      end
    end
  end

  -- 3. Fallback: permissões concedidas diretamente pelo Kernel (ex: admin ACE)
  return vHub().Kernel:hasPerm(user.id, perm)
end

-- ── Eventos vHub ─────────────────────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  if not user or not _pronto then return end

  ensureGroups(user)  -- garante tabela existe

  -- Grupos forçados por uid (superadmin/admin para uid=1)
  local by_uid = CFG.grupos_por_uid[user.id]
  if by_uid then
    for _, nome in ipairs(by_uid) do adicionarGrupo(user, nome) end
  end

  -- Grupos padrão para todos
  for _, nome in ipairs(CFG.grupos_padrao) do
    adicionarGrupo(user, nome)
  end

  -- Restaura grupos salvos no datatable (sessões anteriores)
  -- Itera sobre cópia para evitar modificar durante iteração
  local saved = {}
  for k, v in pairs(user.data.groups) do saved[k] = v end
  for nome in pairs(saved) do
    if not temGrupo(user, nome) then adicionarGrupo(user, nome) end
  end
end)

-- Dispara callbacks onspawn dos grupos ao spawnar
AddEventHandler("vHub:playerSpawn", function(user, first_spawn)
  if not user or not _pronto then return end
  for nome in pairs(ensureGroups(user)) do
    local gcfg = CFG.grupos[nome]
    if gcfg and gcfg._config and gcfg._config.onspawn then
      pcall(gcfg._config.onspawn, user)
    end
  end
end)

-- ── Net events (admin) ────────────────────────────────────────────────────────

RegisterNetEvent("vhub_groups:admin_add")
AddEventHandler("vhub_groups:admin_add", function(target_src, nome)
  local src  = source
  if not _pronto then return end
  local user = vHub().Auth:getUser(src)
  if not user or not temPermissao(user, "player.group.add") then return end
  local tuser = vHub().Auth:getUser(tonumber(target_src))
  if tuser then adicionarGrupo(tuser, nome) end
end)

RegisterNetEvent("vhub_groups:admin_remove")
AddEventHandler("vhub_groups:admin_remove", function(target_src, nome)
  local src  = source
  if not _pronto then return end
  local user = vHub().Auth:getUser(src)
  if not user or not temPermissao(user, "player.group.remove") then return end
  local tuser = vHub().Auth:getUser(tonumber(target_src))
  if tuser then removerGrupo(tuser, nome) end
end)

-- ── Exports públicos ──────────────────────────────────────────────────────────

exports("addGroup", function(src, nome)
  if not _pronto then return false end
  local user = _vHub.Auth:getUser(src)
  return user and adicionarGrupo(user, nome) or false
end)

exports("removeGroup", function(src, nome)
  if not _pronto then return false end
  local user = _vHub.Auth:getUser(src)
  return user and removerGrupo(user, nome) or false
end)

exports("hasGroup", function(src, nome)
  if not _pronto then return false end
  local user = _vHub.Auth:getUser(src)
  return user and temGrupo(user, nome) or false
end)

exports("hasPermission", function(src, perm)
  if not _pronto then return false end
  local user = _vHub.Auth:getUser(src)
  return user and temPermissao(user, perm) or false
end)

exports("getGroups", function(src)
  if not _pronto then return {} end
  local user = _vHub.Auth:getUser(src)
  if not user then return {} end
  return ensureGroups(user)
end)

-- Retorna lista de sources de jogadores com determinado grupo
exports("getUsersByGroup", function(nome)
  if not _pronto then return {} end
  local result = {}
  for _, user in pairs(_vHub.Auth._sessions) do
    if temGrupo(user, nome) then
      result[#result+1] = user.source
    end
  end
  return result
end)

-- Retorna lista de sources com determinada permissão
exports("getUsersByPermission", function(perm)
  if not _pronto then return {} end
  local result = {}
  for _, user in pairs(_vHub.Auth._sessions) do
    if temPermissao(user, perm) then
      result[#result+1] = user.source
    end
  end
  return result
end)

-- Expõe CFG para outros módulos lerem definições de grupos
exports("getGroupConfig", function()
  return CFG.grupos
end)
