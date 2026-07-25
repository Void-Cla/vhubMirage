-- server/channels.lua — memberships efemeras e sincronizacao privada de voz

local Cfg = VHubVoicePMA.Cfg
local E = VHubVoicePMA.E

local S = {
  running = true,
  players = {},
  radios = {},
  calls = {},
  rate = {},
}

VHubVoicePMA.Server = S


-- ============================================================
-- VALIDACAO
-- ============================================================

local function integer(value, min, max)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
  if number % 1 ~= 0 or number < min or number > max then return nil end
  return number
end

local function online(src)
  src = integer(src, 1, 65535)
  return src and GetPlayerName(src) ~= nil and src or nil
end

local function core_character(src)
  local called, char_id = pcall(function() return exports.vhub:getCharacterId(src) end)
  return called and integer(char_id, 1, 4294967295) or nil
end

local function notify(src, kind, message)
  TriggerClientEvent(E.NOTIFY, src, kind, message)
end

local function rate_ok(src, action)
  local now = GetGameTimer()
  local key = action .. ':' .. tostring(src)
  local previous = S.rate[key]
  if previous and now - previous < (Cfg.RATE_MS[action] or 500) then return false end
  S.rate[key] = now
  return true
end

local function count_members(set)
  local count = 0
  for _ in pairs(set or {}) do count = count + 1 end
  return count
end

local function radio_permission(channel)
  for _, rule in ipairs(Cfg.RADIO.PERMISSION_RANGES) do
    if channel >= rule.min and channel <= rule.max then return rule.permission end
  end
  return nil
end

local function communication_access(src)
  if GetResourceState('vhub_hss') ~= 'started' then return false end
  local called, blocks = pcall(function() return exports.vhub_hss:getAnimBlocks(src) end)
  if not called or type(blocks) ~= 'table' then return false end
  return blocks.handcuffed ~= true and blocks.unconscious ~= true
end

local function radio_access(src, channel)
  if Cfg.RADIO.REQUIRE_ITEM then
    if GetResourceState('vhub_inventory') ~= 'started' then return false end
    local called, has_item = pcall(function()
      return exports.vhub_inventory:hasItem(src, Cfg.RADIO.ITEM, 1)
    end)
    if not called or has_item ~= true then return false end
  end

  local permission = radio_permission(channel)
  if permission then
    if GetResourceState('vhub_groups') ~= 'started' then return false end
    local called, allowed = pcall(function()
      return exports.vhub_groups:hasPermission(src, permission)
    end)
    if not called or allowed ~= true then return false end
  end

  return communication_access(src)
end

local function player_state(src)
  local state = S.players[src]
  if state then return state end
  state = {
    char_id = nil,
    mode = Cfg.DEFAULT_MODE,
    proximity_talking = false,
    radio = 0,
    radio_talking = false,
    call = 0,
    call_talking = false,
  }
  S.players[src] = state
  return state
end

local function publish(src, state)
  pcall(function()
    local bag = Player(src).state
    bag:set('vhub_voice_mode', state.mode, true)
    bag:set('vhub_voice_talking', state.proximity_talking, true)
  end)
end


-- ============================================================
-- SNAPSHOTS TARGETED
-- ============================================================

local function snapshot(set, talking_field)
  local out = {}
  for src in pairs(set or {}) do
    local state = S.players[src]
    if state and online(src) then
      out[#out + 1] = { id = src, talking = state[talking_field] == true }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

local function sync_radio_to(src, channel)
  TriggerClientEvent(E.RADIO_SYNC, src, {
    channel = channel,
    members = snapshot(S.radios[channel], 'radio_talking'),
  })
end

local function sync_call_to(src, channel)
  TriggerClientEvent(E.CALL_SYNC, src, {
    channel = channel,
    members = snapshot(S.calls[channel], 'call_talking'),
  })
end

local function publish_member(set, event_name, changed_src, present, talking)
  for member in pairs(set or {}) do
    if member ~= changed_src and online(member) then
      TriggerClientEvent(event_name, member, changed_src, present, talking)
    end
  end
end


-- ============================================================
-- MEMBERSHIP
-- ============================================================

local function leave_radio(src, state)
  local old = state.radio
  if old == 0 then return false end
  local set = S.radios[old]
  if set then
    set[src] = nil
    publish_member(set, E.RADIO_MEMBER, src, false, false)
    if next(set) == nil then S.radios[old] = nil end
  end
  state.radio = 0
  state.radio_talking = false
  TriggerClientEvent(E.RADIO_SYNC, src, { channel = 0, members = {} })
  publish(src, state)
  return true
end

local function leave_call(src, state)
  local old = state.call
  if old == 0 then return false end
  local set = S.calls[old]
  if set then
    set[src] = nil
    publish_member(set, E.CALL_MEMBER, src, false, false)
    if next(set) == nil then S.calls[old] = nil end
  end
  state.call = 0
  state.call_talking = false
  TriggerClientEvent(E.CALL_SYNC, src, { channel = 0, members = {} })
  publish(src, state)
  return true
end

local membershipRevalidationRunning = false

local function start_membership_revalidation()
  if membershipRevalidationRunning then return end
  membershipRevalidationRunning = true

  CreateThread(function()
    while S.running and (next(S.radios) or next(S.calls)) do
      Wait(math.min(Cfg.RADIO.REVALIDATE_MS, Cfg.CALL.REVALIDATE_MS))
      local revoked, revokedCalls = {}, {}
      for channel, set in pairs(S.radios) do
        for src in pairs(set) do
          if not radio_access(src, channel) then revoked[#revoked + 1] = src end
        end
      end
      for _, set in pairs(S.calls) do
        for src in pairs(set) do
          if not communication_access(src) then revokedCalls[#revokedCalls + 1] = src end
        end
      end
      for _, src in ipairs(revoked) do
        local state = S.players[src]
        if state and state.radio ~= 0 then
          leave_radio(src, state)
          notify(src, 'erro', 'Acesso ao rádio removido.')
        end
      end
      for _, src in ipairs(revokedCalls) do
        local state = S.players[src]
        if state and state.call ~= 0 then
          leave_call(src, state)
          notify(src, 'erro', 'Ligacao encerrada por indisponibilidade de voz.')
        end
      end
    end
    membershipRevalidationRunning = false
  end)
end

-- Define o modo de proximidade validado e replica apenas o indice.
function S.setMode(src, mode)
  src = online(src)
  mode = integer(mode, 1, #Cfg.MODES)
  if not src or not mode or not rate_ok(src, 'mode') then return false end
  local state = player_state(src)
  if not state.char_id then return false end
  if state.mode == mode then
    publish(src, state)
    return true
  end
  state.mode = mode
  publish(src, state)
  return true
end

-- Entra ou sai de radio com item, permissao, fisiologia e capacidade revalidados.
function S.setRadio(src, channel)
  src = online(src)
  channel = integer(channel, 0, Cfg.RADIO.MAX_CHANNEL)
  if not src or channel == nil then return false, 'canal_invalido' end
  local state = player_state(src)
  if not state.char_id then return false, 'sem_personagem' end
  if channel == state.radio then return true end
  if channel == 0 then leave_radio(src, state); return true end
  if not rate_ok(src, 'radio') then return false, 'aguarde' end
  if channel < Cfg.RADIO.MIN_CHANNEL or not radio_access(src, channel) then
    return false, 'acesso_negado'
  end
  local target = S.radios[channel]
  if target and count_members(target) >= Cfg.RADIO.MAX_MEMBERS then return false, 'canal_cheio' end

  leave_radio(src, state)
  target = S.radios[channel] or {}
  S.radios[channel] = target
  target[src] = true
  state.radio = channel
  state.radio_talking = false
  publish(src, state)
  publish_member(target, E.RADIO_MEMBER, src, true, false)
  sync_radio_to(src, channel)
  start_membership_revalidation()
  return true
end

-- Entra ou sai de ligacao por contrato server-side confiavel.
function S.setCall(src, channel)
  src = online(src)
  channel = integer(channel, 0, Cfg.CALL.MAX_CHANNEL)
  if not src or channel == nil then return false, 'canal_invalido' end
  local state = player_state(src)
  if not state.char_id then return false, 'sem_personagem' end
  if channel == state.call then return true end
  if channel == 0 then leave_call(src, state); return true end
  if not rate_ok(src, 'call') then return false, 'aguarde' end
  if channel < Cfg.CALL.MIN_CHANNEL then return false, 'canal_invalido' end
  if not communication_access(src) then return false, 'acesso_negado' end
  local target = S.calls[channel]
  if target and count_members(target) >= Cfg.CALL.MAX_MEMBERS then return false, 'ligacao_cheia' end

  leave_call(src, state)
  target = S.calls[channel] or {}
  S.calls[channel] = target
  target[src] = true
  state.call = channel
  state.call_talking = false
  publish(src, state)
  publish_member(target, E.CALL_MEMBER, src, true, false)
  sync_call_to(src, channel)
  start_membership_revalidation()
  return true
end


-- ============================================================
-- ATIVIDADE
-- ============================================================

-- Publica PTT de radio somente apos revalidar membership e acesso.
function S.setRadioTalking(src, talking)
  src = online(src)
  if not src or type(talking) ~= 'boolean' then return false end
  local state = player_state(src)
  if state.radio == 0 then return false end
  if state.radio_talking == talking then return true end
  if talking and not rate_ok(src, 'radio_talk') then return false end
  if talking and not radio_access(src, state.radio) then
    leave_radio(src, state)
    notify(src, 'erro', 'Radio indisponivel ou acesso removido.')
    return false
  end
  state.radio_talking = talking
  local set = S.radios[state.radio]
  if not set then return false end
  for member in pairs(set) do TriggerClientEvent(E.RADIO_TALK, member, src, talking) end
  return true
end

-- Publica atividade de proximidade como State Bag server-owned.
function S.setProximityTalking(src, talking)
  src = online(src)
  if not src or type(talking) ~= 'boolean' then return false end
  local state = player_state(src)
  if not state.char_id or state.proximity_talking == talking then return state.char_id ~= nil end
  if talking and not rate_ok(src, 'proximity_talk') then return false end
  state.proximity_talking = talking
  publish(src, state)
  return true
end

-- Publica atividade da ligacao sem permitir mutacao de membership pelo cliente.
function S.setCallTalking(src, talking)
  src = online(src)
  if not src or type(talking) ~= 'boolean' then return false end
  local state = player_state(src)
  if state.call == 0 or state.call_talking == talking then return state.call ~= 0 end
  if talking and not rate_ok(src, 'call_talk') then return false end
  if talking and not communication_access(src) then
    leave_call(src, state)
    notify(src, 'erro', 'Ligacao encerrada por indisponibilidade de voz.')
    return false
  end
  state.call_talking = talking
  local set = S.calls[state.call]
  if not set then return false end
  for member in pairs(set) do TriggerClientEvent(E.CALL_TALK, member, src, talking) end
  return true
end


-- ============================================================
-- LIFECYCLE / QUERIES
-- ============================================================

-- Reidrata ou troca a sessao de personagem de forma replay-safe.
function S.characterLoad(user)
  if type(user) ~= 'table' then return end
  local src = online(user.source)
  local char_id = integer(user.char_id, 1, 4294967295)
  if not src or not char_id then return end
  local state = player_state(src)
  if state.char_id and state.char_id ~= char_id then
    leave_radio(src, state)
    leave_call(src, state)
    state.mode = Cfg.DEFAULT_MODE
    state.proximity_talking = false
  end
  state.char_id = char_id
  publish(src, state)
  S.sync(src, true)
end

-- Envia somente ao proprio jogador o snapshot corrente.
function S.sync(src, force)
  src = online(src)
  if not src then return false end
  local state = S.players[src]
  if not state or not state.char_id then
    local char_id = core_character(src)
    if not char_id then return false end
    state = player_state(src)
    state.char_id = char_id
    publish(src, state)
  end
  if force ~= true and not rate_ok(src, 'sync') then return false end
  TriggerClientEvent(E.SYNC, src, {
    active = true,
    mode = state.mode,
    proximity_talking = state.proximity_talking,
    radio = { channel = state.radio, members = snapshot(S.radios[state.radio], 'radio_talking') },
    call = { channel = state.call, members = snapshot(S.calls[state.call], 'call_talking') },
  })
  return true
end

-- Retorna copia do estado efemero do jogador.
function S.getState(src)
  src = online(src)
  local state = src and S.players[src]
  if not state then return nil end
  return {
    char_id = state.char_id,
    mode = state.mode,
    radio = state.radio,
    radio_talking = state.radio_talking,
    call = state.call,
    call_talking = state.call_talking,
  }
end

-- Retorna lista ordenada e copiada dos membros de uma radio.
function S.getRadioMembers(channel)
  channel = integer(channel, Cfg.RADIO.MIN_CHANNEL, Cfg.RADIO.MAX_CHANNEL)
  if not channel then return {} end
  local entries = snapshot(S.radios[channel], 'radio_talking')
  local out = {}
  for i = 1, #entries do out[i] = entries[i].id end
  return out
end

-- Limpa estado, rate buckets e memberships de uma origem.
function S.drop(src)
  src = tonumber(src)
  local state = src and S.players[src]
  if state then
    leave_radio(src, state)
    leave_call(src, state)
    S.players[src] = nil
  end
  local suffix = ':' .. tostring(src)
  for key in pairs(S.rate) do
    if key:sub(-#suffix) == suffix then S.rate[key] = nil end
  end
end

-- Limpa replicas publicadas antes do encerramento do resource.
function S.shutdown()
  S.running = false
  for src, state in pairs(S.players) do
    state.radio = 0
    state.call = 0
    state.radio_talking = false
    state.call_talking = false
    state.proximity_talking = false
    publish(src, state)
  end
  S.players = {}
  S.radios = {}
  S.calls = {}
  S.rate = {}
end
