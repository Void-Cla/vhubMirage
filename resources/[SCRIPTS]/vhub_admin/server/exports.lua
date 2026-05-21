-- server/exports.lua  superf cie p blica + comandos console
---@diagnostic disable: undefined-global

local SQL  = VHubAdmin.SQL
local Core = VHubAdmin.Core
local E    = VHubAdmin.E
local U    = VHubAdmin.U

-- ----------------------------------------------------------------------------
-- Money / itens / grupos  delega a outros resources com perm check
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_GIVEMONEY)
AddEventHandler(E.ACT_GIVEMONEY, function(target, amount, rota)
  local src = source; if not Core.hasPerm(src, 'givemoney') then return end
  local t = U.toSrc(target); if not t then return end
  local v = U.clamp(math.floor(math.abs(tonumber(amount) or 0)), 0,
              VHubAdmin.cfg.limits.money_max)
  if v <= 0 then return end
  if rota == 'wallet' then Core.giveWallet(t, v) else Core.giveBank(t, v) end
  Core.notify(src, ('R$ %d enviado a [%d].'):format(v, t))
  Core.notify(t, ('Voc  recebeu R$ %d.'):format(v))
  Core:audit(src, 'givemoney', t, { amount = v, rota = rota or 'banco' })
end)

RegisterNetEvent(E.ACT_SETMONEY)
AddEventHandler(E.ACT_SETMONEY, function(target, amount, rota)
  local src = source; if not Core.hasPerm(src, 'setmoney') then return end
  local t = U.toSrc(target); if not t then return end
  local v = U.clamp(math.floor(math.abs(tonumber(amount) or 0)), 0,
              VHubAdmin.cfg.limits.money_max)
  if rota == 'wallet' then Core.setWallet(t, v) else Core.setBank(t, v) end
  Core:audit(src, 'setmoney', t, { amount = v, rota = rota or 'banco' })
end)

RegisterNetEvent(E.ACT_GIVEITEM)
AddEventHandler(E.ACT_GIVEITEM, function(target, item, qty)
  local src = source; if not Core.hasPerm(src, 'giveitem') then return end
  local t = U.toSrc(target); if not t then return end
  item = U.safeText(tostring(item or ''), 64)
  local q = U.clamp(math.floor(math.abs(tonumber(qty) or 1)), 1, VHubAdmin.cfg.limits.item_max)
  if item == '' then return end
  Core.giveItem(t, item, q)
  Core:audit(src, 'giveitem', t, { item = item, qty = q })
end)

RegisterNetEvent(E.ACT_CLEARINV)
AddEventHandler(E.ACT_CLEARINV, function(target)
  local src = source; if not Core.hasPerm(src, 'clearinv') then return end
  local t = U.toSrc(target); if not t then return end
  local ok = pcall(function() exports.vhub_inventory:clearInventory(t) end)
  if ok then
    Core.notify(src, ('Invent rio de [%d] limpo.'):format(t))
    Core:audit(src, 'clearinv', t, {})
  end
end)

RegisterNetEvent(E.ACT_ADDGROUP)
AddEventHandler(E.ACT_ADDGROUP, function(target, group)
  local src = source; if not Core.hasPerm(src, 'addgroup') then return end
  local t = U.toSrc(target); if not t then return end
  group = U.safeText(tostring(group or ''), 32)
  if group == '' then return end
  Core.addGroup(t, group)
  Core:audit(src, 'addgroup', t, { group = group })
end)

RegisterNetEvent(E.ACT_DELGROUP)
AddEventHandler(E.ACT_DELGROUP, function(target, group)
  local src = source; if not Core.hasPerm(src, 'delgroup') then return end
  local t = U.toSrc(target); if not t then return end
  group = U.safeText(tostring(group or ''), 32)
  if group == '' then return end
  Core.removeGroup(t, group)
  Core:audit(src, 'delgroup', t, { group = group })
end)

-- ----------------------------------------------------------------------------
-- Exports leitura (outros resources)
-- ----------------------------------------------------------------------------
exports('isAdmin', function(src) return Core.hasPerm(src, 'panel') end)
exports('listAdmins', function()
  local out = {}
  for s, _ in pairs(Core.adminIds) do out[#out+1] = s end
  return out
end)
exports('log', function(actor_src, action, target_src, payload)
  Core:audit(actor_src, action or 'extern', target_src, payload)
end)

-- ----------------------------------------------------------------------------
-- Comandos console
-- ----------------------------------------------------------------------------
RegisterCommand('vhub_ban', function(src_str, args)
  if tonumber(src_str) ~= 0 then return end
  local uid    = tonumber(args[1])
  local motivo = U.safeText(table.concat(args, ' ', 2), 180)
  if uid then
    local vh = Core:vHub()
    if vh then
      vh.Auth:ban(uid, motivo ~= '' and motivo or 'Banido via console.', 'console')
      Core:audit(nil, 'ban_console', nil, { uid = uid, reason = motivo })
      print(('[vhub_admin] uid=%d banido.'):format(uid))
    end
  end
end, true)

RegisterCommand('vhub_unban', function(src_str, args)
  if tonumber(src_str) ~= 0 then return end
  local uid = tonumber(args[1])
  if uid then
    local vh = Core:vHub()
    if vh then
      vh.Auth:unban(uid)
      Core:audit(nil, 'unban_console', nil, { uid = uid })
      print(('[vhub_admin] uid=%d desbanido.'):format(uid))
    end
  end
end, true)
