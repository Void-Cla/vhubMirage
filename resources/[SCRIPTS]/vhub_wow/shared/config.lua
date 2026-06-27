---@diagnostic disable: undefined-global, lowercase-global

-- shared/config.lua — config do motor de audio (carregado client + server).

WOW_Config = {}

-- resources autorizados a chamar os exports server-side (fail-closed: vazio = ninguem passa)
WOW_Config.TrustedResources = {
  'vhub_vehcontrol',
}

-- dominios permitidos para URL de audio (host ancorado — nao usar match por substring).
-- So entram hosts que entregam ARQUIVO DE AUDIO DIRETO (tocavel no <audio> HTML5).
-- Pagina de YouTube/Spotify NAO entra: nao devolve stream tocavel sem extrator/SDK.
WOW_Config.AllowedDomains = {
  -- Discord CDN (anexos diretos)
  'cdn%.discordapp%.com',
  'media%.discordapp%.net',

  -- Jamendo (provider de musica padrao — stream .mp3 direto; ver server/music.lua)
  'prod%-%d+%.storage%.jamendo%.com',
  '[%w%-]+%.storage%.jamendo%.com',
  '[%w%-]+%.jamendo%.com',

  -- SoundCloud: so a CDN direta (permalink soundcloud.com NAO e stream)
  '[%w%-]+%.sndcdn%.com',

  -- Hosts diretos reputados (servem arquivo tocavel no <audio>)
  'raw%.githubusercontent%.com',
  '[%w%-]+%.github%.io',
  'archive%.org',
  '[%w%-]+%.archive%.org',
  'dl%.dropboxusercontent%.com',
  'files%.catbox%.moe',

  -- Teste
  'soundhelix%.com',
  'www%.soundhelix%.com',
}

-- slots para integracoes externas.
-- CRITICO: este arquivo e shared (client + server). Nao coloque segredo real aqui.
-- Para chave privada/token secreto, usar convar server-only no server.cfg.
WOW_Config.ApiKeys = {
  youtube = {
    api_key = '',
  },
  spotify = {
    api_key = '',
    client_id = '',
  },
  soundcloud = {
    api_key = '',
    client_id = '',
  },
}

-- ordem de tentativa de busca de musica. Jamendo e o padrao; os slots acima
-- (youtube/spotify/soundcloud) ficam INERTES ate existir camada de extrator/SDK
-- (decisao "So Jamendo + links diretos"). Nao adicionar provider sem implementacao.
WOW_Config.Providers = { 'jamendo' }

-- Jamendo API v3.0 (somente leitura). client_id NAO fica aqui (arquivo e shared
-- client+server). E lido de convar server-only em server/music.lua:
--   set wow_jamendo_id "SEU_CLIENT_ID"
WOW_Config.Jamendo = {
  enabled       = true,
  base          = 'https://api.jamendo.com/v3.0/',
  audioformat   = 'mp32',     -- mp3 VBR — toca direto no <audio>
  searchLimit   = 20,         -- resultados por busca
  radioLimit    = 50,         -- tamanho da playlist semanal em cache
  searchCacheMs = 300000,     -- 5 min: mesma busca nao repete HTTP (controla chamadas)
  radioCacheMs  = 1800000,    -- 30 min: playlist top-semana refrescada lazy (L-06)
}

WOW_Config.MaxDistance     = 80.0   -- distancia maxima de audicao (metros)
WOW_Config.DefaultDistance = 10.0   -- distancia padrao quando nao informada
WOW_Config.RateLimitMs     = 350    -- janela minima entre chamadas por resource (padrao _opAt do projeto)

-- valida nome do som: alfanumerico/underscore/hifen, max 64 chars (anti-injection)
function WOW_Config.isValidSoundName(name)
  return type(name) == 'string' and #name > 0 and #name <= 64 and name:match('^[%w_%-]+$') ~= nil
end

-- valida URL contra a allowlist de dominio (host completo ancorado, nao substring)
function WOW_Config.isValidUrl(url)
  if type(url) ~= 'string' or #url == 0 or #url > 512 then return false end
  local host = url:match('^https://([%w%.%-]+)/')
  if not host then return false end

  for _, domain in ipairs(WOW_Config.AllowedDomains) do
    if host:match('^' .. domain .. '$') then return true end
  end

  return false
end

-- valida texto de busca de musica: 1..80 chars, sem caracteres de controle
-- (a query e URL-encoded antes de ir pra API; isto barra controle/injecao)
function WOW_Config.isValidSearchQuery(q)
  if type(q) ~= 'string' then return false end
  if #q < 1 or #q > 80 then return false end
  if q:find('%c') then return false end
  return true
end


-- ============================================================
-- EMBEDS (YouTube IFrame / SoundCloud Widget) — tocam via player oficial, nao <audio>.
-- Excecao consciente a A-10: exigem youtube.com/soundcloud.com acessiveis no client.
-- ============================================================

-- extrai o id de 11 chars de uma URL do YouTube (watch/youtu.be/shorts/embed/music) ou nil
function WOW_Config.parseYouTubeId(url)
  if type(url) ~= 'string' or #url == 0 or #url > 512 then return nil end

  local host = url:match('^https://([%w%.%-]+)/')
  if not host then return nil end

  local isYt = host == 'youtu.be'
    or host == 'youtube.com' or host == 'www.youtube.com'
    or host == 'm.youtube.com' or host == 'music.youtube.com'
  if not isYt then return nil end

  local id = url:match('[?&]v=([%w_%-]+)')
    or url:match('youtu%.be/([%w_%-]+)')
    or url:match('/shorts/([%w_%-]+)')
    or url:match('/embed/([%w_%-]+)')

  if id and #id >= 11 then return id:sub(1, 11) end
  return nil
end

-- valida permalink do SoundCloud (host ancorado + caminho /artista/faixa)
function WOW_Config.isSoundCloudUrl(url)
  if type(url) ~= 'string' or #url == 0 or #url > 512 then return false end

  local host, path = url:match('^https://([%w%.%-]+)(/.*)$')
  if not host then return false end
  if not (host == 'soundcloud.com' or host == 'www.soundcloud.com' or host == 'm.soundcloud.com') then
    return false
  end

  return path:match('^/[%w%-_]+/[%w%-_]+') ~= nil
end

-- aceita p/ playback: arquivo direto (allowlist) OU YouTube OU SoundCloud
function WOW_Config.isPlayableUrl(url)
  if WOW_Config.isValidUrl(url) then return true end
  if WOW_Config.parseYouTubeId(url) then return true end
  if WOW_Config.isSoundCloudUrl(url) then return true end
  return false
end
