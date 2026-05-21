-- vhub_admin/client.lua

local _noclip     = false
local _god        = false
local _frozen     = false
local _panel_open = false
local _is_admin   = false   -- definido via State Bag (uid=1) ou ao receber panel_allowed

-- ── Notificação ───────────────────────────────────────────────────────────────

local function notify(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, true)
end

-- ── Verificação de permissão (client-side, para comandos diretos) ─────────────

local function checkAdmin()
  if _is_admin then return true end
  notify("Sem permissão de administrador.")
  return false
end

-- ── Spawn de veículo ─────────────────────────────────────────────────────────

local function spawnVeiculo(modelo)
  Citizen.CreateThread(function()
    local hash = GetHashKey(modelo)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
      notify("Modelo inválido: " .. modelo); return
    end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 200 do
      Citizen.Wait(10); tries = tries + 1
    end
    if not HasModelLoaded(hash) then
      notify("Timeout ao carregar: " .. modelo); return
    end
    local ped     = PlayerPedId()
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local veh     = CreateVehicle(hash, coords.x, coords.y + 4.0, coords.z, heading, true, false)
    SetVehicleOnGroundProperly(veh)
    SetPedIntoVehicle(ped, veh, -1)
    SetModelAsNoLongerNeeded(hash)
    notify("Veículo " .. modelo .. " spawnado.")
  end)
end

-- ── Deletar veículo ──────────────────────────────────────────────────────────

local function deletarVeiculo()
  Citizen.CreateThread(function()
    local ped = PlayerPedId()
    local veh
    if IsPedInAnyVehicle(ped, false) then
      veh = GetVehiclePedIsIn(ped, false)
      TaskLeaveVehicle(ped, veh, 4096)
      Citizen.Wait(800)
    else
      local c = GetEntityCoords(ped)
      veh = GetClosestVehicle(c.x, c.y, c.z, 5.0, 0, 71)
    end
    if veh and veh ~= 0 then
      DeleteVehicle(veh)
      notify("Veículo deletado.")
    else
      notify("Nenhum veículo próximo para deletar.")
    end
  end)
end

-- ── Abrir / fechar painel NUI ─────────────────────────────────────────────────

local function abrirPainel()
  _panel_open = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = "abrir", noclip = _noclip, god = _god })
end

local function fecharPainel()
  _panel_open = false
  SetNuiFocus(false, false)
end

-- ── NUI Callbacks ─────────────────────────────────────────────────────────────

RegisterNUICallback("fechar", function(_, cb)
  fecharPainel(); cb({})
end)

RegisterNUICallback("listar_jogadores", function(_, cb)
  TriggerServerEvent("vhub_admin:list_players"); cb({})
end)

RegisterNUICallback("noclip", function(_, cb)
  if not _is_admin then notify("Sem permissão."); cb({}); return end
  _noclip = not _noclip
  local ped = PlayerPedId()
  if not _noclip then
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
  end
  SendNUIMessage({ action = "noclip_sync", ativo = _noclip })
  notify(_noclip and "Noclip ATIVADO" or "Noclip DESATIVADO")
  cb({})
end)

RegisterNUICallback("god", function(_, cb)
  if not _is_admin then notify("Sem permissão."); cb({}); return end
  _god = not _god
  SetPlayerInvincible(PlayerId(), _god)
  SendNUIMessage({ action = "god_sync", ativo = _god })
  notify(_god and "God Mode ATIVADO" or "God Mode DESATIVADO")
  cb({})
end)

RegisterNUICallback("heal_me", function(_, cb)
  if not _is_admin then notify("Sem permissão."); cb({}); return end
  local ped = PlayerPedId()
  SetEntityHealth(ped, 200)
  SetPedArmour(ped, 100)
  ClearPedBloodDamage(ped)
  notify("HP e colete restaurados.")
  cb({})
end)

RegisterNUICallback("delveh", function(_, cb)
  if not _is_admin then notify("Sem permissão."); cb({}); return end
  deletarVeiculo(); cb({})
end)

RegisterNUICallback("spawncar", function(data, cb)
  if not _is_admin then notify("Sem permissão."); cb({}); return end
  local modelo = tostring(data.modelo or ""):lower()
  if modelo ~= "" then spawnVeiculo(modelo) end
  cb({})
end)

RegisterNUICallback("cds", function(data, cb)
  local tipo    = tonumber(data.tipo) or 1
  local coords  = GetEntityCoords(PlayerPedId())
  local heading = GetEntityHeading(PlayerPedId())
  local linha
  if tipo == 2 then
    linha = ("vector4(%.4f, %.4f, %.4f, %.4f)"):format(
      coords.x, coords.y, coords.z, heading)
  else
    linha = ("x=%.4f  y=%.4f  z=%.4f  h=%.4f"):format(
      coords.x, coords.y, coords.z, heading)
  end
  notify(linha)
  print("[cds] " .. linha)
  cb({ linha = linha })
end)

RegisterNUICallback("tptome", function(data, cb)
  local src = tonumber(data.src)
  if src then TriggerServerEvent("vhub_admin:tptome", src) end
  cb({})
end)

RegisterNUICallback("bring", function(data, cb)
  local src = tonumber(data.src)
  if src then TriggerServerEvent("vhub_admin:bring", src) end
  cb({})
end)

RegisterNUICallback("heal", function(data, cb)
  TriggerServerEvent("vhub_admin:heal", tonumber(data.src))
  cb({})
end)

RegisterNUICallback("kick", function(data, cb)
  local src    = tonumber(data.src)
  local motivo = tostring(data.motivo or "Kicked by admin.")
  if src then TriggerServerEvent("vhub_admin:kick", src, motivo) end
  cb({})
end)

RegisterNUICallback("ban", function(data, cb)
  local src    = tonumber(data.src)
  local motivo = tostring(data.motivo or "Banido.")
  if src then TriggerServerEvent("vhub_admin:ban", src, motivo) end
  cb({})
end)

RegisterNUICallback("whitelist", function(data, cb)
  local src = tonumber(data.src)
  if src then TriggerServerEvent("vhub_admin:whitelist", src) end
  cb({})
end)

RegisterNUICallback("unwhitelist", function(data, cb)
  local src = tonumber(data.src)
  if src then TriggerServerEvent("vhub_admin:unwhitelist", src) end
  cb({})
end)

RegisterNUICallback("freeze", function(data, cb)
  local src = tonumber(data.src)
  if src then TriggerServerEvent("vhub_admin:freeze", src) end
  cb({})
end)

-- ── Eventos de servidor → cliente ────────────────────────────────────────────

RegisterNetEvent("vhub_admin:panel_allowed")
AddEventHandler("vhub_admin:panel_allowed", function()
  _is_admin = true   -- servidor confirmou permissão
  abrirPainel()
end)

RegisterNetEvent("vhub_admin:notify")
AddEventHandler("vhub_admin:notify", function(msg)
  notify(msg)
end)

RegisterNetEvent("vhub_admin:player_list")
AddEventHandler("vhub_admin:player_list", function(lista)
  if _panel_open then
    SendNUIMessage({ action = "player_list", lista = lista })
  else
    local msg = ("Jogadores online: %d"):format(#(lista or {}))
    for _, p in ipairs(lista or {}) do
      msg = msg .. ("\n  [%d] uid=%d %s ping=%dms"):format(
        p.src, p.uid, p.name, p.ping)
    end
    notify(msg)
  end
end)

RegisterNetEvent("vhub_admin:toggle_noclip")
AddEventHandler("vhub_admin:toggle_noclip", function()
  _noclip = not _noclip
  local ped = PlayerPedId()
  if not _noclip then
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
  end
  SendNUIMessage({ action = "noclip_sync", ativo = _noclip })
  notify(_noclip and "Noclip ATIVADO" or "Noclip DESATIVADO")
end)

RegisterNetEvent("vhub_admin:toggle_god")
AddEventHandler("vhub_admin:toggle_god", function()
  _god = not _god
  SetPlayerInvincible(PlayerId(), _god)
  SendNUIMessage({ action = "god_sync", ativo = _god })
  notify(_god and "God Mode ATIVADO" or "God Mode DESATIVADO")
end)

RegisterNetEvent("vhub_admin:do_heal")
AddEventHandler("vhub_admin:do_heal", function()
  local ped = PlayerPedId()
  SetEntityHealth(ped, 200)
  SetPedArmour(ped, 100)
  ClearPedBloodDamage(ped)
  notify("Curado!")
end)

RegisterNetEvent("vhub_admin:toggle_freeze")
AddEventHandler("vhub_admin:toggle_freeze", function()
  _frozen = not _frozen
  FreezeEntityPosition(PlayerPedId(), _frozen)
  notify(_frozen and "Você foi congelado por um admin." or "Você foi descongelado.")
end)

RegisterNetEvent("vhub_admin:do_tp")
AddEventHandler("vhub_admin:do_tp", function(x, y, z)
  Citizen.CreateThread(function()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    RequestCollisionAtCoord(x, y, z)
    Citizen.Wait(500)
    FreezeEntityPosition(ped, false)
    notify(("Teleportado para (%.1f, %.1f, %.1f)"):format(x, y, z))
  end)
end)

RegisterNetEvent("vhub_admin:do_spawncar")
AddEventHandler("vhub_admin:do_spawncar", function(modelo)
  spawnVeiculo(modelo)
end)

RegisterNetEvent("vhub_admin:do_delveh")
AddEventHandler("vhub_admin:do_delveh", function()
  deletarVeiculo()
end)

RegisterNetEvent("vhub_admin:get_coords")
AddEventHandler("vhub_admin:get_coords", function()
  local coords  = GetEntityCoords(PlayerPedId())
  local heading = GetEntityHeading(PlayerPedId())
  notify(("x=%.4f  y=%.4f  z=%.4f  h=%.4f"):format(
    coords.x, coords.y, coords.z, heading))
end)

-- ── Thread de noclip (velocity-only, sem SetEntityCoords) ────────────────────

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if not _noclip then goto continue end

    local ped   = PlayerPedId()
    local speed = IsControlPressed(0, 21) and 25.0 or 8.0

    SetEntityCollision(ped, false, true)
    SetEntityHasGravity(ped, false)

    local cam = GetGameplayCamRot(2)
    local fx  = -math.sin(math.rad(cam.z)) * math.cos(math.rad(cam.x))
    local fy  =  math.cos(math.rad(cam.z)) * math.cos(math.rad(cam.x))
    local fz  =  math.sin(math.rad(cam.x))

    local dx, dy, dz = 0.0, 0.0, 0.0
    if IsControlPressed(0, 32) then dx=dx+fx*speed; dy=dy+fy*speed; dz=dz+fz*speed end
    if IsControlPressed(0, 33) then dx=dx-fx*speed; dy=dy-fy*speed; dz=dz-fz*speed end
    if IsControlPressed(0, 34) then dx=dx-fy*speed; dy=dy+fx*speed end
    if IsControlPressed(0, 35) then dx=dx+fy*speed; dy=dy-fx*speed end
    if IsControlPressed(0, 44) then dz=dz+speed end
    if IsControlPressed(0, 38) then dz=dz-speed end

    SetEntityVelocity(ped, dx, dy, dz)
    ::continue::
  end
end)

-- ── Leitura de admin via State Bag (uid=1 recebe ao conectar) ────────────────

AddEventHandler("vhub_player_state:spawned", function()
  -- Reseta efeitos locais ao spawnar
  if _noclip then
    _noclip = false
    local ped = PlayerPedId()
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
  end
  if _god then
    _god = false
    SetPlayerInvincible(PlayerId(), false)
  end
  if _frozen then
    _frozen = false
    FreezeEntityPosition(PlayerPedId(), false)
  end

  -- Lê State Bag após breve delay para garantir propagação
  Citizen.CreateThread(function()
    Citizen.Wait(600)
    if LocalPlayer and LocalPlayer.state then
      local admin_bag = LocalPlayer.state.vhub_is_admin
      if admin_bag == true then
        _is_admin = true
      end
    end
  end)
end)

-- ── Comandos slash ─────────────────────────────────────────────────────────────

RegisterCommand("admin", function()
  if _panel_open then
    fecharPainel()
  else
    TriggerServerEvent("vhub_admin:open_panel")
  end
end, false)

RegisterCommand("nc", function()
  if not checkAdmin() then return end
  _noclip = not _noclip
  local ped = PlayerPedId()
  if not _noclip then
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
  end
  if _panel_open then SendNUIMessage({ action = "noclip_sync", ativo = _noclip }) end
  notify(_noclip and "Noclip ATIVADO" or "Noclip DESATIVADO")
end, false)

RegisterCommand("god", function()
  if not checkAdmin() then return end
  _god = not _god
  SetPlayerInvincible(PlayerId(), _god)
  if _panel_open then SendNUIMessage({ action = "god_sync", ativo = _god }) end
  notify(_god and "God Mode ATIVADO" or "God Mode DESATIVADO")
end, false)

RegisterCommand("car", function(_, args)
  if not checkAdmin() then return end
  local modelo = (args[1] or "adder"):lower()
  spawnVeiculo(modelo)
end, false)

RegisterCommand("dv", function()
  if not checkAdmin() then return end
  deletarVeiculo()
end, false)

RegisterCommand("heal", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  if target then
    TriggerServerEvent("vhub_admin:heal", target)
  else
    local ped = PlayerPedId()
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
    notify("HP e colete restaurados.")
  end
end, false)

RegisterCommand("cds", function(_, args)
  local tipo    = tonumber(args[1]) or 1
  local coords  = GetEntityCoords(PlayerPedId())
  local heading = GetEntityHeading(PlayerPedId())
  local linha
  if tipo == 2 then
    linha = ("vector4(%.4f, %.4f, %.4f, %.4f)"):format(
      coords.x, coords.y, coords.z, heading)
  else
    linha = ("x=%.4f  y=%.4f  z=%.4f  h=%.4f"):format(
      coords.x, coords.y, coords.z, heading)
  end
  notify(linha)
  print("[cds] " .. linha)
end, false)

RegisterCommand("tp", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent("vhub_admin:tptome", target) end
end, false)

RegisterCommand("bring", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent("vhub_admin:bring", target) end
end, false)

RegisterCommand("kick", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  local motivo = table.concat(args, " ", 2)
  if target then TriggerServerEvent("vhub_admin:kick", target, motivo) end
end, false)

RegisterCommand("ban", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  local motivo = table.concat(args, " ", 2)
  if target then TriggerServerEvent("vhub_admin:ban", target, motivo) end
end, false)

RegisterCommand("unban", function(_, args)
  if not checkAdmin() then return end
  local uid = tonumber(args[1])
  if uid then TriggerServerEvent("vhub_admin:unban", uid) end
end, false)

RegisterCommand("wl", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent("vhub_admin:whitelist", target) end
end, false)

RegisterCommand("unwl", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent("vhub_admin:unwhitelist", target) end
end, false)

RegisterCommand("freeze", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent("vhub_admin:freeze", target) end
end, false)

RegisterCommand("unfreeze", function(_, args)
  if not checkAdmin() then return end
  local target = tonumber(args[1])
  if target then TriggerServerEvent("vhub_admin:freeze", target) end
end, false)

RegisterCommand("givemoney", function(_, args)
  if not checkAdmin() then return end
  -- /givemoney <id> <valor>   ou   /givemoney <valor>  (self)
  local target, valor
  if args[2] then
    target = tonumber(args[1])
    valor  = tonumber(args[2])
  else
    target = GetPlayerServerId(PlayerId())
    valor  = tonumber(args[1])
  end
  if not target or not valor or valor <= 0 then
    notify("Uso: /givemoney <valor>  ou  /givemoney <id> <valor>")
    return
  end
  TriggerServerEvent("vhub_admin:givemoney", target, math.floor(valor))
end, false)

RegisterCommand("giveitem", function(_, args)
  if not checkAdmin() then return end
  -- /giveitem <id> <item> <qtd>   ou   /giveitem <item> <qtd>  (self)
  local target, fullid, amount
  if args[3] then
    target = tonumber(args[1]); fullid = args[2]; amount = tonumber(args[3]) or 1
  else
    target = GetPlayerServerId(PlayerId()); fullid = args[1]; amount = tonumber(args[2]) or 1
  end
  if not target or not fullid then
    notify("Uso: /giveitem <item> <qtd>  ou  /giveitem <id> <item> <qtd>")
    return
  end
  TriggerServerEvent("vhub_admin:giveitem", target, fullid, math.floor(amount))
end, false)
