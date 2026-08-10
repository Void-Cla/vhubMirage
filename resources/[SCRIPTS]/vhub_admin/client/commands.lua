-- client/commands.lua  comandos slash restantes (info + moderation + economy)
---@diagnostic disable: undefined-global

local E = VHubAdmin.E
local S = VHubAdmin.state

local function isAdm() return S.is_admin end

local function formatGroups(groups)
  local formatted = {}
  for _, group in ipairs(type(groups) == 'table' and groups or {}) do
    if type(group) == 'table' then
      formatted[#formatted + 1] = ('%s L%d'):format(group.id or '?', tonumber(group.level) or 1)
    else
      formatted[#formatted + 1] = tostring(group)
    end
  end
  return #formatted > 0 and table.concat(formatted, ', ') or 'Nenhum'
end


-- ============================================================
-- KEYBINDS (ações rápidas sem abrir painel)
-- ============================================================

-- N — toggle noclip
RegisterKeyMapping('noclip', 'Admin: Noclip', 'keyboard', 'n')

-- G — toggle god mode
RegisterCommand('admgod', function()
  if not isAdm() then return end
  TriggerServerEvent(E.ACT_GOD)
end, false)
RegisterKeyMapping('admgod', 'Admin: God mode', 'keyboard', 'g')

-- H — prender/segurar player mais próximo (TP to me)
RegisterCommand('admgrabholdnearest', function()
  if not isAdm() then return end
  local me = PlayerPedId()
  local mc = GetEntityCoords(me)
  local best, bd = nil, 9999
  for _, pid in ipairs(GetActivePlayers()) do
    local ped = GetPlayerPed(pid)
    if ped ~= me and ped ~= 0 then
      local d = #(mc - GetEntityCoords(ped))
      if d < bd then bd = d; best = pid end
    end
  end
  if best then
    TriggerServerEvent(E.ACT_TPTOME, GetPlayerServerId(best))
    VHubAdmin.notify(('Trouxe player %d'):format(GetPlayerServerId(best)))
  end
end, false)
RegisterKeyMapping('admgrabholdnearest', 'Admin: Trazer player mais próximo', 'keyboard', 'h')

-- DEL — deletar veículo mais próximo (raio 20m, client-side via controle de entidade)
RegisterCommand('admdelvehnearest', function()
  if not isAdm() then return end
  local ped = PlayerPedId()
  local pc = GetEntityCoords(ped)
  local nearest, nd = 0, 20.0
  local veh = GetVehiclePedIsIn(ped, false)
  -- encontra veículo mais próximo fora do que o admin está dirigindo
  for _, v in ipairs(GetGamePool('CVehicle')) do
    if v ~= veh and DoesEntityExist(v) then
      local d = #(pc - GetEntityCoords(v))
      if d < nd then nd = d; nearest = v end
    end
  end
  if nearest == 0 then VHubAdmin.notify('Nenhum veículo próximo.'); return end
  -- pede controle para deletar (server authoritative delete via clearzone ~0 raio alternativo)
  NetworkRequestControlOfEntity(nearest)
  local deadline = GetGameTimer() + 1000
  Citizen.CreateThread(function()
    while not NetworkHasControlOfEntity(nearest) and GetGameTimer() < deadline do
      Citizen.Wait(50)
    end
    if DoesEntityExist(nearest) then
      DeleteEntity(nearest)
      VHubAdmin.notify('Veículo deletado.')
    end
  end)
end, false)
RegisterKeyMapping('admdelvehnearest', 'Admin: Deletar veículo próximo', 'keyboard', 'DELETE')

-- ----------------------------------------------------------------------------
-- /cds  imprime a posicao atual em TODOS os formatos de uma vez (copia/cola)
-- ----------------------------------------------------------------------------
RegisterCommand('cds', function()
  if not isAdm() then return end

  local ped = PlayerPedId()
  local c, h = GetEntityCoords(ped), GetEntityHeading(ped)

  -- todos os formatos: plano | vector3 (sem heading) | vector4 (com heading) | tabela flat
  local linhas = {
    ('x=%.4f  y=%.4f  z=%.4f  h=%.4f'):format(c.x, c.y, c.z, h),
    ('vector3(%.4f, %.4f, %.4f)'):format(c.x, c.y, c.z),
    ('vector4(%.4f, %.4f, %.4f, %.4f)'):format(c.x, c.y, c.z, h),
    ('{ x = %.4f, y = %.4f, z = %.4f, h = %.4f }'):format(c.x, c.y, c.z, h),
  }

  for _, line in ipairs(linhas) do
    VHubAdmin.notify(line)
  end
end, false)

-- ----------------------------------------------------------------------------
-- /id  mostra player mais próximo
-- ----------------------------------------------------------------------------
RegisterCommand('id', function()
  local me = PlayerPedId()
  local mc = GetEntityCoords(me)
  local best, bd = nil, 9999
  for _, pid in ipairs(GetActivePlayers()) do
    local ped = GetPlayerPed(pid)
    if ped ~= me and ped ~= 0 then
      local d = #(mc - GetEntityCoords(ped))
      if d < bd then bd = d; best = pid end
    end
  end
  if best then
    VHubAdmin.notify(('Player próximo: ID %d  %.1fm'):format(
      GetPlayerServerId(best), bd))
  else VHubAdmin.notify('Nenhum player próximo.') end
end, false)

-- ----------------------------------------------------------------------------
-- /rg <id> exibe a ficha; /rg sem ID e /wall alternam o overlay.
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.PROFILE)
AddEventHandler(E.PROFILE, function(info)
  if S.panel_open then
    SendNUIMessage({ action = VHubAdmin.UI.PROFILE, data = info })
  else
    local lines = {
      ('   FICHA [%d]'):format(info.src),
      ('uid=%d char=%d ping=%dms'):format(info.uid, info.char_id, info.ping or 0),
      ('Nome: %s'):format(info.name or '?'),
    }
    if info.identity then
      lines[#lines+1] = ('Identidade: %s %s (%s)'):format(
        info.identity.firstname or '?', info.identity.lastname or '',
        info.identity.registration or '?')
    end
    lines[#lines+1] = ('Carteira: R$ %d   Banco: R$ %d'):format(
      info.wallet or 0, info.bank or 0)
    lines[#lines+1] = ('Grupos: %s'):format(formatGroups(info.groups))
    if info.vehicles and #info.vehicles > 0 then
      local vs = {}
      for _, v in ipairs(info.vehicles) do
        vs[#vs+1] = ('%s(%s)'):format(v.plate, v.status)
      end
      lines[#lines+1] = ('Veículos: %s'):format(table.concat(vs, ', '))
    end
    for _, l in ipairs(lines) do
      TriggerEvent('chat:addMessage', { color = { 76, 200, 255 }, args = { '[RG]', l } })
    end
  end
end)

RegisterCommand('rg', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  if args[1] and not t then return VHubAdmin.notify('Uso: /rg [id]') end
  if t then return TriggerServerEvent(E.REQ_PROFILE, t) end
  TriggerServerEvent(E.REQ_WALL_TOGGLE)
end, false)

RegisterCommand('wall', function()
  if not isAdm() then return end
  TriggerServerEvent(E.REQ_WALL_TOGGLE)
end, false)

-- ----------------------------------------------------------------------------
-- /pon  lista IDs online
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.PLAYER_LIST)
AddEventHandler(E.PLAYER_LIST, function(list)
  if S.panel_open then
    SendNUIMessage({ action = VHubAdmin.UI.PLAYER_LIST, data = list })
    return
  end
  TriggerEvent('chat:addMessage', { color = { 76, 200, 255 },
    args = { '[PON]', ('%d jogadores online:'):format(#list) } })
  for _, p in ipairs(list) do
    TriggerEvent('chat:addMessage', { args = {
      ('  [%d]'):format(p.src),
      ('uid=%d %s ping=%dms'):format(p.uid, p.name, p.ping)
    } })
  end
end)

RegisterCommand('pon', function()
  if not isAdm() then return end
  TriggerServerEvent(E.REQ_PLAYERS)
end, false)

-- ----------------------------------------------------------------------------
-- Moderation slash
-- ----------------------------------------------------------------------------
RegisterCommand('kick', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  local r = table.concat(args, ' ', 2)
  if t then TriggerServerEvent(E.ACT_KICK, t, r) end
end, false)

RegisterCommand('ban', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  local r = table.concat(args, ' ', 2)
  if t then TriggerServerEvent(E.ACT_BAN, t, r) end
end, false)

RegisterCommand('unban', function(_, args)
  if not isAdm() then return end
  local uid = tonumber(args[1])
  if uid then TriggerServerEvent(E.ACT_UNBAN, uid) end
end, false)

RegisterCommand('warn', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  local msg = table.concat(args, ' ', 2)
  if t and msg ~= '' then TriggerServerEvent(E.ACT_WARN, t, msg) end
end, false)

RegisterCommand('jail', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  local m = tonumber(args[2]) or 10
  local r = table.concat(args, ' ', 3)
  if t then TriggerServerEvent(E.ACT_JAIL, t, m, r) end
end, false)

RegisterCommand('unjail', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_UNJAIL, t) end
end, false)

RegisterCommand('mute', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  local m = tonumber(args[2]) or 10
  local r = table.concat(args, ' ', 3)
  if t then TriggerServerEvent(E.ACT_MUTE, t, m, r) end
end, false)

RegisterCommand('unmute', function(_, args)
  if not isAdm() then return end
  local t = tonumber(args[1])
  if t then TriggerServerEvent(E.ACT_UNMUTE, t) end
end, false)

-- ----------------------------------------------------------------------------
-- Economia / itens
-- ----------------------------------------------------------------------------
RegisterCommand('givemoney', function(_, args)
  if not isAdm() then return end
  local t, v, rota
  if args[2] then
    t = tonumber(args[1]); v = tonumber(args[2]); rota = args[3] or 'banco'
  else
    t = GetPlayerServerId(PlayerId()); v = tonumber(args[1]); rota = 'banco'
  end
  if t and v then TriggerServerEvent(E.ACT_GIVEMONEY, t, math.floor(v), rota)
  else VHubAdmin.notify('Uso: /givemoney <valor>  ou  /givemoney <id> <valor> [wallet|banco]') end
end, false)

RegisterCommand('setmoney', function(_, args)
  if not isAdm() then return end
  local t, v, rota = tonumber(args[1]), tonumber(args[2]), args[3] or 'banco'
  if t and v then TriggerServerEvent(E.ACT_SETMONEY, t, math.floor(v), rota) end
end, false)

RegisterCommand('removemoney', function(_, args)
  if not isAdm() then return end
  local t, v, rota
  if args[2] then
    t = tonumber(args[1]); v = tonumber(args[2]); rota = args[3] or 'banco'
  else
    t = GetPlayerServerId(PlayerId()); v = tonumber(args[1]); rota = 'banco'
  end
  if t and v then TriggerServerEvent(E.ACT_REMOVEMONEY, t, math.floor(v), rota)
  else VHubAdmin.notify('Uso: /removemoney <valor>  ou  /removemoney <id> <valor> [wallet|banco]') end
end, false)

RegisterCommand('giveitem', function(_, args)
  if not isAdm() then return end
  local t, item, q
  if args[3] then
    t = tonumber(args[1]); item = args[2]; q = tonumber(args[3]) or 1
  else
    t = GetPlayerServerId(PlayerId()); item = args[1]; q = tonumber(args[2]) or 1
  end
  if t and item then TriggerServerEvent(E.ACT_GIVEITEM, t, item, math.floor(q)) end
end, false)

RegisterCommand('addgroup', function(_, args)
  if not isAdm() then return end
  local t, g = tonumber(args[1]), args[2]
  if t and g then TriggerServerEvent(E.ACT_ADDGROUP, t, g) end
end, false)

RegisterCommand('delgroup', function(_, args)
  if not isAdm() then return end
  local t, g = tonumber(args[1]), args[2]
  if t and g then TriggerServerEvent(E.ACT_DELGROUP, t, g) end
end, false)
