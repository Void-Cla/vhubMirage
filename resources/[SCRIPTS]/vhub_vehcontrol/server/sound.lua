---@diagnostic disable: undefined-global

-- server/sound.lua — ponte radio de veiculo -> vhub_wow (soft-dep, sem dependencies{})
-- Sem vhub_wow rodando, o radio so nao funciona (resto do vehcontrol intacto).
--
-- SEGURANCA: soundName NUNCA vem do payload do cliente (deriva sempre de src — um
-- player não pode forjar o nome de outro e parar/alterar o som dele). netId só é
-- aceito após hasAccess(src, plate) confirmar que o player tem chave/posse do veiculo
-- com aquela placa (mesmo padrao de requestLock em main.lua).

local function wowAvailable()
  return GetResourceState('vhub_wow') == 'started'
end

local function soundNameOf(src)
  return ('vc_radio_%d'):format(src)
end

local function rejectSound(src)
  TriggerClientEvent('vhub_vehcontrol:soundRejected', src)
end


-- ============================================================
-- ESTADO — url/faixa em reproducao por player (base do "DVD no carro")
-- ============================================================

local _now = {}   -- [src] = { url=, title=, plate= } do som ativo (nil = nada tocando)

-- extrai o videoId de 11 chars de uma URL do YouTube (inclui nocookie/embed) ou nil.
-- espelha WOW_Config.parseYouTubeId (o vehcontrol nao carrega o config do wow).
local function youTubeIdOf(url)
  if type(url) ~= 'string' then return nil end
  local host = url:match('^https://([%w%.%-]+)/')
  if not host then return nil end
  local isYt = host == 'youtu.be'
    or host == 'youtube.com' or host == 'www.youtube.com'
    or host == 'm.youtube.com' or host == 'music.youtube.com'
    or host == 'www.youtube-nocookie.com' or host == 'youtube-nocookie.com'
  if not isYt then return nil end
  local id = url:match('[?&]v=([%w_%-]+)') or url:match('youtu%.be/([%w_%-]+)')
    or url:match('/shorts/([%w_%-]+)') or url:match('/embed/([%w_%-]+)')
  if id and #id >= 11 then return id:sub(1, 11) end
  return nil
end

-- desliga a telinha de video do player (o audio segue tocando no wow)
local function detachVideo(src)
  TriggerClientEvent(VHubVeh.E.VIDEO_DETACH, src)
end


RegisterNetEvent('vhub_vehcontrol:soundPlay', function(netId, plate, url, volume, title)
  local src = source
  if not wowAvailable() then rejectSound(src); return end
  if type(netId) ~= 'number' or type(plate) ~= 'string' or type(url) ~= 'string' then rejectSound(src); return end
  if not VHubVeh.hasVehicleAccess(src, plate) then rejectSound(src); return end

  -- title e cosmetico (rotulo da telinha): sanea tamanho, aceita nil
  local tt = (type(title) == 'string' and #title <= 120) and title or nil

  local ok, accepted = pcall(function()
    return exports.vhub_wow:PlayAtEntity({ src }, soundNameOf(src), url, volume, netId, 10.0, true)
  end)
  if ok and accepted == true then
    _now[src] = { url = url, title = tt, plate = plate }
  else
    rejectSound(src)
  end
end)

RegisterNetEvent('vhub_vehcontrol:soundStop', function()
  local src = source
  _now[src] = nil
  detachVideo(src)                       -- sem som = sem telinha
  if not wowAvailable() then return end

  pcall(function()
    exports.vhub_wow:Destroy({ src }, soundNameOf(src))
  end)
end)

RegisterNetEvent('vhub_vehcontrol:soundVolume', function(volume)
  local src = source
  if not wowAvailable() then return end

  pcall(function()
    exports.vhub_wow:SetVolume({ src }, soundNameOf(src), volume)
  end)
end)

-- liga/desliga a telinha de video "DVD no carro" (so YouTube). Server valida acesso ao
-- veiculo e so exibe se houver um som YouTube tocando; a telinha (video) e do vehcontrol.
RegisterNetEvent('vhub_vehcontrol:soundVideo', function(netId, plate, show)
  local src = source
  if type(netId) ~= 'number' or type(plate) ~= 'string' then return end
  if not VHubVeh.hasVehicleAccess(src, plate) then return end

  if show ~= true then detachVideo(src); return end

  -- so ha video se o som ativo do player for do YouTube
  local now = _now[src]
  local vid = now and youTubeIdOf(now.url)
  if not vid then detachVideo(src); return end

  TriggerClientEvent(VHubVeh.E.VIDEO_ATTACH, src, vid, now.title)
end)

-- usuario fechou a telinha pelo X (client) — limpa qualquer estado de exibicao
RegisterNetEvent('vhub_vehcontrol:soundVideoOff', function()
  detachVideo(source)
end)


-- ============================================================
-- BUSCA / RADIO — delega ao provider de musica do vhub_wow
-- ============================================================

local _searchAt = {}           -- [src] = ultimo ms de busca (rate-limit por player)
local SEARCH_COOLDOWN = 1500    -- 1 busca por jogador a cada 1.5s

-- busca: rate-limit por player + valida tamanho; resultado volta so pra quem pediu
RegisterNetEvent('vhub_vehcontrol:soundSearch', function(query)
  local src = source
  if not wowAvailable() then return end
  if type(query) ~= 'string' or #query < 1 or #query > 80 then return end

  local now = GetGameTimer()
  if now - (_searchAt[src] or -1e9) < SEARCH_COOLDOWN then return end
  _searchAt[src] = now

  -- resultado chega no client do player via evento vhub_wow:searchResults (sem callback cross-resource)
  pcall(function() exports.vhub_wow:RequestSearch(src, query) end)
end)

-- radio: exige acesso ao veiculo (mesmo gate do play); servidor escolhe a faixa
RegisterNetEvent('vhub_vehcontrol:soundRadio', function(netId, plate, volume)
  local src = source
  if not wowAvailable() then rejectSound(src); return end
  if type(netId) ~= 'number' or type(plate) ~= 'string' then rejectSound(src); return end
  if not VHubVeh.hasVehicleAccess(src, plate) then rejectSound(src); return end

  local vol = tonumber(volume) or 0.5
  if vol < 0 then vol = 0 elseif vol > 1 then vol = 1 end

  -- GetRadioTrack e SINCRONO (le do cache do vhub_wow). nil = cache ainda frio → tenta de novo.
  local ok, track = pcall(function() return exports.vhub_wow:GetRadioTrack() end)
  if not ok or type(track) ~= 'table' or not track.url then rejectSound(src); return end

  -- fronteira externa em pcall (R7): vhub_wow pode reiniciar entre wowAvailable() e aqui
  local okp, accepted = pcall(function()
    return exports.vhub_wow:PlayAtEntity({ src }, soundNameOf(src), track.url, vol, netId, 10.0, true)
  end)
  if okp and accepted == true then
    _now[src] = { url = track.url, title = track.title, plate = plate }
    TriggerClientEvent('vhub_vehcontrol:soundNow', src, track.title, track.artist)
  else
    rejectSound(src)
  end
end)

AddEventHandler('playerDropped', function()
  local src = source
  _searchAt[src] = nil
  _now[src] = nil
end)
