-- client/transport.lua — HAL Mumble nativa, modos, targets e submixes

local Cfg = VHubVoicePMA.Cfg
local E = VHubVoicePMA.E

local C = {
  running = true,
  ready = false,
  mode = Cfg.DEFAULT_MODE,
  radioChannel = 0,
  callChannel = 0,
  radioMembers = {},
  callMembers = {},
  radioTalkers = {},
  callTalkers = {},
  radioPressed = false,
  localTalking = false,
  voiceChannel = 0,
  radioVolume = tonumber(GetResourceKvpString('vhub_voice_radio_volume'))
    or Cfg.DEFAULT_RADIO_VOLUME,
  callVolume = tonumber(GetResourceKvpString('vhub_voice_call_volume'))
    or Cfg.DEFAULT_CALL_VOLUME,
  target = 1,
}

VHubVoicePMA.Client = C

local radioSubmix = -1
local callSubmix = -1


-- ============================================================
-- VALIDACAO / VOLUME
-- ============================================================

local function clamp_volume(value)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
  return math.max(0.0, math.min(1.0, number))
end

local function trusted_client()
  local caller = GetInvokingResource()
  return type(caller) == 'string' and Cfg.TRUSTED_CLIENT_RESOURCES[caller] == true
end

local function is_self(server_id)
  return tonumber(server_id) == GetPlayerServerId(PlayerId())
end


-- ============================================================
-- SUBMIXES
-- ============================================================

local function create_submixes()
  if radioSubmix == -1 then
    radioSubmix = CreateAudioSubmix('vhub_voice_radio')
    if radioSubmix ~= -1 then
      SetAudioSubmixEffectRadioFx(radioSubmix, 0)
      SetAudioSubmixEffectParamInt(radioSubmix, 0, GetHashKey('default'), 1)
      SetAudioSubmixEffectParamFloat(radioSubmix, 0, GetHashKey('freq_low'), 350.0)
      SetAudioSubmixEffectParamFloat(radioSubmix, 0, GetHashKey('freq_hi'), 4200.0)
      AddAudioSubmixOutput(radioSubmix, 0)
    end
  end

  if callSubmix == -1 then
    callSubmix = CreateAudioSubmix('vhub_voice_call')
    if callSubmix ~= -1 then
      SetAudioSubmixEffectRadioFx(callSubmix, 0)
      SetAudioSubmixEffectParamInt(callSubmix, 0, GetHashKey('default'), 1)
      SetAudioSubmixEffectParamFloat(callSubmix, 0, GetHashKey('freq_low'), 300.0)
      SetAudioSubmixEffectParamFloat(callSubmix, 0, GetHashKey('freq_hi'), 6000.0)
      AddAudioSubmixOutput(callSubmix, 0)
    end
  end
end

-- Reaplica volume e efeito do caminho de recepcao prioritario.
function C.refreshRemote(server_id)
  server_id = tonumber(server_id)
  if not server_id or is_self(server_id) then return end

  if C.radioTalkers[server_id] then
    MumbleSetVolumeOverrideByServerId(server_id, C.radioVolume)
    MumbleSetSubmixForServerId(server_id, radioSubmix)
  elseif C.callMembers[server_id] then
    MumbleSetVolumeOverrideByServerId(server_id, C.callVolume)
    MumbleSetSubmixForServerId(server_id, callSubmix)
  else
    MumbleSetVolumeOverrideByServerId(server_id, -1.0)
    MumbleSetSubmixForServerId(server_id, -1)
  end
end

-- Reconstrui os destinatarios explicitos sem tocar no canal raiz de proximidade.
function C.rebuildTargets()
  MumbleClearVoiceTargetPlayers(C.target)

  for server_id in pairs(C.callMembers) do
    if not is_self(server_id) then MumbleAddVoiceTargetPlayerByServerId(C.target, server_id) end
  end

  if C.radioPressed then
    for server_id in pairs(C.radioMembers) do
      if not is_self(server_id) then MumbleAddVoiceTargetPlayerByServerId(C.target, server_id) end
    end
  end
end

-- Aplica canal Mumble isolado pelo routing bucket publicado pelo HSS.
function C.applyRoutingBucket(bucket)
  bucket = tonumber(bucket)
  if not bucket or bucket % 1 ~= 0 or bucket < 0 or bucket > 65535 then return false end
  local channel = 100000 + bucket
  if C.voiceChannel == channel then return true end
  C.voiceChannel = channel
  MumbleSetVoiceChannel(channel)
  MumbleClearVoiceTargetChannels(C.target)
  MumbleAddVoiceTargetChannel(C.target, channel)
  return true
end


-- ============================================================
-- TRANSPORTE / MODO
-- ============================================================

-- Retorna true quando a fisiologia local bloqueia emissao de voz.
function C.isBlocked()
  local state = LocalPlayer and LocalPlayer.state
  return state and (state.hss_handcuffed == true or state.hss_consciousness == 'unconscious') or false
end

-- Atualiza a ativacao local sem conceder autoridade ao cliente.
function C.refreshActive()
  NetworkSetVoiceActive(C.ready and not C.isBlocked())
end

-- Aplica um modo de proximidade previamente validado pelo servidor.
function C.applyMode(mode)
  mode = tonumber(mode)
  local spec = mode and Cfg.MODES[mode]
  if not spec then return false end
  C.mode = mode
  MumbleSetTalkerProximity(spec.distance + 0.0)
  MumbleSetAudioInputDistance(spec.distance + 0.0)
  MumbleSetAudioOutputDistance(Cfg.MODES[#Cfg.MODES].distance + 0.0)
  TriggerEvent(E.MODE_CHANGED, mode, spec.label, spec.distance)
  return true
end

-- Inicializa o transporte Mumble de forma idempotente.
function C.initTransport()
  create_submixes()
  MumbleClearVoiceTarget(C.target)
  MumbleSetVoiceTarget(C.target)
  C.voiceChannel = 0
  C.applyRoutingBucket(tonumber(LocalPlayer.state.vhub_routing_bucket) or 0)
  MumbleSetAudioInputIntent(GetHashKey('speech'))
  C.applyMode(C.mode)
  C.rebuildTargets()
  C.refreshActive()
end

-- Limpa overrides e desativa voz nao gerenciada ao encerrar.
function C.cleanup()
  C.running = false
  C.ready = false
  C.radioPressed = false
  C.localTalking = false
  C.voiceChannel = 0
  local seen = {}
  for server_id in pairs(C.radioMembers) do seen[server_id] = true end
  for server_id in pairs(C.callMembers) do seen[server_id] = true end
  for server_id in pairs(seen) do
    if not is_self(server_id) then
      MumbleSetVolumeOverrideByServerId(server_id, -1.0)
      MumbleSetSubmixForServerId(server_id, -1)
    end
  end
  MumbleClearVoiceTarget(C.target)
  NetworkSetVoiceActive(false)
end


-- ============================================================
-- EXPORTS CLIENT
-- ============================================================

-- Solicita entrada em radio; o servidor revalida item e permissao.
exports('setRadioChannel', function(channel)
  if not trusted_client() then return false end
  TriggerServerEvent(E.RADIO_REQUEST, { channel = channel })
  return true
end)

-- Solicita saida da radio atual.
exports('leaveRadio', function()
  if not trusted_client() then return false end
  TriggerServerEvent(E.RADIO_REQUEST, { channel = 0 })
  return true
end)

-- Define o volume local de recepcao da radio.
exports('setRadioVolume', function(volume)
  if not trusted_client() then return false end
  local value = clamp_volume(volume)
  if not value then return false end
  C.radioVolume = value
  SetResourceKvp('vhub_voice_radio_volume', tostring(value))
  for server_id in pairs(C.radioTalkers) do C.refreshRemote(server_id) end
  return true
end)

-- Define o volume local de recepcao das ligacoes.
exports('setCallVolume', function(volume)
  if not trusted_client() then return false end
  local value = clamp_volume(volume)
  if not value then return false end
  C.callVolume = value
  SetResourceKvp('vhub_voice_call_volume', tostring(value))
  for server_id in pairs(C.callMembers) do C.refreshRemote(server_id) end
  return true
end)

-- Retorna copia do estado local de voz.
exports('getVoiceState', function()
  return {
    ready = C.ready,
    mode = C.mode,
    radio = C.radioChannel,
    call = C.callChannel,
    radio_talking = C.radioPressed,
    radio_volume = C.radioVolume,
    call_volume = C.callVolume,
  }
end)


-- ============================================================
-- LIFECYCLE
-- ============================================================

AddEventHandler('mumbleConnected', function()
  if not C.running then return end
  C.ready = false
  C.initTransport()
  TriggerServerEvent(E.SYNC_REQUEST)
end)

AddEventHandler('mumbleDisconnected', function()
  if C.radioPressed then
    C.radioPressed = false
    C.rebuildTargets()
    TriggerServerEvent(E.RADIO_TALK_REQUEST, false)
    TriggerEvent(E.RADIO_ACTIVE, false)
  end
  if C.localTalking then
    C.localTalking = false
    TriggerServerEvent(E.PROXIMITY_TALK_REQUEST, false)
    if C.callChannel ~= 0 then TriggerServerEvent(E.CALL_TALK_REQUEST, false) end
  end
  C.ready = false
  C.refreshActive()
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource == GetCurrentResourceName() then C.cleanup() end
end)
