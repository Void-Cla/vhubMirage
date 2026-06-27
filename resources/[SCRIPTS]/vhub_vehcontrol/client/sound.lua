---@diagnostic disable: undefined-global, lowercase-global

-- client/sound.lua — ponte rádio de veículo -> vhub_wow (soft-dep, decisão de integração #34)
-- A NUI (html/sound.js) decide play/pause/volume; aqui só repassa pro servidor, que
-- valida e dispara o som 3D ancorado no netId do veículo via exports.vhub_wow.

local playing = false   -- só controla se este client tem som ativo (nome real é derivado no servidor)

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
  if v == 0 or not pl then SendNUIMessage({ type = 'soundRejected' }); cb('ok'); return end

  local url = d and d.url
  if type(url) ~= 'string' or url == '' then cb('ok'); return end

  playing = true
  TriggerServerEvent('vhub_vehcontrol:soundPlay', VehToNet(v), pl, url, tonumber(d.volume) or 0.5)
  cb('ok')
end)

RegisterNUICallback('soundStop', function(_, cb)
  if playing then
    TriggerServerEvent('vhub_vehcontrol:soundStop')
    playing = false
  end
  cb('ok')
end)

RegisterNUICallback('soundVolume', function(d, cb)
  if playing then
    TriggerServerEvent('vhub_vehcontrol:soundVolume', tonumber(d and d.volume) or 0.5)
  end
  cb('ok')
end)

-- busca de musica (Jamendo via vhub_wow). So repassa o texto; servidor valida/limita.
RegisterNUICallback('soundSearch', function(d, cb)
  local q = d and d.query
  if type(q) == 'string' and #q >= 1 then
    TriggerServerEvent('vhub_vehcontrol:soundSearch', q)
  end
  cb('ok')
end)

-- radio aleatorio (top-semana): servidor escolhe a faixa e dispara no carro
RegisterNUICallback('soundRadio', function(d, cb)
  local v = drivingVehicle()
  local pl = plateOf(v)
  if v ~= 0 and pl then
    playing = true
    TriggerServerEvent('vhub_vehcontrol:soundRadio', VehToNet(v), pl, tonumber(d and d.volume) or 0.5)
  else
    SendNUIMessage({ type = 'soundRejected' })
  end
  cb('ok')
end)

-- ============================================================
-- LIFECYCLE — sai do carro = para o som (evita radio fantasma tocando vazio)
-- ============================================================

RegisterNetEvent(VHubVeh.E.LEFT_VEHICLE, function()
  if playing then
    TriggerServerEvent('vhub_vehcontrol:soundStop')
    playing = false
  end
end)

RegisterNetEvent('vhub_vehcontrol:soundRejected', function()
  playing = false
  SendNUIMessage({ type = 'soundRejected' })
end)

-- resultados da busca chegam direto do vhub_wow → repassa pra NUI montar a lista
RegisterNetEvent('vhub_wow:searchResults', function(query, items)
  SendNUIMessage({ type = 'soundResults', items = items or {} })
end)

-- faixa que entrou no ar (radio) → atualiza header da NUI
RegisterNetEvent('vhub_vehcontrol:soundNow', function(title, artist)
  SendNUIMessage({ type = 'soundNow', title = title, artist = artist })
end)
