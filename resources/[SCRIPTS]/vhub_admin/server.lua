-- vhub_admin/server.lua

local _vHub   = nil
local _pronto = false

-- ── Permissão ─────────────────────────────────────────────────────────────────

local function temPerm(src, perm)
  -- uid=1 → irrestrito (export retorna número simples, funciona cross-resource)
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  if ok and uid == 1 then return true end
  -- grupo admin via vhub_groups
  local ok2, r = pcall(function() return exports.vhub_groups:hasPermission(src, perm) end)
  if ok2 and r then return true end
  -- ACE fallback
  if IsPlayerAceAllowed then return IsPlayerAceAllowed(src, "vhub." .. perm) end
  return false
end

local function auditoria(src, acao, alvo, detalhes)
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  print(("[ADMIN] uid=%s acao=%s alvo=%s %s"):format(
    tostring((ok and uid) or 0), acao, tostring(alvo), detalhes or ""))
end

-- Retorna coords server-side de um player (evita roundtrip client)
local function playerCoords(src)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  return GetEntityCoords(ped)
end

-- ── Init ──────────────────────────────────────────────────────────────────────

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    for _ = 1, 50 do
      local ok, vh = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(vh) == "table" and vh.Auth then
        _vHub = vh
        _pronto = true
        print("[vhub_admin] Pronto.")
        return
      end
      Citizen.Wait(200)
    end
    print("[vhub_admin][ERRO] vHub não disponível após 10s")
  end)
end)

-- ── Verificação de painel (com perm) ─────────────────────────────────────────

RegisterNetEvent("vhub_admin:open_panel")
AddEventHandler("vhub_admin:open_panel", function()
  local src = source
  if not _pronto then return end
  if not temPerm(src, "panel.open") then
    TriggerClientEvent("vhub_admin:notify", src, "Sem permissão de administrador.")
    return
  end
  TriggerClientEvent("vhub_admin:panel_allowed", src)
end)

-- ── Kick ──────────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:kick")
AddEventHandler("vhub_admin:kick", function(target_src, motivo)
  local src = source
  if not _pronto or not temPerm(src, "player.kick") then return end
  target_src = tonumber(target_src)
  DropPlayer(target_src, motivo or "Kicked by admin.")
  auditoria(src, "kick", target_src, motivo)
end)

-- ── Ban ───────────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:ban")
AddEventHandler("vhub_admin:ban", function(target_src, motivo)
  local src = source
  if not _pronto or not temPerm(src, "player.ban") then return end
  target_src = tonumber(target_src)
  local tuser = _vHub.Auth:getUser(target_src)
  if tuser then
    local user = _vHub.Auth:getUser(src)
    _vHub.Auth:ban(tuser.id, motivo or "Banido.", user and user.id or "admin")
    TriggerClientEvent("vhub_admin:notify", src,
      ("Jogador [%d] uid=%d banido."):format(target_src, tuser.id))
    auditoria(src, "ban", target_src, motivo)
  end
end)

-- ── Unban ─────────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:unban")
AddEventHandler("vhub_admin:unban", function(uid)
  local src = source
  if not _pronto or not temPerm(src, "player.unban") then return end
  uid = tonumber(uid)
  if uid then
    _vHub.Auth:unban(uid)
    TriggerClientEvent("vhub_admin:notify", src, ("uid=%d desbanido."):format(uid))
    auditoria(src, "unban", uid)
  end
end)

-- ── Whitelist ─────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:whitelist")
AddEventHandler("vhub_admin:whitelist", function(target_src)
  local src = source
  if not _pronto or not temPerm(src, "player.whitelist") then return end
  target_src = tonumber(target_src)
  local tuser = _vHub.Auth:getUser(target_src)
  if tuser then
    tuser.data.whitelisted = true
    TriggerClientEvent("vhub_admin:notify", src,
      ("[%d] uid=%d adicionado à whitelist."):format(target_src, tuser.id))
    TriggerClientEvent("vhub_admin:notify", target_src,
      "Você foi adicionado à whitelist do servidor.")
    auditoria(src, "whitelist", target_src)
  end
end)

RegisterNetEvent("vhub_admin:unwhitelist")
AddEventHandler("vhub_admin:unwhitelist", function(target_src)
  local src = source
  if not _pronto or not temPerm(src, "player.whitelist") then return end
  target_src = tonumber(target_src)
  local tuser = _vHub.Auth:getUser(target_src)
  if tuser then
    tuser.data.whitelisted = false
    TriggerClientEvent("vhub_admin:notify", src,
      ("[%d] uid=%d removido da whitelist."):format(target_src, tuser.id))
    auditoria(src, "unwhitelist", target_src)
  end
end)

-- ── Teleporte admin → alvo ────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:tptome")
AddEventHandler("vhub_admin:tptome", function(target_src)
  local src = source
  if not _pronto or not temPerm(src, "player.tptome") then return end
  target_src = tonumber(target_src)
  local coords = playerCoords(target_src)
  if not coords then
    TriggerClientEvent("vhub_admin:notify", src, "Jogador não encontrado.")
    return
  end
  TriggerClientEvent("vhub_admin:do_tp", src, coords.x, coords.y + 2.0, coords.z)
  auditoria(src, "tptome", target_src)
end)

-- ── Trazer jogador ao admin (bring) ───────────────────────────────────────────

RegisterNetEvent("vhub_admin:bring")
AddEventHandler("vhub_admin:bring", function(target_src)
  local src = source
  if not _pronto or not temPerm(src, "player.bring") then return end
  target_src = tonumber(target_src)
  local coords = playerCoords(src)
  if not coords then
    TriggerClientEvent("vhub_admin:notify", src, "Não foi possível obter sua posição.")
    return
  end
  TriggerClientEvent("vhub_admin:do_tp", target_src, coords.x, coords.y + 2.0, coords.z)
  TriggerClientEvent("vhub_admin:notify", target_src,
    "Você foi teleportado por um administrador.")
  auditoria(src, "bring", target_src)
end)

-- ── God mode ─────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:god")
AddEventHandler("vhub_admin:god", function()
  local src = source
  if not _pronto or not temPerm(src, "player.god") then return end
  TriggerClientEvent("vhub_admin:toggle_god", src)
  auditoria(src, "god", src)
end)

-- ── Heal ──────────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:heal")
AddEventHandler("vhub_admin:heal", function(target_src)
  local src = source
  if not _pronto or not temPerm(src, "player.heal") then return end
  target_src = tonumber(target_src) or src
  TriggerClientEvent("vhub_admin:do_heal", target_src)
  if target_src ~= src then
    TriggerClientEvent("vhub_admin:notify", src,
      ("Jogador [%d] curado."):format(target_src))
    TriggerClientEvent("vhub_admin:notify", target_src,
      "Você foi curado por um administrador.")
  end
  auditoria(src, "heal", target_src)
end)

-- ── Freeze ────────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:freeze")
AddEventHandler("vhub_admin:freeze", function(target_src)
  local src = source
  if not _pronto or not temPerm(src, "player.freeze") then return end
  target_src = tonumber(target_src)
  TriggerClientEvent("vhub_admin:toggle_freeze", target_src)
  TriggerClientEvent("vhub_admin:notify", src,
    ("Jogador [%d] freeze toggled."):format(target_src))
  auditoria(src, "freeze", target_src)
end)

-- ── Spawn veículo (server valida, client spawna) ──────────────────────────────

RegisterNetEvent("vhub_admin:spawncar")
AddEventHandler("vhub_admin:spawncar", function(modelo)
  local src = source
  if not _pronto or not temPerm(src, "player.spawncar") then return end
  modelo = tostring(modelo or "adder"):lower()
  TriggerClientEvent("vhub_admin:do_spawncar", src, modelo)
  auditoria(src, "spawncar", src, modelo)
end)

-- ── Deletar veículo ───────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:delveh")
AddEventHandler("vhub_admin:delveh", function()
  local src = source
  if not _pronto or not temPerm(src, "player.delveh") then return end
  TriggerClientEvent("vhub_admin:do_delveh", src)
end)

-- ── Dar dinheiro ──────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:givemoney")
AddEventHandler("vhub_admin:givemoney", function(target_src, valor)
  local src = source
  if not _pronto or not temPerm(src, "player.givemoney") then return end
  target_src = tonumber(target_src)
  valor = math.floor(math.abs(tonumber(valor) or 0))
  local ok = pcall(function() exports.vhub_money:giveWallet(target_src, valor) end)
  if ok then
    TriggerClientEvent("vhub_admin:notify", src,
      ("R$ %d enviado ao jogador [%d]."):format(valor, target_src))
    TriggerClientEvent("vhub_admin:notify", target_src,
      ("Você recebeu R$ %d de um administrador."):format(valor))
    auditoria(src, "givemoney", target_src, tostring(valor))
  end
end)

-- ── Dar item ──────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:giveitem")
AddEventHandler("vhub_admin:giveitem", function(target_src, fullid, amount)
  local src = source
  if not _pronto or not temPerm(src, "player.giveitem") then return end
  target_src = tonumber(target_src)
  amount = math.floor(math.abs(tonumber(amount) or 1))
  local ok = pcall(function() exports.vhub_inventory:giveItem(target_src, fullid, amount) end)
  if ok then
    auditoria(src, "giveitem", target_src, fullid .. " x" .. amount)
  end
end)

-- ── Grupos ────────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:addgroup")
AddEventHandler("vhub_admin:addgroup", function(target_src, grupo)
  local src = source
  if not _pronto or not temPerm(src, "player.group.add") then return end
  target_src = tonumber(target_src)
  local ok = pcall(function() exports.vhub_groups:addGroup(target_src, grupo) end)
  if ok then
    TriggerClientEvent("vhub_admin:notify", src,
      ("Grupo '%s' adicionado ao jogador [%d]."):format(grupo, target_src))
    auditoria(src, "addgroup", target_src, grupo)
  end
end)

RegisterNetEvent("vhub_admin:removegroup")
AddEventHandler("vhub_admin:removegroup", function(target_src, grupo)
  local src = source
  if not _pronto or not temPerm(src, "player.group.remove") then return end
  target_src = tonumber(target_src)
  local ok = pcall(function() exports.vhub_groups:removeGroup(target_src, grupo) end)
  if ok then auditoria(src, "removegroup", target_src, grupo) end
end)

-- ── Lista de jogadores ────────────────────────────────────────────────────────

RegisterNetEvent("vhub_admin:list_players")
AddEventHandler("vhub_admin:list_players", function()
  local src = source
  if not _pronto or not temPerm(src, "player.list") then return end
  local lista = {}
  for _, s in ipairs(GetPlayers()) do
    s = tonumber(s)
    local ok, uid = pcall(function() return exports.vhub:getUID(s) end)
    lista[#lista + 1] = {
      src  = s,
      uid  = (ok and uid) or 0,
      name = GetPlayerName(s) or "?",
      ping = GetPlayerPing(s) or 0,
    }
  end
  TriggerClientEvent("vhub_admin:player_list", src, lista)
end)

-- ── Coordenadas (via server→client) ──────────────────────────────────────────

RegisterNetEvent("vhub_admin:coords")
AddEventHandler("vhub_admin:coords", function()
  local src = source
  if not _pronto or not temPerm(src, "player.coords") then return end
  TriggerClientEvent("vhub_admin:get_coords", src)
end)

-- ── Noclip (via server para manter auditoria) ────────────────────────────────

RegisterNetEvent("vhub_admin:noclip")
AddEventHandler("vhub_admin:noclip", function()
  local src = source
  if not _pronto or not temPerm(src, "player.noclip") then return end
  TriggerClientEvent("vhub_admin:toggle_noclip", src)
end)

-- ── Comandos de console ───────────────────────────────────────────────────────

RegisterCommand("vhub_ban", function(src_str, args)
  if tonumber(src_str) ~= 0 then return end
  local uid    = tonumber(args[1])
  local motivo = table.concat(args, " ", 2)
  if uid then
    _vHub.Auth:ban(uid, motivo or "Banido via console.", "console")
    print(("[vHub Admin] uid=%d banido."):format(uid))
  end
end, true)

RegisterCommand("vhub_unban", function(src_str, args)
  if tonumber(src_str) ~= 0 then return end
  local uid = tonumber(args[1])
  if uid then
    _vHub.Auth:unban(uid)
    print(("[vHub Admin] uid=%d desbanido."):format(uid))
  end
end, true)
