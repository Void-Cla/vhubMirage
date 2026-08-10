-- client/channels.lua — sync targeted, comandos e PTT de radio/ligacao

local Cfg = VHubVoicePMA.Cfg
local E = VHubVoicePMA.E
local C = VHubVoicePMA.Client

local hssHandlers = {}

local function local_talking()
  local value = NetworkIsPlayerTalking(PlayerId())
  return value == true or value == 1
end


-- ============================================================
-- SNAPSHOTS
-- ============================================================

local function members_from(payload)
  local members, talkers = {}, {}
  if type(payload) ~= 'table' or type(payload.members) ~= 'table' then return members, talkers end
  local limit = math.min(#payload.members, 128)
  for index = 1, limit do
    local entry = payload.members[index]
    local server_id = type(entry) == 'table' and tonumber(entry.id) or nil
    if server_id and server_id >= 1 and server_id <= 65535 then
      members[server_id] = true
      if entry.talking == true then talkers[server_id] = true end
    end
  end
  return members, talkers
end

local function refresh_union(previous, current)
  local seen = {}
  for server_id in pairs(previous or {}) do seen[server_id] = true end
  for server_id in pairs(current or {}) do seen[server_id] = true end
  for server_id in pairs(seen) do C.refreshRemote(server_id) end
end

local function apply_radio(payload)
  local previous_members = C.radioMembers
  local previous_talkers = C.radioTalkers
  local channel = type(payload) == 'table' and tonumber(payload.channel) or 0
  if not channel or channel % 1 ~= 0 or channel < 0 or channel > Cfg.RADIO.MAX_CHANNEL then channel = 0 end
  local members, talkers = members_from(payload)
  C.radioChannel = channel
  C.radioMembers = members
  C.radioTalkers = talkers

  if C.radioChannel == 0 and C.radioPressed then
    C.radioPressed = false
    TriggerServerEvent(E.RADIO_TALK_REQUEST, false)
  end

  C.rebuildTargets()
  refresh_union(previous_members, members)
  refresh_union(previous_talkers, talkers)
end

local function apply_call(payload)
  local previous_members = C.callMembers
  local previous_talkers = C.callTalkers
  local channel = type(payload) == 'table' and tonumber(payload.channel) or 0
  if not channel or channel % 1 ~= 0 or channel < 0 or channel > Cfg.CALL.MAX_CHANNEL then channel = 0 end
  local members, talkers = members_from(payload)
  C.callChannel = channel
  C.callMembers = members
  C.callTalkers = talkers
  C.rebuildTargets()
  refresh_union(previous_members, members)
  refresh_union(previous_talkers, talkers)
  if C.callChannel ~= 0 and C.localTalking then
    TriggerServerEvent(E.CALL_TALK_REQUEST, true)
  end
end

local function apply_member(kind, server_id, present, talking)
  server_id = tonumber(server_id)
  if not server_id or server_id % 1 ~= 0 or server_id < 1 or server_id > 65535
      or type(present) ~= 'boolean' or type(talking) ~= 'boolean' then return end
  local members = kind == 'radio' and C.radioMembers or C.callMembers
  local talkers = kind == 'radio' and C.radioTalkers or C.callTalkers
  if present then
    members[server_id] = true
    talkers[server_id] = talking or nil
  else
    members[server_id] = nil
    talkers[server_id] = nil
  end
  if kind == 'call' or C.radioPressed then C.rebuildTargets() end
  C.refreshRemote(server_id)
end


-- ============================================================
-- EVENTOS TARGETED
-- ============================================================

RegisterNetEvent(E.SYNC, function(payload)
  if type(payload) ~= 'table' or payload.active ~= true then return end
  C.ready = true
  C.applyMode(payload.mode)
  apply_radio(payload.radio)
  apply_call(payload.call)
  C.initTransport()
end)

RegisterNetEvent(E.RADIO_SYNC, function(payload)
  apply_radio(payload)
end)

RegisterNetEvent(E.RADIO_MEMBER, function(server_id, present, talking)
  apply_member('radio', server_id, present, talking)
end)

RegisterNetEvent(E.CALL_SYNC, function(payload)
  apply_call(payload)
end)

RegisterNetEvent(E.CALL_MEMBER, function(server_id, present, talking)
  apply_member('call', server_id, present, talking)
end)

RegisterNetEvent(E.RADIO_TALK, function(server_id, talking)
  server_id = tonumber(server_id)
  if not server_id or type(talking) ~= 'boolean' or not C.radioMembers[server_id] then return end
  C.radioTalkers[server_id] = talking or nil
  C.refreshRemote(server_id)
end)

RegisterNetEvent(E.CALL_TALK, function(server_id, talking)
  server_id = tonumber(server_id)
  if not server_id or type(talking) ~= 'boolean' or not C.callMembers[server_id] then return end
  C.callTalkers[server_id] = talking or nil
end)


-- ============================================================
-- COMANDOS
-- ============================================================

RegisterCommand('cyclevoice', function()
  if not C.ready then return end
  local next_mode = C.mode + 1
  if not Cfg.MODES[next_mode] then next_mode = 1 end
  TriggerServerEvent(E.MODE_REQUEST, next_mode)
end, false)

RegisterKeyMapping('cyclevoice', 'Voz: alternar alcance', 'keyboard', Cfg.CLIENT.MODE_KEY)

RegisterCommand('voiceup', function()
  if not C.ready then return end
  local next_mode = math.min(#Cfg.MODES, C.mode + 1)
  TriggerServerEvent(E.MODE_REQUEST, next_mode)
end, false)

RegisterKeyMapping('voiceup', 'Voz: aumentar alcance', 'keyboard', 'HOME')

RegisterCommand('voicedown', function()
  if not C.ready then return end
  local next_mode = math.max(1, C.mode - 1)
  TriggerServerEvent(E.MODE_REQUEST, next_mode)
end, false)

RegisterKeyMapping('voicedown', 'Voz: diminuir alcance', 'keyboard', 'END')

RegisterCommand('radio', function(_, args)
  local raw = args and args[1]
  local channel = raw == 'sair' and 0 or tonumber(raw)
  if not channel or channel % 1 ~= 0 then
    TriggerEvent(E.NOTIFY, 'info', 'Use /radio <1-999> ou /radio sair.')
    return
  end
  TriggerServerEvent(E.RADIO_REQUEST, { channel = channel })
end, false)

local function stop_radio()
  if not C.radioPressed then return end
  C.radioPressed = false
  C.rebuildTargets()
  TriggerServerEvent(E.RADIO_TALK_REQUEST, false)
  TriggerEvent(E.RADIO_ACTIVE, false)
end

RegisterCommand('+vhubRadio', function()
  if not C.ready or C.radioPressed or C.radioChannel == 0 or C.isBlocked() then return end
  C.radioPressed = true
  C.rebuildTargets()
  TriggerServerEvent(E.RADIO_TALK_REQUEST, true)
  TriggerEvent(E.RADIO_ACTIVE, true)

  CreateThread(function()
    while C.running and C.radioPressed do
      SetControlNormal(0, 249, 1.0)
      Wait(0)
    end
  end)
end, false)

RegisterCommand('-vhubRadio', function()
  stop_radio()
end, false)

RegisterKeyMapping('+vhubRadio', 'Voz: transmitir no radio', 'keyboard', Cfg.CLIENT.RADIO_KEY)


-- ============================================================
-- FISIOLOGIA / BOOT
-- ============================================================

local function refresh_block()
  if C.isBlocked() then stop_radio() end
  C.refreshActive()
end

CreateThread(function()
  Wait(500)
  C.initTransport()
  TriggerServerEvent(E.SYNC_REQUEST)

  local bag = ('player:%d'):format(GetPlayerServerId(PlayerId()))
  hssHandlers[#hssHandlers + 1] = AddStateBagChangeHandler('hss_handcuffed', bag, refresh_block)
  hssHandlers[#hssHandlers + 1] = AddStateBagChangeHandler('hss_consciousness', bag, refresh_block)
  hssHandlers[#hssHandlers + 1] = AddStateBagChangeHandler('vhub_voice_mode', bag,
    function(_, _, value) C.applyMode(value) end)
  hssHandlers[#hssHandlers + 1] = AddStateBagChangeHandler('vhub_routing_bucket', bag,
    function(_, _, value) C.applyRoutingBucket(value) end)

  while C.running do
    local current = C.ready and not C.isBlocked() and local_talking() or false
    if current ~= C.localTalking then
      C.localTalking = current
      TriggerServerEvent(E.PROXIMITY_TALK_REQUEST, current)
      if C.callChannel ~= 0 then TriggerServerEvent(E.CALL_TALK_REQUEST, current) end
    end
    Wait(C.ready and Cfg.CLIENT.TALK_INTERVAL_MS or 500)
  end
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  stop_radio()
  if C.localTalking then
    TriggerServerEvent(E.PROXIMITY_TALK_REQUEST, false)
    if C.callChannel ~= 0 then TriggerServerEvent(E.CALL_TALK_REQUEST, false) end
  end
  for _, cookie in ipairs(hssHandlers) do RemoveStateBagChangeHandler(cookie) end
  hssHandlers = {}
end)
