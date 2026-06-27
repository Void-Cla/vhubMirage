---@diagnostic disable: undefined-global, lowercase-global

-- server/exports.lua — porta canonica do vhub_wow (auth + validacao, repassa pro client)


-- ============================================================
-- AUTH (N0-2: default-deny — sem whitelist configurada, ninguem passa)
-- ============================================================

local _opAt = {}

local function rateLimited(caller)
  local now = GetGameTimer()
  if now - (_opAt[caller] or -1e9) < WOW_Config.RateLimitMs then return true end
  _opAt[caller] = now
  return false
end

-- resource chamador esta na whitelist? retorna o nome (ou nil) — N0-2 default-deny
local function trustedCaller()
  local caller = GetInvokingResource()
  if not caller then return nil end

  for _, name in ipairs(WOW_Config.TrustedResources) do
    if name == caller then return caller end
  end
  return nil
end

-- gate de PLAYBACK: trusted + rate-limit por resource (janela minima entre disparos)
local function callAllowed()
  local caller = trustedCaller()
  if not caller then return false end
  return not rateLimited(caller)
end


-- ============================================================
-- PLAYBACK — toca/destroi som em jogadores especificos (targets)
-- ============================================================

-- toca som 2D (sem posicao) nos targets informados (lista de server ids)
local function Play(targets, soundName, url, volume, loop)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end
  if not WOW_Config.isPlayableUrl(url) then return false end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:play', src, soundName, url, tonumber(volume) or 0.5, loop == true)
  end
  return true
end

exports('Play', Play)

-- toca som 3D ancorado a uma entidade de rede (netId) — client resolve a posicao localmente
local function PlayAtEntity(targets, soundName, url, volume, netId, distance, loop)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end
  if not WOW_Config.isPlayableUrl(url) then return false end
  if type(netId) ~= 'number' then return false end

  local dist = tonumber(distance) or WOW_Config.DefaultDistance
  if dist > WOW_Config.MaxDistance then dist = WOW_Config.MaxDistance end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:playAtEntity', src, soundName, url, tonumber(volume) or 0.5, netId, dist, loop == true)
  end
  return true
end

exports('PlayAtEntity', PlayAtEntity)

-- destroi som ativo nos targets informados
local function Destroy(targets, soundName)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:destroy', src, soundName)
  end
  return true
end

exports('Destroy', Destroy)


-- ============================================================
-- MANIPULATION
-- ============================================================

local function Pause(targets, soundName)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:pause', src, soundName)
  end
  return true
end

exports('Pause', Pause)

local function Resume(targets, soundName)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:resume', src, soundName)
  end
  return true
end

exports('Resume', Resume)

local function SetVolume(targets, soundName, volume)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:setVolume', src, soundName, tonumber(volume) or 0.5)
  end
  return true
end

exports('SetVolume', SetVolume)

local function SetDistance(targets, soundName, distance)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end

  local dist = tonumber(distance) or WOW_Config.DefaultDistance
  if dist > WOW_Config.MaxDistance then dist = WOW_Config.MaxDistance end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:setDistance', src, soundName, dist)
  end
  return true
end

exports('SetDistance', SetDistance)


-- ============================================================
-- MUSICA — busca e radio (provider Jamendo, ver server/music.lua)
-- Sem rate-limit por resource aqui: o cache do music.lua + o rate-limit por
-- PLAYER no consumidor ja controlam o uso da API. So o gate trusted (default-deny).
--
-- NB: NAO passamos callback Lua por export (funcref nao cruza Lua->Lua de forma
-- confiavel). Busca = async via evento de retorno; radio = leitura SINCRONA do cache.
-- ============================================================

-- inicia uma busca para um player; o resultado chega no CLIENT dele pelo evento
-- 'vhub_wow:searchResults' (playerSrc, query, items). Retorna so se foi aceita.
local function RequestSearch(playerSrc, query)
  if not trustedCaller() then return false end

  playerSrc = tonumber(playerSrc)
  if not playerSrc then return false end

  -- callback LOCAL (mesmo resource) → funcref ok aqui dentro do vhub_wow
  WOW_Music.searchTracks(query, function(items)
    TriggerClientEvent('vhub_wow:searchResults', playerSrc, query, items or {})
  end)
  return true
end

exports('RequestSearch', RequestSearch)

-- retorna 1 faixa aleatoria das mais tocadas (SINCRONO, do cache) ou nil se frio
local function GetRadioTrack()
  if not trustedCaller() then return nil end
  return WOW_Music.radioTrackSync()
end

exports('GetRadioTrack', GetRadioTrack)

-- NB: _opAt e indexado por NOME DE RESOURCE (GetInvokingResource), nao por player.
-- Conjunto finito = sem leak; nao precisa de limpeza em playerDropped.
