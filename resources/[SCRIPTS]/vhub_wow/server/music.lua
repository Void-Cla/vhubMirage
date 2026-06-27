---@diagnostic disable: undefined-global, lowercase-global

-- server/music.lua — provider de musica (Jamendo padrao) + cache + normalizacao.
-- Dono unico da integracao: segredo, egress HTTP e cache moram aqui (decisao #34).
-- Consumido pelos exports SearchTracks/GetRadioTrack (server/exports.lua).
--
-- SEGREDO: client_id vem de convar server-only (wow_jamendo_id) — nunca no shared
-- config, nunca enviado ao client. client_secret reservado (read-only nao usa OAuth).

WOW_Music = {}


-- ============================================================
-- CREDENCIAIS (convar server-only) + estado de prontidao
-- ============================================================

local JAMENDO_ID = GetConvar('wow_jamendo_id', '')
-- client_secret (wow_jamendo_secret) reservado p/ OAuth/write futuro — read-only nao usa.

-- Jamendo habilitado e com credencial?
local function jamendoReady()
  return WOW_Config.Jamendo and WOW_Config.Jamendo.enabled and JAMENDO_ID ~= ''
end


-- ============================================================
-- HELPERS (encode + normalizacao da resposta)
-- ============================================================

-- percent-encode (RFC 3986) — poe a query do usuario na URL da API com seguranca
local function urlencode(s)
  return (tostring(s):gsub('[^%w%-_%.~]', function(c)
    return ('%%%02X'):format(string.byte(c))
  end))
end

-- normaliza 1 faixa do Jamendo p/ o contrato { id, title, artist, url, duration }.
-- descarta faixa sem audio valido ou com host fora da allowlist (defesa em profundidade)
local function normalizeTrack(t)
  if type(t) ~= 'table' then return nil end

  local url = t.audio
  if type(url) ~= 'string' or not WOW_Config.isValidUrl(url) then return nil end

  return {
    id       = tostring(t.id or ''),
    title    = tostring(t.name or 'Faixa'),
    artist   = tostring(t.artist_name or '—'),
    url      = url,
    duration = tonumber(t.duration) or 0,
  }
end

-- decodifica o corpo JSON do Jamendo numa lista normalizada de faixas
local function parseTracks(body)
  local ok, data = pcall(json.decode, body)
  if not ok or type(data) ~= 'table' or type(data.results) ~= 'table' then
    return {}
  end

  local out = {}
  for _, t in ipairs(data.results) do
    local n = normalizeTrack(t)
    if n then out[#out + 1] = n end
  end
  return out
end


-- ============================================================
-- BUSCA — cache por query normalizada (TTL controla chamadas a API)
-- ============================================================

local searchCache  = {}     -- [queryKey] = { at = ms, items = {...} }
local searchCacheN = 0
local SEARCH_CACHE_MAX = 64  -- teto: alem disso, zera (anti-leak; L-18)

-- chave de cache da busca (minusculo + espacos colapsados + trim)
local function cacheKey(query)
  return query:lower():gsub('%s+', ' '):gsub('^%s*(.-)%s*$', '%1')
end

-- guarda resultado no cache respeitando o teto de tamanho
local function cacheStore(key, items)
  if searchCacheN >= SEARCH_CACHE_MAX then
    searchCache, searchCacheN = {}, 0
  end
  if not searchCache[key] then searchCacheN = searchCacheN + 1 end
  searchCache[key] = { at = GetGameTimer(), items = items }
end

-- busca faixas por texto livre (faixa/artista/album/tag). cb(items) sempre chamado.
function WOW_Music.searchTracks(query, cb)
  if type(cb) ~= 'function' then return end
  if not WOW_Config.isValidSearchQuery(query) then return cb({}) end
  if not jamendoReady() then return cb({}) end

  local key = cacheKey(query)
  local hit = searchCache[key]
  if hit and (GetGameTimer() - hit.at) < WOW_Config.Jamendo.searchCacheMs then
    return cb(hit.items)
  end

  local J = WOW_Config.Jamendo
  local url = ('%stracks/?client_id=%s&format=json&limit=%d&audioformat=%s&search=%s'):format(
    J.base, urlencode(JAMENDO_ID), J.searchLimit, J.audioformat, urlencode(query))

  PerformHttpRequest(url, function(status, body)
    if status == 200 and type(body) == 'string' then
      local items = parseTracks(body)
      cacheStore(key, items)   -- cacheia ate "sem resultados" (nao muda em 5 min)
      return cb(items)
    end
    cb({})                     -- falha transitoria: nao cacheia (permite retry)
  end, 'GET')
end


-- ============================================================
-- RADIO — playlist top-semana em cache, refresh lazy (sem polling, L-06)
-- ============================================================

local radio = { at = 0, items = {}, fetching = false }

-- refaz a playlist semanal em background (fire-and-forget; nunca bloqueia o caller)
local function refreshRadio()
  if radio.fetching or not jamendoReady() then return end
  radio.fetching = true

  local J = WOW_Config.Jamendo
  local url = ('%stracks/?client_id=%s&format=json&limit=%d&audioformat=%s&order=popularity_week'):format(
    J.base, urlencode(JAMENDO_ID), J.radioLimit, J.audioformat)

  PerformHttpRequest(url, function(status, body)
    if status == 200 and type(body) == 'string' then
      local items = parseTracks(body)
      if #items > 0 then radio.items = items; radio.at = GetGameTimer() end
    end
    radio.fetching = false
  end, 'GET')
end

-- sorteia 1 faixa das mais tocadas da semana DO CACHE (sincrono — retorna na hora).
-- dispara refresh em background se vazio/vencido (nao espera). nil = cache ainda frio.
function WOW_Music.radioTrackSync()
  local stale = (GetGameTimer() - radio.at) >= WOW_Config.Jamendo.radioCacheMs
  if #radio.items == 0 or stale then refreshRadio() end

  if #radio.items == 0 then return nil end
  return radio.items[math.random(#radio.items)]
end


-- ============================================================
-- WARM-UP — aquece a playlist no start (1 HTTP unico, sem polling)
-- ============================================================

-- sem client_id, refreshRadio() retorna cedo (jamendoReady=false) — start silencioso
CreateThread(function()
  refreshRadio()
end)
