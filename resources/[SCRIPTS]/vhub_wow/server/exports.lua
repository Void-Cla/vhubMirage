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
-- VIDEO — surface de video (embed YouTube nocookie). Existencia (Play*) e separada
-- de VISIBILIDADE (Attach/Detach). O audio ja toca; o video e opt-in por chamada.
-- Todos gated (callAllowed) + isPlayableUrl. Export-first: PlayVideoAt/StopVideoAt
-- ja prontos para a "TV da cidade" futura (sem consumidor hoje — decisao #35).
-- ============================================================

-- toca audio+video 3D ancorado a uma entidade (netId). O iframe fica pronto p/ attach
-- visivel (AttachInCarVideo); por padrao toca so o audio (telinha oculta ate o attach).
local function PlayVideoAtEntity(targets, soundName, url, volume, netId, distance, loop)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end
  if not WOW_Config.parseYouTubeId(url) then return false end   -- video = so YouTube
  if type(netId) ~= 'number' then return false end

  local dist = tonumber(distance) or WOW_Config.DefaultDistance
  if dist > WOW_Config.MaxDistance then dist = WOW_Config.MaxDistance end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:playAtEntity', src, soundName, url, tonumber(volume) or 0.5, netId, dist, loop == true)
  end
  return true
end

exports('PlayVideoAtEntity', PlayVideoAtEntity)

-- toca audio+video 3D numa coordenada fixa (base p/ "TV da cidade" — outdoor/palco/boteco).
-- export-first: sem consumidor hoje; a superficie ja existe pra fase futura.
local function PlayVideoAt(targets, soundName, url, volume, coords, distance, loop)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end
  if not WOW_Config.parseYouTubeId(url) then return false end
  if type(coords) ~= 'table' or type(coords.x) ~= 'number'
     or type(coords.y) ~= 'number' or type(coords.z) ~= 'number' then return false end

  local dist = tonumber(distance) or WOW_Config.DefaultDistance
  if dist > WOW_Config.MaxDistance then dist = WOW_Config.MaxDistance end

  for _, src in ipairs(targets or {}) do
    TriggerClientEvent('vhub_wow:playAt', src, soundName, url, tonumber(volume) or 0.5,
      { x = coords.x, y = coords.y, z = coords.z }, dist, loop == true)
  end
  return true
end

exports('PlayVideoAt', PlayVideoAt)

-- para audio+video de uma surface (alias semantico de Destroy p/ contrato de video limpo)
local function StopVideoAt(targets, soundName)
  return Destroy(targets, soundName)
end

exports('StopVideoAt', StopVideoAt)

-- torna a telinha de video VISIVEL para 'target' se ele confirmar (client) estar a bordo
-- de 'netId'. Server propoe; o client valida com IsPedInVehicle antes de exibir (R1).
local function AttachInCarVideo(target, soundName, netId)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end
  if type(netId) ~= 'number' then return false end

  target = tonumber(target)
  if not target then return false end

  TriggerClientEvent('vhub_wow:videoAttach', target, soundName, netId)
  return true
end

exports('AttachInCarVideo', AttachInCarVideo)

-- esconde a telinha de video (o audio segue tocando)
local function DetachInCarVideo(target, soundName)
  if not callAllowed() then return false end
  if not WOW_Config.isValidSoundName(soundName) then return false end

  target = tonumber(target)
  if not target then return false end

  TriggerClientEvent('vhub_wow:videoDetach', target, soundName)
  return true
end

exports('DetachInCarVideo', DetachInCarVideo)


-- ============================================================
-- MUSICA — busca (YouTube: InnerTube + APIv3 fallback) e radio (playlist curada).
-- Sem rate-limit por resource aqui: o cache do music_search.lua + o rate-limit por
-- PLAYER no consumidor ja controlam o egress. So o gate trusted (default-deny).
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
