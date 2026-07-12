---@diagnostic disable: undefined-global, lowercase-global

-- client/engine.lua — estado dos sons + motor de ATENUACAO 3D (1 thread, zero idle).
--
-- O audio fica PRESO A FONTE (netId do veiculo, ou coord fixa): alto perto, some ao
-- afastar. O YouTube/SoundCloud nao expoem audio p/ Web Audio (CORS), entao a atenuacao
-- e SIMULADA ajustando o volume do player por degraus de distancia (tecnica principallafy).
-- O volume final = baseVolume (escolha do usuario) x fator de distancia (0..1).

local sounds = {}       -- [name] = { url, baseVolume, distance, loop, netId|coords, playing, lastSent }
local soundCount = 0
local engineRunning = false


-- ============================================================
-- ATENUACAO — mapeia distancia -> fator de volume (0..1)
-- ============================================================

local NEAR_RADIUS = 4.0   -- ate aqui: volume cheio (cabine do carro)

-- fator de volume por distancia: 1.0 ate NEAR_RADIUS, decai linear ate 0.0 no raio maximo
local function distanceFactor(dist, maxDist)
  if dist <= NEAR_RADIUS then return 1.0 end
  if dist >= maxDist then return 0.0 end
  return 1.0 - ((dist - NEAR_RADIUS) / (maxDist - NEAR_RADIUS))
end

-- coord da fonte de um som (entidade viva -> coords; coord fixa -> ela mesma; senao nil)
local function sourceCoords(data)
  if data.netId then
    local ent = NetworkGetEntityFromNetworkId(data.netId)
    if ent == 0 or not DoesEntityExist(ent) then return nil, true end   -- 2o retorno = morreu
    return GetEntityCoords(ent), false
  end
  if data.coords then return data.coords, false end
  return nil, false
end


-- ============================================================
-- MOTOR — nasce no 1o som posicional, morre no ultimo (L-06: zero custo idle)
-- ============================================================

local function startEngine()
  if engineRunning then return end
  engineRunning = true

  CreateThread(function()
    while soundCount > 0 do
      local anyPositional = false
      local listenerPos = GetEntityCoords(PlayerPedId())

      -- coleta mortos em lista separada: nao mutar sounds[] dentro de pairs()
      local toDestroy = {}

      for name, data in pairs(sounds) do
        if data.netId or data.coords then
          if not data.playing then
            -- pausado: nao recalcula volume (evita SendNUIMessage desperdicado)
            anyPositional = true
          else
            local src, dead = sourceCoords(data)

            if dead then
              toDestroy[#toDestroy + 1] = name
            elseif src then
              anyPositional = true
              local dist = #(listenerPos - src)
              local factor = distanceFactor(dist, data.distance or 30.0)
              local vol = data.baseVolume * factor

              if not data.lastSent or math.abs(vol - data.lastSent) > 0.02 then
                data.lastSent = vol
                SendNUIMessage({ type = 'volume', name = name, volume = vol })
              end
            end
          end
        end
      end

      -- aplica destruicoes fora do pairs() (safe)
      for _, name in ipairs(toDestroy) do
        if sounds[name] ~= nil then   -- guard: destroy pode ter chegado entre coleta e aqui
          sounds[name] = nil
          soundCount = soundCount - 1
          SendNUIMessage({ type = 'destroy', name = name })
        end
      end

      Wait(anyPositional and 150 or 1000)
    end

    engineRunning = false
    -- guard: novo som chegou enquanto o ultimo Wait ainda rodava (race condition)
    if soundCount > 0 then startEngine() end
  end)
end


-- ============================================================
-- HANDLERS — recebem do server, aplicam na NUI, mantem estado local
-- ============================================================

-- som 2D (sem posicao): toca no volume base fixo, segue o jogador
RegisterNetEvent('vhub_wow:play', function(name, url, volume, loop)
  if sounds[name] == nil then soundCount = soundCount + 1 end
  sounds[name] = { url = url, baseVolume = volume or 0.5, loop = loop, playing = true }

  SendNUIMessage({ type = 'play', name = name, url = url, volume = volume, loop = loop })
end)

-- som 3D preso a uma ENTIDADE (netId do veiculo): atenua por distancia no tick
RegisterNetEvent('vhub_wow:playAtEntity', function(name, url, volume, netId, distance, loop)
  if sounds[name] == nil then soundCount = soundCount + 1 end
  sounds[name] = {
    url = url, baseVolume = volume or 0.5, distance = distance,
    loop = loop, netId = netId, playing = true, lastSent = nil,
  }

  -- comeca no volume base; o tick ajusta pela distancia ja no proximo ciclo
  SendNUIMessage({ type = 'play', name = name, url = url, volume = volume, loop = loop })
  startEngine()
end)

-- som 3D preso a uma COORD fixa (base p/ "TV da cidade"): atenua por distancia no tick
RegisterNetEvent('vhub_wow:playAt', function(name, url, volume, coords, distance, loop)
  if sounds[name] == nil then soundCount = soundCount + 1 end
  sounds[name] = {
    url = url, baseVolume = volume or 0.5, distance = distance,
    loop = loop, coords = vector3(coords.x, coords.y, coords.z), playing = true, lastSent = nil,
  }

  SendNUIMessage({ type = 'play', name = name, url = url, volume = volume, loop = loop })
  startEngine()
end)

RegisterNetEvent('vhub_wow:destroy', function(name)
  if sounds[name] ~= nil then
    sounds[name] = nil
    soundCount = soundCount - 1
  end

  SendNUIMessage({ type = 'destroy', name = name })
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

-- ajuste do volume BASE (slider do usuario). O tick reaplica com a atenuacao por cima.
RegisterNetEvent('vhub_wow:setVolume', function(name, volume)
  local data = sounds[name]
  if not data then return end
  data.baseVolume = volume or 0.5
  data.lastSent = nil   -- forca o proximo tick a reenviar com o novo base

  -- som 2D nao entra no tick: aplica direto
  if not (data.netId or data.coords) then
    SendNUIMessage({ type = 'volume', name = name, volume = data.baseVolume })
  end
end)

RegisterNetEvent('vhub_wow:setDistance', function(name, distance)
  local data = sounds[name]
  if not data then return end
  data.distance = distance
  data.lastSent = nil
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
    url = data.url, volume = data.baseVolume, distance = data.distance,
    loop = data.loop, playing = data.playing,
  }
end)
