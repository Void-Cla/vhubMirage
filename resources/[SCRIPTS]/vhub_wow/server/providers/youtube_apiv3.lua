---@diagnostic disable: undefined-global, lowercase-global

-- server/providers/youtube_apiv3.lua — provider FALLBACK de busca no YouTube.
--
-- YouTube Data API v3 (oficial). Exige chave via convar server-only `wow_youtube_key`.
-- Fica INERTE enquanto a convar estiver vazia (ready()=false → registry pula este provider).
-- Cota diaria limitada — por isso e fallback, nao primario.


WOW_Provider_ApiV3 = {}


local API_KEY = GetConvar('wow_youtube_key', '')
local SEARCH_BASE = 'https://www.googleapis.com/youtube/v3/search'
local MAX_BODY = 1 * 1024 * 1024   -- resposta da APIv3 e compacta; 1 MB e folgado


-- percent-encode (RFC 3986) — poe a query do usuario na URL com seguranca
local function urlencode(s)
  return (tostring(s):gsub('[^%w%-_%.~]', function(c)
    return ('%%%02X'):format(string.byte(c))
  end))
end

-- normaliza 1 item da APIv3 para o contrato { id, title, artist, url, duration }.
-- duration nao vem na busca da APIv3 (exigiria chamada extra videos.list) → 0.
local function normalizeItem(it)
  if type(it) ~= 'table' then return nil end
  local id = it.id and it.id.videoId
  if not WOW_Config.isValidVideoId(id) then return nil end

  local url = WOW_Config.buildEmbedUrl(id)
  if not url then return nil end

  local sn = it.snippet or {}
  return {
    id       = id,
    title    = tostring(sn.title or 'Faixa'),
    artist   = tostring(sn.channelTitle or '—'),
    url      = url,
    duration = 0,
  }
end


-- provider habilitado? exige toggle + chave presente (fail-closed)
function WOW_Provider_ApiV3.ready()
  return WOW_Config.YouTube.apiv3 and WOW_Config.YouTube.apiv3.enabled == true and API_KEY ~= ''
end

-- busca faixas por texto. cb(items|nil): nil = falha transitoria; tabela = resposta valida.
function WOW_Provider_ApiV3.search(query, cb)
  local limit = WOW_Config.YouTube.searchLimit
  local url = ('%s?part=snippet&type=video&maxResults=%d&q=%s&key=%s'):format(
    SEARCH_BASE, limit, urlencode(query), urlencode(API_KEY))

  PerformHttpRequest(url, function(status, resp)
    if status ~= 200 or type(resp) ~= 'string' or #resp == 0 or #resp > MAX_BODY then
      return cb(nil)
    end

    local ok, data = pcall(json.decode, resp)
    if not ok or type(data) ~= 'table' or type(data.items) ~= 'table' then return cb(nil) end

    local out = {}
    for _, it in ipairs(data.items) do
      local n = normalizeItem(it)
      if n then out[#out + 1] = n end
    end
    return cb(out)
  end, 'GET')
end
