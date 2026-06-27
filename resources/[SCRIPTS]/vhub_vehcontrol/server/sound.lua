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


RegisterNetEvent('vhub_vehcontrol:soundPlay', function(netId, plate, url, volume)
  local src = source
  if not wowAvailable() then rejectSound(src); return end
  if type(netId) ~= 'number' or type(plate) ~= 'string' or type(url) ~= 'string' then rejectSound(src); return end
  if not VHubVeh.hasVehicleAccess(src, plate) then rejectSound(src); return end

  local ok, accepted = pcall(function()
    return exports.vhub_wow:PlayAtEntity({ src }, soundNameOf(src), url, volume, netId, 10.0, true)
  end)
  if not ok or accepted ~= true then rejectSound(src) end
end)

RegisterNetEvent('vhub_vehcontrol:soundStop', function()
  local src = source
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

  local okp = exports.vhub_wow:PlayAtEntity({ src }, soundNameOf(src), track.url, vol, netId, 10.0, true)
  if okp == true then
    TriggerClientEvent('vhub_vehcontrol:soundNow', src, track.title, track.artist)
  else
    rejectSound(src)
  end
end)

AddEventHandler('playerDropped', function()
  local src = source
  _searchAt[src] = nil
end)
