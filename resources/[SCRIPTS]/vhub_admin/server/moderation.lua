-- server/moderation.lua  kick, ban, unban, whitelist, warn, jail, mute
---@diagnostic disable: undefined-global

local SQL  = VHubAdmin.SQL
local Core = VHubAdmin.Core
local CFG  = VHubAdmin.cfg
local E    = VHubAdmin.E
local U    = VHubAdmin.U

local function reqPerm(src, key)
  if not Core.hasPerm(src, key) then
    Core.notify(src, 'Sem permiss o para esta a  o.')
    return false
  end
  return true
end

-- ----------------------------------------------------------------------------
-- KICK
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_KICK)
AddEventHandler(E.ACT_KICK, function(target, reason)
  local src = source; if not reqPerm(src, 'kick') then return end
  local t = U.toSrc(target); if not t then return end
  reason = U.safeText(reason, 180)
  DropPlayer(t, 'Expulso pelo admin: ' .. (reason ~= '' and reason or 'sem motivo'))
  Core:audit(src, 'kick', t, { reason = reason })
end)

-- ----------------------------------------------------------------------------
-- BAN
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_BAN)
AddEventHandler(E.ACT_BAN, function(target, reason)
  local src = source; if not reqPerm(src, 'ban') then return end
  local t = U.toSrc(target); if not t then return end
  reason = U.safeText(reason, 180)
  local vh = Core:vHub(); if not vh then return end
  local tuser = vh.Auth:getUser(t); if not tuser then return end
  local actor = vh.Auth:getUser(src)
  vh.Auth:ban(tuser.id, reason, actor and actor.id or 'admin')
  Core.notify(src, ('[%d] uid=%d banido.'):format(t, tuser.id))
  Core:audit(src, 'ban', t, { uid = tuser.id, reason = reason })
end)

RegisterNetEvent(E.ACT_UNBAN)
AddEventHandler(E.ACT_UNBAN, function(uid)
  local src = source; if not reqPerm(src, 'unban') then return end
  uid = tonumber(uid); if not uid then return end
  local vh = Core:vHub(); if not vh then return end
  vh.Auth:unban(uid)
  Core.notify(src, ('uid=%d desbanido.'):format(uid))
  Core:audit(src, 'unban', nil, { uid = uid })
end)

-- ----------------------------------------------------------------------------
-- WHITELIST
-- ----------------------------------------------------------------------------
local function setWhitelist(src, target, on)
  if not reqPerm(src, 'whitelist') then return end
  local t = U.toSrc(target); if not t then return end
  local vh = Core:vHub(); if not vh then return end
  local tuser = vh.Auth:getUser(t); if not tuser then return end
  tuser.data.whitelisted = on
  Core.notify(src,
    ('[%d] uid=%d %s whitelist.'):format(t, tuser.id, on and 'adicionado  ' or 'removido da'))
  if on then Core.notify(t, 'Voc  foi adicionado   whitelist.') end
  Core:audit(src, on and 'whitelist' or 'unwhitelist', t, { uid = tuser.id })
end

RegisterNetEvent(E.ACT_WL)
AddEventHandler(E.ACT_WL, function(target) setWhitelist(source, target, true) end)

RegisterNetEvent(E.ACT_UNWL)
AddEventHandler(E.ACT_UNWL, function(target) setWhitelist(source, target, false) end)

-- ----------------------------------------------------------------------------
-- WARN
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_WARN)
AddEventHandler(E.ACT_WARN, function(target, message)
  local src = source; if not reqPerm(src, 'warn') then return end
  local t = U.toSrc(target); if not t then return end
  local msg = U.safeText(message, 180)
  if msg == '' then Core.notify(src, 'Mensagem vazia.'); return end
  Core.notify(t, '   AVISO ADMIN: ' .. msg)
  Core.notify(src, ('Aviso enviado a [%d].'):format(t))
  Core:audit(src, 'warn', t, { message = msg })
end)

-- ----------------------------------------------------------------------------
-- JAIL
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_JAIL)
AddEventHandler(E.ACT_JAIL, function(target, minutes, reason)
  local src = source; if not reqPerm(src, 'jail') then return end
  local t = U.toSrc(target); if not t then return end
  local m = U.clamp(tonumber(minutes) or 0, CFG.limits.jail_min, CFG.limits.jail_max)
  reason = U.safeText(reason, 180)
  Citizen.CreateThread(function()
    local cid = Core:getCharId(t)
    if not cid then Core.notify(src, 'Personagem do alvo n o carregado.'); return end
    local expires = os.time() + m * 60
    SQL:jailPut(cid, expires, reason, Core:getUid(src))
    TriggerClientEvent(E.JAIL_APPLY, t,
      { expires_at = expires, pos = CFG.jail_pos, reason = reason })
    Core.notify(src, ('[%d] preso por %d min.'):format(t, m))
    Core.notify(t, ('Voc  foi preso por %d min: %s'):format(m, reason ~= '' and reason or 'sem motivo'))
    Core:audit(src, 'jail', t, { minutes = m, reason = reason })
  end)
end)

RegisterNetEvent(E.ACT_UNJAIL)
AddEventHandler(E.ACT_UNJAIL, function(target)
  local src = source; if not reqPerm(src, 'jail') then return end
  local t = U.toSrc(target); if not t then return end
  Citizen.CreateThread(function()
    local cid = Core:getCharId(t); if not cid then return end
    SQL:jailRemove(cid)
    TriggerClientEvent(E.JAIL_RELEASE, t)
    Core.notify(src, ('[%d] liberado.'):format(t))
    Core:audit(src, 'unjail', t, {})
  end)
end)

-- ----------------------------------------------------------------------------
-- MUTE
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_MUTE)
AddEventHandler(E.ACT_MUTE, function(target, minutes, reason)
  local src = source; if not reqPerm(src, 'mute') then return end
  local t = U.toSrc(target); if not t then return end
  local m = U.clamp(tonumber(minutes) or 0, CFG.limits.mute_min, CFG.limits.mute_max)
  reason = U.safeText(reason, 180)
  Citizen.CreateThread(function()
    local cid = Core:getCharId(t)
    if not cid then Core.notify(src, 'Personagem do alvo n o carregado.'); return end
    SQL:mutePut(cid, os.time() + m * 60, reason, Core:getUid(src))
    Core.notify(src, ('[%d] silenciado por %d min.'):format(t, m))
    Core.notify(t, ('Voc  foi silenciado por %d min.'):format(m))
    Core:audit(src, 'mute', t, { minutes = m, reason = reason })
  end)
end)

RegisterNetEvent(E.ACT_UNMUTE)
AddEventHandler(E.ACT_UNMUTE, function(target)
  local src = source; if not reqPerm(src, 'mute') then return end
  local t = U.toSrc(target); if not t then return end
  Citizen.CreateThread(function()
    local cid = Core:getCharId(t); if not cid then return end
    SQL:muteRemove(cid)
    Core.notify(src, ('[%d] desmutado.'):format(t))
    Core:audit(src, 'unmute', t, {})
  end)
end)

-- ----------------------------------------------------------------------------
-- Filtro de chat: bloqueia mensagens de quem est  mute
-- ----------------------------------------------------------------------------
AddEventHandler('chatMessage', function(src, _, _)
  Citizen.CreateThread(function()
    local cid = Core:getCharId(src); if not cid then return end
    local m = SQL:muteGet(cid)
    if m and tonumber(m.expires_at) > os.time() then
      CancelEvent()
      Core.notify(src, 'Voc  est  silenciado at  ' ..
        os.date('%H:%M', tonumber(m.expires_at)))
    end
  end)
end)

-- ----------------------------------------------------------------------------
-- Export para outros resources (apreens es, etc) consultar
-- ----------------------------------------------------------------------------
exports('isJailed', function(char_id)
  local j = SQL:jailGet(tonumber(char_id) or 0)
  return j and tonumber(j.expires_at) > os.time() or false
end)

exports('isMuted', function(char_id)
  local m = SQL:muteGet(tonumber(char_id) or 0)
  return m and tonumber(m.expires_at) > os.time() or false
end)
