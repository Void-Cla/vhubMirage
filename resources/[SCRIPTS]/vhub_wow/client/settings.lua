-- client/settings.lua — preferencia streamer, painel e master gain do WOW

local STATE = {
  streamer = GetResourceKvpString('vhub_wow_streamer_mode') == '1',
  voice_activity = 0.0,
  sound_count = 0,
  settings_open = false,
}

VHubWOWClient = VHubWOWClient or {}


-- ============================================================
-- STATE / NUI
-- ============================================================

local function finite(value)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
  return number
end

local function send(type_name, data)
  SendNUIMessage({ type = type_name, data = data or {} })
end

local function snapshot()
  return {
    streamer_mode = STATE.streamer,
    voice_activity = STATE.voice_activity,
    has_audio = STATE.sound_count > 0,
  }
end

local function set_streamer(active, persist)
  if type(active) ~= 'boolean' then return false end
  if STATE.streamer == active then
    send('wow:settings:state', snapshot())
    return true
  end
  STATE.streamer = active
  if persist then SetResourceKvp('vhub_wow_streamer_mode', active and '1' or '0') end
  send('wow:audio:master', snapshot())
  send('wow:settings:state', snapshot())
  return true
end

local function open_settings()
  if STATE.settings_open then return true end
  STATE.settings_open = true
  SetNuiFocus(true, true)
  send('wow:settings:open', snapshot())
  return true
end

local function close_settings()
  if not STATE.settings_open then return end
  STATE.settings_open = false
  SetNuiFocus(false, false)
  send('wow:settings:close', {})
end


-- ============================================================
-- API INTERNA
-- ============================================================

-- Retorna o modo streamer para o motor aplicar antes do primeiro frame.
function VHubWOWClient.isStreamerMode()
  return STATE.streamer
end

-- Atualiza demanda do voicePMA somente nas transicoes 0 para 1 e 1 para 0.
function VHubWOWClient.setSoundCount(count)
  count = math.max(0, math.floor(tonumber(count) or 0))
  local was_active = STATE.sound_count > 0
  STATE.sound_count = count
  local active = count > 0
  if was_active ~= active then
    pcall(function() exports.vhub_voicePMA:setDuckingDemand(active) end)
    send('wow:settings:state', snapshot())
  end
end


-- ============================================================
-- EXPORTS CLIENT
-- ============================================================

-- Recebe atividade normalizada exclusivamente do owner de voz.
exports('setVoiceActivity', function(value)
  if GetInvokingResource() ~= 'vhub_voicePMA' then return false end
  local number = finite(value)
  if not number or number < 0.0 or number > 1.0 then return false end
  if math.abs(number - STATE.voice_activity) < 0.01 then return true end
  STATE.voice_activity = number
  send('wow:audio:master', snapshot())
  send('wow:settings:state', snapshot())
  return true
end)

-- Define a preferencia streamer por consumidor autorizado.
exports('setStreamerMode', function(active)
  local caller = GetInvokingResource()
  if type(caller) ~= 'string' or WOW_Config.TrustedClientResources[caller] ~= true then return false end
  return set_streamer(active, true)
end)

-- Retorna a preferencia streamer local.
exports('getStreamerMode', function()
  return STATE.streamer
end)

-- Abre o painel local de preferencias do WOW.
exports('openSettings', function()
  local caller = GetInvokingResource()
  if type(caller) ~= 'string' or WOW_Config.TrustedClientResources[caller] ~= true then return false end
  return open_settings()
end)


-- ============================================================
-- COMANDOS / CALLBACKS
-- ============================================================

RegisterCommand('wow', function()
  if STATE.settings_open then close_settings() else open_settings() end
end, false)

RegisterCommand('streamermode', function()
  set_streamer(not STATE.streamer, true)
  TriggerEvent('vHub:notify', 'sucesso', STATE.streamer
    and 'Modo streamer ativado: audio do WOW silenciado.'
    or 'Modo streamer desativado.')
end, false)

RegisterNUICallback('settingsSetStreamer', function(data, cb)
  local active = type(data) == 'table' and data.active
  local ok = set_streamer(active, true)
  cb({ ok = ok, data = snapshot(), err = ok and nil or 'invalid_active' })
end)

RegisterNUICallback('settingsClose', function(_, cb)
  close_settings()
  cb({ ok = true })
end)


-- ============================================================
-- LIFECYCLE
-- ============================================================

AddEventHandler('onClientResourceStart', function(resource)
  if resource == GetCurrentResourceName() then
    send('wow:audio:master', snapshot())
  elseif resource == 'vhub_voicePMA' and STATE.sound_count > 0 then
    pcall(function() exports.vhub_voicePMA:setDuckingDemand(true) end)
  end
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  pcall(function() exports.vhub_voicePMA:setDuckingDemand(false) end)
  SetNuiFocus(false, false)
end)
