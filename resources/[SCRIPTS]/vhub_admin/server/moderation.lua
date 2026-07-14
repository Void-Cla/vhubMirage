-- server/moderation.lua — disciplina persistente e aplicada pelo servidor
---@diagnostic disable: undefined-global

local SQL = VHubAdmin.SQL
local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E
local U = VHubAdmin.U

local M = {
  jailed = {}, -- [src] = { char_id, expires_at, reason }
  muted = {}, -- [src] = { char_id, expires_at }
  jailByChar = {},
  muteByChar = {},
}
VHubAdmin.Moderation = M

local running = true


-- ============================================================
-- ESTADO DISCIPLINAR
-- ============================================================

local function jailPayload(state)
  return {
    expires_at = state.expires_at,
    reason = state.reason,
    pos = CFG.jail.pos,
  }
end

-- Replica a prisão como estado visual; o servidor mantém a autoridade real.
function M:applyJail(src, state, relocate)
  src = tonumber(src)
  if not src or not GetPlayerName(src) then return false end

  self.jailed[src] = state
  self.jailByChar[state.char_id] = state
  Player(src).state:set('vhub_admin_jail', jailPayload(state), true)
  if relocate then Core:teleport(src, CFG.jail.pos) end
  return true
end

-- Libera uma prisão em memória, State Bag e persistência.
function M:releaseJail(src, charId, removeDb)
  src = tonumber(src)
  charId = tonumber(charId)
  if charId then self.jailByChar[charId] = nil end
  if src then
    self.jailed[src] = nil
    if GetPlayerName(src) then Player(src).state:set('vhub_admin_jail', nil, true) end
  end
  if removeDb and charId then SQL:jailRemove(charId) end
end

-- Mantém o mute disponível para a checagem síncrona do evento de chat.
function M:applyMute(src, state)
  src = tonumber(src)
  if not src then return end
  self.muted[src] = state
  self.muteByChar[state.char_id] = state
end

-- Libera o mute em memória e opcionalmente no banco.
function M:releaseMute(src, charId, removeDb)
  src = tonumber(src)
  charId = tonumber(charId)
  if charId then self.muteByChar[charId] = nil end
  if src then self.muted[src] = nil end
  if removeDb and charId then SQL:muteRemove(charId) end
end

-- Reidrata disciplina do personagem sem depender de estado do cliente.
function M:hydrate(src, user)
  src = tonumber(src)
  local charId = user and tonumber(user.char_id) or nil
  if not src or not charId then return end

  Citizen.CreateThread(function()
    local now = os.time()
    local jail = self.jailByChar[charId] or SQL:jailGet(charId)
    if jail and tonumber(jail.expires_at) > now then
      self:applyJail(src, {
        char_id = charId,
        expires_at = tonumber(jail.expires_at),
        reason = U.safeText(jail.reason, 180),
      }, true)
    elseif jail then
      self:releaseJail(src, charId, true)
    end

    local mute = self.muteByChar[charId] or SQL:muteGet(charId)
    if mute and tonumber(mute.expires_at) > now then
      self:applyMute(src, { char_id = charId, expires_at = tonumber(mute.expires_at) })
    elseif mute then
      self:releaseMute(src, charId, true)
    end
  end)
end

-- Carrega os registros ativos uma vez no boot para sessões que chegarem depois.
function M:hydrateActive()
  local now = os.time()
  for _, jail in ipairs(SQL:jailListActive() or {}) do
    self.jailByChar[tonumber(jail.char_id)] = {
      char_id = tonumber(jail.char_id),
      expires_at = tonumber(jail.expires_at),
      reason = U.safeText(jail.reason, 180),
    }
  end
  for _, mute in ipairs(SQL:muteListActive() or {}) do
    self.muteByChar[tonumber(mute.char_id)] = {
      char_id = tonumber(mute.char_id),
      expires_at = tonumber(mute.expires_at),
    }
  end
  return now
end

-- Remove referências transitórias no disconnect.
function M:drop(src)
  self.jailed[tonumber(src)] = nil
  self.muted[tonumber(src)] = nil
end


-- ============================================================
-- MODERAÇÃO
-- ============================================================

RegisterNetEvent(E.ACT_KICK)
AddEventHandler(E.ACT_KICK, function(target, reason)
  local src = source
  if not Core:guard(src, 'kick', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  local message = U.safeText(reason, 180)
  if not targetSrc or message == '' then return Core:notify(src, 'Alvo ou motivo inválido.', 'erro') end

  Core:audit(src, 'kick', targetSrc, { reason = message })
  DropPlayer(targetSrc, 'Expulso pela equipe: ' .. message)
end)

RegisterNetEvent(E.ACT_BAN)
AddEventHandler(E.ACT_BAN, function(target, reason)
  local src = source
  if not Core:guard(src, 'ban', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  local message = U.safeText(reason, 180)
  local uid = targetSrc and Core:getUid(targetSrc) or nil
  if not uid or message == '' then return Core:notify(src, 'Alvo ou motivo inválido.', 'erro') end

  local ok = pcall(function()
    return exports.vhub:banPlayer(uid, message, tostring(Core:getUid(src) or 'admin'))
  end)
  if not ok then return Core:notify(src, 'Banimento recusado pelo CORE.', 'erro') end

  Core:audit(src, 'ban', targetSrc, { uid = uid, reason = message })
  Core:notify(src, ('UID %d banido.'):format(uid), 'sucesso')
end)

RegisterNetEvent(E.ACT_UNBAN)
AddEventHandler(E.ACT_UNBAN, function(uid)
  local src = source
  if not Core:guard(src, 'unban', 'moderation') then return end
  uid = U.number(uid, 1, 2147483647)
  if not uid or uid % 1 ~= 0 then return Core:notify(src, 'UID inválido.', 'erro') end

  local ok = pcall(function() return exports.vhub:unbanPlayer(math.floor(uid)) end)
  if not ok then return Core:notify(src, 'Desbanimento recusado pelo CORE.', 'erro') end

  Core:audit(src, 'unban', nil, { uid = math.floor(uid) })
  Core:notify(src, ('UID %d desbanido.'):format(uid), 'sucesso')
end)

RegisterNetEvent(E.ACT_WARN)
AddEventHandler(E.ACT_WARN, function(target, message)
  local src = source
  if not Core:guard(src, 'warn', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  local text = U.safeText(message, 180)
  if not targetSrc or text == '' then return Core:notify(src, 'Alvo ou mensagem inválida.', 'erro') end

  Core:notify(targetSrc, 'Aviso da equipe: ' .. text, 'aviso')
  Core:notify(src, ('Aviso enviado para [%d].'):format(targetSrc), 'sucesso')
  Core:audit(src, 'warn', targetSrc, { message = text })
end)

RegisterNetEvent(E.ACT_JAIL)
AddEventHandler(E.ACT_JAIL, function(target, minutes, reason)
  local src = source
  if not Core:guard(src, 'jail', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  local duration = U.number(minutes, CFG.limits.jail_min, CFG.limits.jail_max)
  local text = U.safeText(reason, 180)
  if not targetSrc or not duration or text == '' then
    return Core:notify(src, 'Alvo, tempo ou motivo inválido.', 'erro')
  end

  Citizen.CreateThread(function()
    local charId = Core:getCharId(targetSrc)
    if not charId then return Core:notify(src, 'Personagem do alvo não carregado.', 'erro') end

    local expires = os.time() + math.floor(duration) * 60
    SQL:jailPut(charId, expires, text, Core:getUid(src))
    M:applyJail(targetSrc, { char_id = charId, expires_at = expires, reason = text }, true)
    Core:notify(targetSrc, ('Você foi preso por %d minutos: %s'):format(duration, text), 'erro')
    Core:notify(src, ('[%d] preso por %d minutos.'):format(targetSrc, duration), 'sucesso')
    Core:audit(src, 'jail', targetSrc, { minutes = duration, reason = text })
  end)
end)

RegisterNetEvent(E.ACT_UNJAIL)
AddEventHandler(E.ACT_UNJAIL, function(target)
  local src = source
  if not Core:guard(src, 'jail', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  if not targetSrc then return Core:notify(src, 'Alvo inválido.', 'erro') end

  Citizen.CreateThread(function()
    local charId = Core:getCharId(targetSrc)
    if not charId then return end
    M:releaseJail(targetSrc, charId, true)
    Core:notify(targetSrc, 'Você foi liberado.', 'sucesso')
    Core:notify(src, ('[%d] liberado.'):format(targetSrc), 'sucesso')
    Core:audit(src, 'unjail', targetSrc, {})
  end)
end)

RegisterNetEvent(E.ACT_MUTE)
AddEventHandler(E.ACT_MUTE, function(target, minutes, reason)
  local src = source
  if not Core:guard(src, 'mute', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  local duration = U.number(minutes, CFG.limits.mute_min, CFG.limits.mute_max)
  local text = U.safeText(reason, 180)
  if not targetSrc or not duration or text == '' then
    return Core:notify(src, 'Alvo, tempo ou motivo inválido.', 'erro')
  end

  Citizen.CreateThread(function()
    local charId = Core:getCharId(targetSrc)
    if not charId then return end
    local expires = os.time() + math.floor(duration) * 60
    SQL:mutePut(charId, expires, text, Core:getUid(src))
    M:applyMute(targetSrc, { char_id = charId, expires_at = expires })
    Core:notify(targetSrc, ('Você foi silenciado por %d minutos.'):format(duration), 'erro')
    Core:notify(src, ('[%d] silenciado por %d minutos.'):format(targetSrc, duration), 'sucesso')
    Core:audit(src, 'mute', targetSrc, { minutes = duration, reason = text })
  end)
end)

RegisterNetEvent(E.ACT_UNMUTE)
AddEventHandler(E.ACT_UNMUTE, function(target)
  local src = source
  if not Core:guard(src, 'mute', 'moderation') then return end
  local targetSrc = Core:onlineTarget(target)
  if not targetSrc then return Core:notify(src, 'Alvo inválido.', 'erro') end

  Citizen.CreateThread(function()
    local charId = Core:getCharId(targetSrc)
    if not charId then return end
    M:releaseMute(targetSrc, charId, true)
    Core:notify(targetSrc, 'Seu chat foi liberado.', 'sucesso')
    Core:notify(src, ('[%d] desmutado.'):format(targetSrc), 'sucesso')
    Core:audit(src, 'unmute', targetSrc, {})
  end)
end)


-- ============================================================
-- ENFORCEMENT
-- ============================================================

-- Cancela o chat no próprio frame do evento; Await depois de CancelEvent é tarde demais.
AddEventHandler('chatMessage', function(rawSrc)
  local src = tonumber(rawSrc)
  local state = src and M.muted[src] or nil
  if not state then return end
  if state.expires_at <= os.time() then
    M:releaseMute(src, state.char_id, false)
    Citizen.CreateThread(function() SQL:muteRemove(state.char_id) end)
    return
  end
  CancelEvent()
  Core:notify(src, 'Você está silenciado.', 'negado')
end)

Citizen.CreateThread(function()
  while running do
    Citizen.Wait(CFG.jail.check_ms)
    local now = os.time()

    for src, state in pairs(M.jailed) do
      if not GetPlayerName(src) then
        M.jailed[src] = nil
      elseif state.expires_at <= now then
        M:releaseJail(src, state.char_id, true)
        Core:notify(src, 'Sua prisão expirou.', 'sucesso')
      else
        local pos = Core:coordsOf(src)
        local cell = CFG.jail.pos
        if pos then
          local dx, dy, dz = pos.x - cell.x, pos.y - cell.y, pos.z - cell.z
          if dx * dx + dy * dy + dz * dz > CFG.jail.radius * CFG.jail.radius then
            Core:teleport(src, cell)
            Core:notify(src, 'Você continua preso.', 'negado')
          end
        end
      end
    end

    for src, state in pairs(M.muted) do
      if not GetPlayerName(src) then
        M.muted[src] = nil
      elseif state.expires_at <= now then
        M:releaseMute(src, state.char_id, true)
        Core:notify(src, 'Seu silêncio expirou.', 'sucesso')
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then running = false end
end)

-- Consulta pública e somente leitura da disciplina persistente.
exports('isJailed', function(charId)
  local state = M.jailByChar[tonumber(charId)]
  return state and state.expires_at > os.time() or false
end)

exports('isMuted', function(charId)
  local state = M.muteByChar[tonumber(charId)]
  return state and state.expires_at > os.time() or false
end)
