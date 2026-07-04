---@diagnostic disable: undefined-global, lowercase-global

-- server/providers/youtube_innertube.lua — provider PRIMARIO de busca no YouTube.
--
-- Usa o endpoint interno "InnerTube" (o mesmo que o site do YouTube usa): sem chave,
-- sem cota. Egress isolado aqui (dono unico). Parser DEFENSIVO: payload adversario/mudado
-- nunca derruba o resource (pcall + checagem de tipo em cada nivel).


WOW_Provider_InnerTube = {}


-- ============================================================
-- CONSTANTES (contexto de cliente exigido pelo InnerTube)
-- ============================================================

-- chave publica do InnerTube (nao e segredo — vai embutida no proprio site do YouTube).
local INNERTUBE_KEY = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8'
local SEARCH_ENDPOINT = 'https://www.youtube.com/youtubei/v1/search?key=' .. INNERTUBE_KEY
local MAX_BODY = 4 * 1024 * 1024   -- teto de resposta (anti-payload gigante); 4 MB

-- corpo base da requisicao: identifica um cliente WEB valido para o InnerTube
local function buildBody(query)
  return json.encode({
    query   = query,
    context = {
      client = {
        clientName    = 'WEB',
        clientVersion = '2.20240401.00.00',
        hl            = 'pt',
        gl            = 'BR',
      },
    },
    -- EgIQAQ%3D%3D = filtro "somente videos" (decodificado: type=video). Estavel.
    params = 'EgIQAQ%3D%3D',
  })
end


-- ============================================================
-- PARSER DEFENSIVO — desce a arvore do InnerTube sem confiar em nada
-- ============================================================

-- pega chave de tabela com seguranca (nil se caminho nao existe)
local function tget(t, k)
  if type(t) ~= 'table' then return nil end
  return t[k]
end

-- concatena os "runs" de texto do InnerTube ({ runs = {{text=..}, ..} } ou { simpleText = .. })
local function readText(node)
  if type(node) ~= 'table' then return nil end
  if type(node.simpleText) == 'string' then return node.simpleText end
  local runs = node.runs
  if type(runs) ~= 'table' then return nil end
  local out = {}
  for _, r in ipairs(runs) do
    if type(r) == 'table' and type(r.text) == 'string' then out[#out + 1] = r.text end
  end
  if #out == 0 then return nil end
  return table.concat(out)
end

-- "3:45" / "1:02:33" → segundos; nil se formato inesperado
local function parseDuration(text)
  if type(text) ~= 'string' then return 0 end
  local parts = {}
  for n in text:gmatch('%d+') do parts[#parts + 1] = tonumber(n) end
  if #parts == 2 then return parts[1] * 60 + parts[2] end
  if #parts == 3 then return parts[1] * 3600 + parts[2] * 60 + parts[3] end
  return 0
end

-- normaliza 1 videoRenderer do InnerTube para o contrato { id, title, artist, url, duration }.
-- descarta qualquer item sem videoId de 11 chars valido (defesa em profundidade).
local function normalizeVideo(vr)
  local id = tget(vr, 'videoId')
  if not WOW_Config.isValidVideoId(id) then return nil end

  local url = WOW_Config.buildEmbedUrl(id)
  if not url then return nil end

  local title = readText(tget(vr, 'title')) or 'Faixa'
  local artist = readText(tget(vr, 'ownerText'))
    or readText(tget(vr, 'longBylineText'))
    or '—'
  local duration = parseDuration(readText(tget(vr, 'lengthText')))

  return {
    id       = id,
    title    = tostring(title),
    artist   = tostring(artist),
    url      = url,
    duration = duration,
  }
end

-- varre a arvore de resultados e coleta os videoRenderer (limite = searchLimit)
local function extractResults(data, limit)
  local out = {}

  local contents = tget(tget(tget(tget(data,
    'contents'), 'twoColumnSearchResultsRenderer'), 'primaryContents'),
    'sectionListRenderer')
  contents = tget(contents, 'contents')
  if type(contents) ~= 'table' then return out end

  for _, section in ipairs(contents) do
    local items = tget(tget(section, 'itemSectionRenderer'), 'contents')
    if type(items) == 'table' then
      for _, item in ipairs(items) do
        local vr = tget(item, 'videoRenderer')
        if vr then
          local n = normalizeVideo(vr)
          if n then
            out[#out + 1] = n
            if #out >= limit then return out end
          end
        end
      end
    end
  end

  return out
end


-- ============================================================
-- PORTA DO PROVIDER — search(query, cb)
-- ============================================================

-- provider habilitado? (InnerTube nao precisa de chave — so respeita o toggle de config)
function WOW_Provider_InnerTube.ready()
  return WOW_Config.YouTube.innertube and WOW_Config.YouTube.innertube.enabled == true
end

-- busca faixas por texto. cb(items|nil): nil = falha transitoria (deixa o registry tentar
-- o proximo provider); tabela (mesmo vazia) = resposta valida do provider.
function WOW_Provider_InnerTube.search(query, cb)
  local body = buildBody(query)
  local limit = WOW_Config.YouTube.searchLimit

  PerformHttpRequest(SEARCH_ENDPOINT, function(status, resp)
    if status ~= 200 or type(resp) ~= 'string' or #resp == 0 or #resp > MAX_BODY then
      return cb(nil)
    end

    local ok, data = pcall(json.decode, resp)
    if not ok or type(data) ~= 'table' then return cb(nil) end

    local items = extractResults(data, limit)
    return cb(items)
  end, 'POST', body, { ['Content-Type'] = 'application/json' })
end
