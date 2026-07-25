---@diagnostic disable: undefined-global, lowercase-global

-- shared/config.lua — config do motor de audio/video (carregado client + server).


WOW_Config = {}


-- ============================================================
-- TRUST + LIMITES
-- ============================================================

-- resources autorizados a chamar os exports server-side (fail-closed: vazio = ninguem passa)
WOW_Config.TrustedResources = {
  'vhub_vehcontrol',
}

-- consumers client-side autorizados a alterar preferencias locais do WOW
WOW_Config.TrustedClientResources = {
  ['vhub_vehcontrol'] = true,
}

-- dominios permitidos para URL de AUDIO DIRETO (tocavel no <audio> HTML5).
-- Pagina de YouTube NAO entra aqui: e tratada a parte (parseYouTubeId + embed nocookie).
WOW_Config.AllowedDomains = {
  -- Discord CDN (anexos diretos)
  'cdn%.discordapp%.com',
  'media%.discordapp%.net',

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

WOW_Config.MaxDistance     = 80.0   -- distancia maxima de audicao (metros)
WOW_Config.DefaultDistance = 10.0   -- distancia padrao quando nao informada
WOW_Config.RateLimitMs     = 350    -- janela minima entre chamadas por resource (padrao _opAt do projeto)


-- ============================================================
-- YOUTUBE — busca (InnerTube + APIv3 fallback) e embed sem anuncio
-- ============================================================
--
-- SEGREDO: a chave da API v3 (fallback) vem de convar server-only `wow_youtube_key`.
-- NUNCA colocar chave real aqui (este arquivo e shared client+server). Vazia = so InnerTube.

WOW_Config.YouTube = {
  -- provider primario: InnerTube (endpoint interno youtubei/v1/search — sem chave, sem cota).
  innertube   = { enabled = true },

  -- provider fallback: YouTube Data API v3 (ativa quando convar wow_youtube_key preenchida).
  apiv3       = { enabled = true },

  searchLimit = 20,        -- resultados retornados por busca
  embedHost   = 'www.youtube-nocookie.com',  -- embed sem cookie/tracking (menos anuncio)

  searchCacheMs = 1800000, -- 30 min: mesma busca nao repete egress (InnerTube nao tem cota)
  radioCacheMs  = 3600000, -- 60 min: playlist da radio refrescada lazy (L-06)

  -- radio = playlist curada por videoId semente (config, nao vem de ranking de API).
  -- troque por hits/estacoes da cidade. Cada id = 11 chars.
  radioSeed = {
    'dQw4w9WgXcQ',
    '9bZkp7q19f0',
    'kJQP7kiw5Fk',
    'OPf0YbXqDm0',
    'fJ9rUzIMcZQ',
  },
}


-- ============================================================
-- VALIDACAO DE NOME/URL/QUERY (defesa em profundidade — client espelha server)
-- ============================================================

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
-- YOUTUBE — parse/validacao de id e URL de embed (sem <audio>)
-- ============================================================

-- extrai o id de 11 chars de uma URL do YouTube (watch/youtu.be/shorts/embed/music/nocookie) ou nil
function WOW_Config.parseYouTubeId(url)
  if type(url) ~= 'string' or #url == 0 or #url > 512 then return nil end

  local host = url:match('^https://([%w%.%-]+)/')
  if not host then return nil end

  local isYt = host == 'youtu.be'
    or host == 'youtube.com' or host == 'www.youtube.com'
    or host == 'm.youtube.com' or host == 'music.youtube.com'
    or host == 'www.youtube-nocookie.com' or host == 'youtube-nocookie.com'
  if not isYt then return nil end

  local id = url:match('[?&]v=([%w_%-]+)')
    or url:match('youtu%.be/([%w_%-]+)')
    or url:match('/shorts/([%w_%-]+)')
    or url:match('/embed/([%w_%-]+)')

  if id and #id >= 11 then return id:sub(1, 11) end
  return nil
end

-- valida um videoId cru de 11 chars (retorno de busca / semente de radio)
function WOW_Config.isValidVideoId(id)
  return type(id) == 'string' and #id == 11 and id:match('^[%w_%-]+$') ~= nil
end

-- monta a URL de embed sem anuncio (nocookie) a partir de um videoId ja validado
function WOW_Config.buildEmbedUrl(videoId)
  if not WOW_Config.isValidVideoId(videoId) then return nil end
  return ('https://%s/embed/%s'):format(WOW_Config.YouTube.embedHost, videoId)
end

-- aceita p/ playback: arquivo direto (allowlist) OU YouTube
function WOW_Config.isPlayableUrl(url)
  if WOW_Config.isValidUrl(url) then return true end
  if WOW_Config.parseYouTubeId(url) then return true end
  return false
end


-- ============================================================
-- ENTRADA DO BUSCADOR — "se nao for URL YouTube nem query valida, nem abre"
-- ============================================================

-- classifica o input do buscador. Regra do dono: aceita URL YouTube OU nome de
-- musica/artista; qualquer outra coisa (URL nao-YouTube, lixo) e recusada ANTES do egress.
--   { kind = 'video', id = '<11 chars>' }  → toca direto (pula busca)
--   { kind = 'query', q  = '<texto>'    }  → busca no provider
--   nil                                    → recusado (fail-closed)
function WOW_Config.acceptSearchInput(input)
  if type(input) ~= 'string' then return nil end

  local id = WOW_Config.parseYouTubeId(input)
  if id then return { kind = 'video', id = id } end

  -- URL http(s) que NAO e YouTube: recusa (evita SSRF/URL-hack via buscador)
  if input:match('^https?://') then return nil end

  if WOW_Config.isValidSearchQuery(input) then return { kind = 'query', q = input } end
  return nil
end
