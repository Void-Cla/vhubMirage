---@diagnostic disable: undefined-global, lowercase-global

-- client/sound.lua — ponte rádio de veículo -> vhub_wow (soft-dep, decisão de integração #34)
-- A NUI (html/sound.js) decide play/pause/volume; aqui só repassa pro servidor, que
-- valida e dispara o som 3D ancorado no netId do veículo via exports.vhub_wow.

local playing = false   -- só controla se este client tem som ativo (nome real é derivado no servidor)

local function localSoundName()
  return ('vc_radio_%d'):format(GetPlayerServerId(PlayerId()))
end

-- veiculo atual do player (radio só funciona dentro do carro, sem fallback a pé)
local function drivingVehicle()
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return GetVehiclePedIsIn(ped, false) end
  return 0
end

-- placa normalizada do veiculo (mesmo padrao de plateOf em main.lua)
local function plateOf(v)
  if not v or v == 0 then return nil end
  local p = GetVehicleNumberPlateText(v)
  if not p then return nil end
  p = p:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  return (p and #p >= 1) and p or nil
end


-- ============================================================
-- NUI CALLBACKS — play/stop/volume vindos do aside Som
-- ============================================================

RegisterNUICallback('soundPlay', function(d, cb)
  local v = drivingVehicle()
  local pl = plateOf(v)
  if v == 0 or not pl then
    SendNUIMessage({ type = 'soundRejected', data = {} })
    cb({ ok = false, err = 'vehicle_unavailable' })
    return
  end

  local url = d and d.url
  if type(url) ~= 'string' or url == '' then cb({ ok = false, err = 'invalid_url' }); return end

  local title = (type(d.title) == 'string') and d.title or nil

  playing = true
  TriggerServerEvent(VHubVeh.E.SOUND_PLAY, VehToNet(v), pl, url, tonumber(d.volume) or 0.5, title)
  cb({ ok = true })
end)

RegisterNUICallback('soundStop', function(_, cb)
  if playing then
    TriggerServerEvent(VHubVeh.E.SOUND_STOP)
    playing = false
  end
  cb({ ok = true })
end)

RegisterNUICallback('soundVolume', function(d, cb)
  local ok = playing == true
  if ok then
    TriggerServerEvent(VHubVeh.E.SOUND_VOLUME, tonumber(d and d.volume) or 0.5)
  end
  cb({ ok = ok, err = ok and nil or 'sound_not_active' })
end)

-- busca de musica (YouTube via vhub_wow). So repassa o texto; servidor valida/limita.
RegisterNUICallback('soundSearch', function(d, cb)
  local q = d and d.query
  local ok = type(q) == 'string' and #q >= 1 and #q <= 80
  if ok then
    TriggerServerEvent(VHubVeh.E.SOUND_SEARCH, q)
  end
  cb({ ok = ok, err = ok and nil or 'invalid_query' })
end)

-- liga/desliga a telinha de video "DVD no carro" (checkbox da aba Som)
RegisterNUICallback('soundVideo', function(d, cb)
  local v = drivingVehicle()
  local pl = plateOf(v)
  local ok = v ~= 0 and pl ~= nil
  if ok then
    TriggerServerEvent(VHubVeh.E.SOUND_VIDEO, VehToNet(v), pl, (d and d.show) == true)
  end
  cb({ ok = ok, err = ok and nil or 'vehicle_unavailable' })
end)

-- usuario fechou a telinha pelo X (dentro da NUI) — avisa o server p/ limpar exibicao
RegisterNUICallback('soundVideoOff', function(_, cb)
  TriggerServerEvent(VHubVeh.E.SOUND_VIDEO_OFF)
  cb({ ok = true })
end)

-- radio aleatorio (top-semana): servidor escolhe a faixa e dispara no carro
RegisterNUICallback('soundRadio', function(d, cb)
  local v = drivingVehicle()
  local pl = plateOf(v)
  local ok = v ~= 0 and pl ~= nil
  if ok then
    playing = true
    TriggerServerEvent(VHubVeh.E.SOUND_RADIO, VehToNet(v), pl, tonumber(d and d.volume) or 0.5)
  else
    SendNUIMessage({ type = 'soundRejected', data = {} })
  end
  cb({ ok = ok, err = ok and nil or 'vehicle_unavailable' })
end)

-- ============================================================
-- LIFECYCLE — sai do carro = para o som (evita radio fantasma tocando vazio)
-- ============================================================

RegisterNetEvent(VHubVeh.E.LEFT_VEHICLE, function()
  if playing then
    TriggerServerEvent(VHubVeh.E.SOUND_STOP)
    playing = false
  end
end)

RegisterNetEvent(VHubVeh.E.SOUND_REJECTED, function()
  playing = false
  SendNUIMessage({ type = 'soundRejected', data = {} })
end)

-- resultados da busca chegam direto do vhub_wow → repassa pra NUI montar a lista
RegisterNetEvent(VHubVeh.E.WOW_SEARCH_RESULTS, function(query, items)
  SendNUIMessage({ type = 'soundResults', data = { items = items or {} } })
end)

-- faixa que entrou no ar (radio) → atualiza header da NUI
RegisterNetEvent(VHubVeh.E.SOUND_NOW, function(title, artist)
  SendNUIMessage({ type = 'soundNow', data = { title = title, artist = artist } })
end)

AddEventHandler(VHubVeh.E.WOW_AUDIO_LIFECYCLE, function(name)
  if name ~= localSoundName() or not playing then return end
  playing = false
  TriggerServerEvent(VHubVeh.E.SOUND_STOP)
  SendNUIMessage({ type = 'soundEnded', data = {} })
end)

-- servidor mandou exibir a telinha DVD (videoId validado) → repassa pra NUI montar o iframe
RegisterNetEvent(VHubVeh.E.VIDEO_ATTACH, function(videoId, title)
  SendNUIMessage({ type = 'soundVideoAttach', data = { video_id = videoId, title = title } })
end)

-- servidor mandou esconder a telinha DVD → repassa pra NUI destruir o iframe
RegisterNetEvent(VHubVeh.E.VIDEO_DETACH, function()
  SendNUIMessage({ type = 'soundVideoDetach', data = {} })
end)

RegisterNUICallback('soundStreamerGet', function(_, cb)
  local ok, active = pcall(function() return exports.vhub_wow:getStreamerMode() end)
  cb({ ok = ok, data = { active = ok and active == true }, err = ok and nil or 'wow_unavailable' })
end)

RegisterNUICallback('soundStreamer', function(data, cb)
  local active = type(data) == 'table' and data.active
  if type(active) ~= 'boolean' then
    cb({ ok = false, data = { active = false }, err = 'invalid_active' })
    return
  end

  local ok, accepted = pcall(function() return exports.vhub_wow:setStreamerMode(active) end)
  local read_ok, current = pcall(function() return exports.vhub_wow:getStreamerMode() end)
  local success = ok and accepted == true and read_ok
  cb({
    ok = success,
    data = { active = read_ok and current == true },
    err = success and nil or 'wow_unavailable',
  })
end)
