-- client/ducking.lua — atividade normalizada sob demanda para o vhub_wow

local Cfg = VHubVoicePMA.Cfg
local C = VHubVoicePMA.Client

local demanded = false
local monitorRunning = false
local lastActivity = -1.0
local proximityTalkers = {}
local talkHandler = nil


-- ============================================================
-- CALCULO
-- ============================================================

local function remote_mode(server_id)
  local ok, value = pcall(function() return Player(server_id).state.vhub_voice_mode end)
  local mode = ok and tonumber(value) or Cfg.DEFAULT_MODE
  return Cfg.MODES[mode] or Cfg.MODES[Cfg.DEFAULT_MODE]
end

local function spatial_activity()
  local local_ped = PlayerPedId()
  if not DoesEntityExist(local_ped) then return 0.0 end
  local local_coords = GetEntityCoords(local_ped)
  local strength = 0.0

  for server_id in pairs(proximityTalkers) do
    local player = GetPlayerFromServerId(server_id)
    if player == -1 then
      proximityTalkers[server_id] = nil
    elseif not C.radioTalkers[server_id] and not C.callTalkers[server_id] then
      local ped = GetPlayerPed(player)
      if DoesEntityExist(ped) then
        local spec = remote_mode(server_id)
        local distance = #(local_coords - GetEntityCoords(ped))
        if distance < spec.distance then
          local value = spec.duck * (1.0 - (distance / spec.distance))
          if value > strength then strength = value end
        end
      end
    end
  end
  return strength
end

local function activity()
  if C.localTalking then return 1.0 end
  local strength = spatial_activity()

  for server_id in pairs(C.radioTalkers) do
    if server_id ~= GetPlayerServerId(PlayerId()) then
      local value = Cfg.RADIO_DUCK * C.radioVolume
      if value > strength then strength = value end
    end
  end

  for server_id in pairs(C.callTalkers) do
    if server_id ~= GetPlayerServerId(PlayerId()) then
      local value = Cfg.CALL_DUCK * C.callVolume
      if value > strength then strength = value end
    end
  end
  return math.max(0.0, math.min(1.0, strength))
end

local function seed_talkers()
  local self_id = GetPlayerServerId(PlayerId())
  for _, player in ipairs(GetActivePlayers()) do
    local server_id = GetPlayerServerId(player)
    if server_id ~= self_id then
      local ok, value = pcall(function() return Player(server_id).state.vhub_voice_talking end)
      if ok and value == true then proximityTalkers[server_id] = true end
    end
  end
end

local function publish(value)
  local ok, accepted = pcall(function() return exports.vhub_wow:setVoiceActivity(value) end)
  if ok and accepted == true then lastActivity = value end
end


-- ============================================================
-- DEMANDA
-- ============================================================

local function start_monitor()
  if monitorRunning then return end
  monitorRunning = true

  CreateThread(function()
    while C.running and demanded do
      local value = activity()
      if lastActivity < 0.0 or math.abs(value - lastActivity) >= Cfg.CLIENT.DUCK_DELTA
          or (value == 0.0) ~= (lastActivity == 0.0) then
        publish(value)
      end
      Wait(Cfg.CLIENT.DUCK_INTERVAL_MS)
    end
    if lastActivity ~= 0.0 then publish(0.0) end
    monitorRunning = false
  end)
end

-- Liga ou desliga o monitor somente quando o WOW possui som ativo.
exports('setDuckingDemand', function(active)
  if GetInvokingResource() ~= 'vhub_wow' or type(active) ~= 'boolean' then return false end
  demanded = active
  if active then
    seed_talkers()
    start_monitor()
  elseif lastActivity ~= 0.0 then
    publish(0.0)
  end
  return true
end)

talkHandler = AddStateBagChangeHandler('vhub_voice_talking', nil, function(bag_name, _, value)
  local server_id = tonumber(type(bag_name) == 'string' and bag_name:match('^player:(%d+)$'))
  if not server_id or server_id == GetPlayerServerId(PlayerId()) then return end
  proximityTalkers[server_id] = value == true and true or nil
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  demanded = false
  if talkHandler then RemoveStateBagChangeHandler(talkHandler); talkHandler = nil end
  proximityTalkers = {}
  if lastActivity ~= 0.0 then publish(0.0) end
end)
