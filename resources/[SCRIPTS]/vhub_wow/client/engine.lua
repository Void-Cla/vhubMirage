---@diagnostic disable: undefined-global, lowercase-global

-- client/engine.lua — estado dos sons ativos + motor de posicao (1 thread, zero idle)

local sounds = {}       -- [soundName] = { url, volume, distance, loop, netId, playing }
local soundCount = 0
local engineRunning = false


-- ============================================================
-- MOTOR — nasce no 1o som, morre no ultimo (L-06: zero custo idle)
-- ============================================================

-- resolve posicao 3D de um som ancorado a entidade e atualiza a NUI.
-- (coord estatica nao precisa de tick — e enviada 1x no play e nao muda)
local function pushPosition(name, data)
  if not data.netId then return end

  local ent = NetworkGetEntityFromNetworkId(data.netId)
  if ent == 0 or not DoesEntityExist(ent) then
    SendNUIMessage({ type = 'destroy', name = name })
    sounds[name] = nil
    soundCount = soundCount - 1
    return
  end

  local pos = GetEntityCoords(ent)
  SendNUIMessage({ type = 'position', name = name, x = pos.x, y = pos.y, z = pos.z })
end

local function startEngine()
  if engineRunning then return end
  engineRunning = true

  CreateThread(function()
    while soundCount > 0 do
      local anyDynamic = false

      for name, data in pairs(sounds) do
        if data.netId then
          pushPosition(name, data)
          anyDynamic = true
        end
      end

      Wait(anyDynamic and 150 or 1000)
    end

    engineRunning = false
  end)
end


-- ============================================================
-- HANDLERS — recebem do server, aplicam na NUI, mantem soundInfo local
-- ============================================================

RegisterNetEvent('vhub_wow:play', function(name, url, volume, loop)
  if sounds[name] == nil then soundCount = soundCount + 1 end
  sounds[name] = { url = url, volume = volume, loop = loop, playing = true }

  SendNUIMessage({ type = 'play', name = name, url = url, volume = volume, loop = loop })
end)

RegisterNetEvent('vhub_wow:playAtEntity', function(name, url, volume, netId, distance, loop)
  if sounds[name] == nil then soundCount = soundCount + 1 end
  sounds[name] = { url = url, volume = volume, distance = distance, loop = loop, netId = netId, playing = true }

  SendNUIMessage({
    type = 'play', name = name, url = url, volume = volume, loop = loop,
    dynamic = true, distance = distance,
  })

  startEngine()
end)

RegisterNetEvent('vhub_wow:playAt', function(name, url, volume, coords, distance, loop)
  if sounds[name] == nil then soundCount = soundCount + 1 end
  sounds[name] = { url = url, volume = volume, distance = distance, loop = loop, playing = true }

  -- coord fixa: manda a posicao 1x (nao entra no tick — nao muda)
  SendNUIMessage({
    type = 'play', name = name, url = url, volume = volume, loop = loop,
    dynamic = true, distance = distance,
  })
  SendNUIMessage({ type = 'position', name = name, x = coords.x, y = coords.y, z = coords.z })
end)

RegisterNetEvent('vhub_wow:destroy', function(name)
  if sounds[name] ~= nil then
    sounds[name] = nil
    soundCount = soundCount - 1
  end

  SendNUIMessage({ type = 'destroy', name = name })
end)


-- ============================================================
-- VIDEO — visibilidade da telinha (server propoe, client confirma a bordo — R1)
-- ============================================================

-- torna a telinha visivel SO se o ped local esta de fato dentro do veiculo alegado.
-- o server manda o attach; a decisao final e local (anti "ver DVD do carro alheio").
RegisterNetEvent('vhub_wow:videoAttach', function(name, netId)
  if sounds[name] == nil then return end   -- so exibe video de som que existe aqui

  local ent = NetworkGetEntityFromNetworkId(netId)
  if ent == 0 or not DoesEntityExist(ent) then return end

  local ped = PlayerPedId()
  if not IsPedInVehicle(ped, ent, false) then return end   -- confirmacao fisica local

  SendNUIMessage({ type = 'video.attach', name = name, mode = 'incar' })
end)

RegisterNetEvent('vhub_wow:videoDetach', function(name)
  SendNUIMessage({ type = 'video.detach', name = name })
end)

RegisterNetEvent('vhub_wow:pause', function(name)
  local data = sounds[name]
  if not data then return end
  data.playing = false

  SendNUIMessage({ type = 'pause', name = name })
end)

RegisterNetEvent('vhub_wow:resume', function(name)
  local data = sounds[name]
  if not data then return end
  data.playing = true

  SendNUIMessage({ type = 'resume', name = name })
end)

RegisterNetEvent('vhub_wow:setVolume', function(name, volume)
  local data = sounds[name]
  if not data then return end
  data.volume = volume

  SendNUIMessage({ type = 'volume', name = name, volume = volume })
end)

RegisterNetEvent('vhub_wow:setDistance', function(name, distance)
  local data = sounds[name]
  if not data then return end
  data.distance = distance

  SendNUIMessage({ type = 'distance', name = name, distance = distance })
end)


-- ============================================================
-- QUERIES (read-only) — exports locais para o consumidor consultar estado
-- ============================================================

-- verifica se um som existe na VRAM local do client
exports('soundExists', function(name)
  return sounds[name] ~= nil
end)

-- verifica se um som esta tocando
exports('isPlaying', function(name)
  return sounds[name] ~= nil and sounds[name].playing == true
end)

-- retorna copia somente-leitura do estado local do som (ou nil)
exports('getInfo', function(name)
  local data = sounds[name]
  if not data then return nil end

  return {
    url = data.url, volume = data.volume, distance = data.distance,
    loop = data.loop, playing = data.playing,
  }
end)
