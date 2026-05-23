-- server/init.lua - bootstrap e fronteiras de rede do vhub_racha.

local Core, SQL, E = VHubRachaCore, VHubRachaSQL, VHubRachaE

local function respond(src, ok, data_or_err)
  TriggerClientEvent(E.NUI_RESULT, src, ok and { ok = true, data = data_or_err } or { ok = false, err = data_or_err })
end

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    local vh = nil
    for _ = 1, 60 do
      local ok, ref = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(ref) == 'table' and ref.Auth then vh = ref; break end
      Citizen.Wait(250)
    end
    if not vh then print('[vhub_racha][ERRO] vhub indisponivel apos 15s - abortando init.'); return end
    Core.set_vhub(vh)
    local ok, err = SQL.apply_schema()
    if not ok then print('[vhub_racha][ERRO] falha ao aplicar schema: ' .. tostring(err)); return end
    Core.mark_ready()
    print('[vhub_racha] Pronto.')
  end)
end)

RegisterNetEvent(E.NUI_OPEN, function(payload)
  Core.open_panel(source, type(payload) == 'table' and payload.track_id or nil)
end)

RegisterNetEvent('vhub_racha:profile:nick', function(payload)
  local src = source
  Citizen.CreateThread(function()
    local ok, data_or_err = Core.set_nickname(src, type(payload) == 'table' and payload.nickname or '')
    respond(src, ok, data_or_err)
    if ok then Core.open_panel(src, type(payload) == 'table' and payload.track_id or nil) end
  end)
end)

RegisterNetEvent(E.CREATE_LOBBY, function(payload)
  local src = source
  Citizen.CreateThread(function() local ok, data_or_err = Core.create_lobby(src, payload); respond(src, ok, data_or_err) end)
end)

RegisterNetEvent(E.JOIN_LOBBY, function(payload)
  local src = source
  Citizen.CreateThread(function() local ok, data_or_err = Core.join_lobby(src, payload); respond(src, ok, data_or_err) end)
end)

RegisterNetEvent(E.START_LOBBY, function(payload)
  local src = source
  Citizen.CreateThread(function() local ok, data_or_err = Core.start_lobby(src, payload); respond(src, ok, data_or_err) end)
end)

RegisterNetEvent(E.LEAVE_LOBBY, function(payload)
  local src = source
  Citizen.CreateThread(function()
    local ok, data_or_err = Core.leave(src, 'left')
    respond(src, ok, data_or_err)
    if ok then Core.open_panel(src, type(payload) == 'table' and payload.track_id or nil) end
  end)
end)

RegisterNetEvent(E.CANCEL_LOBBY, function(payload)
  local src = source
  Citizen.CreateThread(function()
    local ok, data_or_err = Core.cancel_lobby(src, payload)
    respond(src, ok, data_or_err)
    if ok then Core.open_panel(src, type(payload) == 'table' and payload.track_id or nil) end
  end)
end)

RegisterNetEvent(E.RACE_CHECKPOINT, function(payload)
  local src = source
  Citizen.CreateThread(function() Core.checkpoint(src, payload) end)
end)

RegisterNetEvent(E.RACE_ABORT, function(payload)
  local src = source
  Citizen.CreateThread(function()
    local reason = type(payload) == 'table' and payload.reason or 'dnf'
    Core.leave(src, reason == 'timeout' and 'timeout' or 'dnf')
  end)
end)

AddEventHandler('playerDropped', function() Core.drop_src(source) end)

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(5000)
    if Core.is_ready() then Core.tick() end
  end
end)

RegisterCommand('vhub_racha_status', function(src)
  if src ~= 0 then return end
  local st = Core.status()
  print(('[vhub_racha] ready=%s sql=%s lobbies=%d created=%d started=%d finished=%d dnf=%d'):format(
    tostring(st.ready), tostring(st.sql_ready), #(st.lobbies or {}),
    st.metrics.created, st.metrics.started, st.metrics.finished, st.metrics.dnf))
end, true)
