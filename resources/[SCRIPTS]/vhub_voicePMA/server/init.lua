-- server/init.lua — bordas de rede e lifecycle do motor de voz

local E = VHubVoicePMA.E
local S = VHubVoicePMA.Server


-- ============================================================
-- INTENCOES DO CLIENTE
-- ============================================================

RegisterNetEvent(E.SYNC_REQUEST, function()
  S.sync(source)
end)

RegisterNetEvent(E.MODE_REQUEST, function(mode)
  S.setMode(source, mode)
end)

RegisterNetEvent(E.PROXIMITY_TALK_REQUEST, function(talking)
  S.setProximityTalking(source, talking)
end)

RegisterNetEvent(E.RADIO_REQUEST, function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local ok, reason = S.setRadio(src, payload.channel)
  if not ok then
    TriggerClientEvent(E.NOTIFY, src, 'erro', reason == 'canal_cheio'
      and 'A frequencia esta cheia.' or 'Nao foi possivel acessar esta frequencia.')
  end
end)

RegisterNetEvent(E.RADIO_TALK_REQUEST, function(talking)
  S.setRadioTalking(source, talking)
end)

RegisterNetEvent(E.CALL_TALK_REQUEST, function(talking)
  S.setCallTalking(source, talking)
end)


-- ============================================================
-- LIFECYCLE
-- ============================================================

AddEventHandler(E.CHARACTER_LOAD, function(user)
  S.characterLoad(user)
end)

AddEventHandler('playerDropped', function()
  S.drop(source)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  S.shutdown()
end)
