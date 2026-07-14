-- server/exports.lua - delegacoes economicas e API externa gated
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E
local U = VHubAdmin.U

local trusted = {
  vhub = true,
  vhub_garage = true,
  vhub_player_state = true,
}

local function invokerAllowed()
  local invoker = GetInvokingResource()
  return invoker == GetCurrentResourceName() or trusted[invoker] == true
end

local function integer(value, minimum, maximum)
  local number = U.number(value, minimum, maximum)
  if not number or number % 1 ~= 0 then return nil end
  return math.floor(number)
end

local function route(value)
  local selected = U.identifier(value, 16)
  if selected == 'bank' or selected == 'wallet' then return selected end
  return nil
end

local function balance(src, selected)
  local wallet, bank = Core:getBalances(src)
  return selected == 'wallet' and wallet or bank
end


-- ============================================================
-- DINHEIRO E INVENTARIO
-- ============================================================

RegisterNetEvent(E.ACT_GIVEMONEY)
AddEventHandler(E.ACT_GIVEMONEY, function(rawTarget, rawAmount, rawRoute, rawReason)
  local src = source
  if not Core:guard(src, 'givemoney', 'economy') then return end

  local target = Core:onlineTarget(rawTarget)
  local amount = integer(rawAmount, 1, CFG.limits.money_max)
  local selected = route(rawRoute)
  local reason = U.safeText(rawReason, 96)
  if not target or not amount or not selected then
    return Core:notify(src, 'Alvo, valor ou rota invalidos.', 'erro')
  end

  local before = balance(target, selected)
  local ok = Core:mutateMoney(target, selected, amount, false,
    reason ~= '' and reason or 'vhub_admin:givemoney')
  if not ok then return Core:notify(src, 'Credito recusado pelo financeiro.', 'erro') end

  Core:notify(src, ('R$ %d enviados para [%d].'):format(amount, target), 'sucesso')
  Core:notify(target, ('A equipe creditou R$ %d.'):format(amount), 'info')
  Core:audit(src, 'givemoney', target, {
    amount = amount, route = selected, before = before, after = before + amount, reason = reason,
  })
end)

RegisterNetEvent(E.ACT_SETMONEY)
AddEventHandler(E.ACT_SETMONEY, function(rawTarget, rawAmount, rawRoute, rawReason)
  local src = source
  if not Core:guard(src, 'setmoney', 'economy') then return end

  local target = Core:onlineTarget(rawTarget)
  local amount = integer(rawAmount, 0, CFG.limits.money_max)
  local selected = route(rawRoute)
  local reason = U.safeText(rawReason, 96)
  if not target or amount == nil or not selected then
    return Core:notify(src, 'Alvo, valor ou rota invalidos.', 'erro')
  end

  local before = balance(target, selected)
  local ok = Core:mutateMoney(target, selected, amount, true,
    reason ~= '' and reason or 'vhub_admin:setmoney')
  if not ok then return Core:notify(src, 'Alteracao recusada pelo financeiro.', 'erro') end

  Core:notify(src, ('Saldo de [%d] atualizado.'):format(target), 'sucesso')
  Core:notify(target, 'Seu saldo foi atualizado pela equipe.', 'info')
  Core:audit(src, 'setmoney', target, {
    route = selected, before = before, after = amount, reason = reason,
  })
end)

RegisterNetEvent(E.ACT_REMOVEMONEY)
AddEventHandler(E.ACT_REMOVEMONEY, function(rawTarget, rawAmount, rawRoute, rawReason)
  local src = source
  if not Core:guard(src, 'givemoney', 'economy') then return end

  local target = Core:onlineTarget(rawTarget)
  local amount = integer(rawAmount, 1, CFG.limits.money_max)
  local selected = route(rawRoute)
  local reason = U.safeText(rawReason, 96)
  if not target or not amount or not selected then
    return Core:notify(src, 'Alvo, valor ou rota invalidos.', 'erro')
  end

  local before = balance(target, selected)
  local ok = Core:removeMoney(target, selected, amount,
    reason ~= '' and reason or 'vhub_admin:removemoney')
  if not ok then return Core:notify(src, 'Debito recusado pelo financeiro.', 'erro') end

  Core:notify(src, ('R$ %d debitados de [%d].'):format(amount, target), 'sucesso')
  Core:notify(target, ('A equipe debitou R$ %d.'):format(amount), 'info')
  Core:audit(src, 'removemoney', target, {
    amount = amount, route = selected, before = before, after = math.max(0, before - amount), reason = reason,
  })
end)

RegisterNetEvent(E.ACT_GIVEITEM)
AddEventHandler(E.ACT_GIVEITEM, function(rawTarget, rawItem, rawQuantity, rawReason)
  local src = source
  if not Core:guard(src, 'giveitem', 'economy') then return end

  local target = Core:onlineTarget(rawTarget)
  local item = U.identifier(rawItem, 64)
  local quantity = integer(rawQuantity, 1, CFG.limits.item_max)
  local reason = U.safeText(rawReason, 96)
  if not target or not item or not quantity then
    return Core:notify(src, 'Alvo, item ou quantidade invalidos.', 'erro')
  end
  if not Core:giveItem(target, item, quantity, reason) then
    return Core:notify(src, 'Item inexistente ou inventario sem capacidade.', 'erro')
  end

  Core:notify(src, ('%dx %s entregue para [%d].'):format(quantity, item, target), 'sucesso')
  Core:audit(src, 'giveitem', target, { item = item, quantity = quantity, reason = reason })
end)


-- ============================================================
-- GRUPOS
-- ============================================================

RegisterNetEvent(E.ACT_ADDGROUP)
AddEventHandler(E.ACT_ADDGROUP, function(rawTarget, rawGroup, rawLevel, rawDays, rawReason)
  local src = source
  if not Core:guard(src, 'addgroup', 'economy') then return end

  local target = Core:onlineTarget(rawTarget)
  local group = U.identifier(rawGroup, 48)
  local level = integer(rawLevel or 1, 1, 99)
  local days = integer(rawDays or 0, 0, 3650)
  local reason = U.safeText(rawReason, 96)
  if not target or not group or not level or days == nil then
    return Core:notify(src, 'Alvo ou grupo invalido.', 'erro')
  end
  if not Core:addGroup(target, group, level, days, reason ~= '' and reason or 'vhub_admin:addgroup') then
    return Core:notify(src, 'Grupo ou nivel recusado pelo owner.', 'erro')
  end

  Core:notify(src, ('Grupo %s adicionado a [%d].'):format(group, target), 'sucesso')
  Core:audit(src, 'addgroup', target, { group = group, level = level, days = days, reason = reason })
end)

RegisterNetEvent(E.ACT_DELGROUP)
AddEventHandler(E.ACT_DELGROUP, function(rawTarget, rawGroup, rawReason)
  local src = source
  if not Core:guard(src, 'delgroup', 'economy') then return end

  local target = Core:onlineTarget(rawTarget)
  local group = U.identifier(rawGroup, 48)
  local reason = U.safeText(rawReason, 96)
  if not target or not group then return Core:notify(src, 'Alvo ou grupo invalido.', 'erro') end
  if not Core:removeGroup(target, group, reason ~= '' and reason or 'vhub_admin:delgroup') then
    return Core:notify(src, 'Grupo recusado pelo owner.', 'erro')
  end

  Core:notify(src, ('Grupo %s removido de [%d].'):format(group, target), 'sucesso')
  Core:audit(src, 'delgroup', target, { group = group, reason = reason })
end)


-- ============================================================
-- EXPORTS GATED
-- ============================================================

-- Retorna se o alvo tem a capacidade de abrir o painel.
exports('isAdmin', function(src)
  if not invokerAllowed() then return false end
  return Core.hasPerm(src, 'panel')
end)

-- Retorna apenas administradores conectados e visiveis ao invocador autorizado.
exports('listAdmins', function()
  if not invokerAllowed() then return {} end
  local out = {}
  Core:eachAdmin(function(src)
    out[#out + 1] = { src = src, name = U.safeText(GetPlayerName(src) or '?', 64) }
  end)
  return out
end)

-- Registra uma acao externa com payload estritamente tabelado.
exports('log', function(actorSrc, action, targetSrc, payload)
  if not invokerAllowed() then return false end
  local name = U.identifier(action, 48)
  if not name or (payload ~= nil and type(payload) ~= 'table') then return false end
  Core:audit(U.toSrc(actorSrc), name, U.toSrc(targetSrc), payload or {})
  return true
end)


-- ============================================================
-- CONSOLE
-- ============================================================

RegisterCommand('vhub_ban', function(rawSource, args)
  if tonumber(rawSource) ~= 0 then return end
  local uid = integer(args[1], 1, 2147483647)
  local reason = U.safeText(table.concat(args, ' ', 2), 180)
  if not uid then return end

  local ok = pcall(function()
    exports.vhub:banPlayer(uid, reason ~= '' and reason or 'Banido via console.', 'console')
  end)
  if ok then Core:audit(nil, 'ban_console', nil, { uid = uid, reason = reason }) end
end, true)

RegisterCommand('vhub_unban', function(rawSource, args)
  if tonumber(rawSource) ~= 0 then return end
  local uid = integer(args[1], 1, 2147483647)
  if not uid then return end

  local ok = pcall(function() exports.vhub:unbanPlayer(uid) end)
  if ok then Core:audit(nil, 'unban_console', nil, { uid = uid }) end
end, true)
