---@diagnostic disable: undefined-global, lowercase-global

-- server/music_search.lua — busca de musica com failover de providers + cache + radio.
--
-- Mantem o contrato historico WOW_Music.searchTracks/radioTrackSync (consumido pelo
-- vhub_vehcontrol aba Som), mas por baixo delega ao registry de providers YouTube
-- (InnerTube primario → APIv3 fallback). Dono unico de: egress (nos providers), cache,
-- normalizacao e curadoria da radio. Segredo (chave APIv3) vive na convar server-only.


WOW_Music = {}


-- ============================================================
-- REGISTRY DE PROVIDERS (ordem = prioridade; failover em cascata)
-- ============================================================

local PROVIDERS = {
  WOW_Provider_InnerTube,   -- primario: sem chave, sem cota
  WOW_Provider_ApiV3,       -- fallback: exige convar wow_youtube_key
}

-- tenta os providers prontos em ordem; para no primeiro que devolver lista nao-vazia.
-- cb(items) sempre chamado (lista vazia se todos falharem).
local function runProviders(query, cb)
  local i = 0

  local function tryNext()
    i = i + 1
    local p = PROVIDERS[i]
    if not p then return cb({}) end                 -- esgotou os providers
    if type(p.ready) ~= 'function' or not p.ready() then return tryNext() end

    p.search(query, function(items)
      if type(items) == 'table' and #items > 0 then
        return cb(items)                            -- sucesso: encerra a cascata
      end
      tryNext()                                     -- nil (falha) ou vazio: proximo provider
    end)
  end

  tryNext()
end


-- ============================================================
-- CACHE DE BUSCA (por query normalizada; TTL controla egress)
-- ============================================================

local searchCache  = {}     -- [queryKey] = { at = ms, items = {...} }
local searchCacheN = 0
local SEARCH_CACHE_MAX = 64  -- teto: alem disso, zera (anti-leak; L-18)
local SEARCH_CONCURRENCY_MAX = 2
local SEARCH_QUEUE_MAX = 32
local SEARCH_WAITERS_MAX = 64
local searchInflight = {}
local searchQueue = {}
local searchActive = 0

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

local pumpSearchQueue

-- Executa egress com concorrencia fixa, deduplicacao e fila limitada.
pumpSearchQueue = function()
  while searchActive < SEARCH_CONCURRENCY_MAX and #searchQueue > 0 do
    local key = table.remove(searchQueue, 1)
    local entry = searchInflight[key]
    if entry then
      searchActive = searchActive + 1
      local completed = false
      runProviders(entry.query, function(items)
        if completed then return end
        completed = true
        searchActive = math.max(0, searchActive - 1)
        items = type(items) == 'table' and items or {}
        if #items > 0 then cacheStore(key, items) end

        local callbacks = entry.callbacks
        searchInflight[key] = nil
        for index = 1, #callbacks do pcall(callbacks[index], items) end
        SetTimeout(0, pumpSearchQueue)
      end)
    end
  end
end

-- busca faixas por texto livre (faixa/artista). cb(items) sempre chamado.
function WOW_Music.searchTracks(query, cb)
  if type(cb) ~= 'function' then return end
  if not WOW_Config.isValidSearchQuery(query) then return cb({}) end

  local key = cacheKey(query)
  local hit = searchCache[key]
  if hit and (GetGameTimer() - hit.at) < WOW_Config.YouTube.searchCacheMs then
    return cb(hit.items)
  end

  local pending = searchInflight[key]
  if pending then
    if #pending.callbacks >= SEARCH_WAITERS_MAX then return cb({}) end
    pending.callbacks[#pending.callbacks + 1] = cb
    return
  end
  if #searchQueue >= SEARCH_QUEUE_MAX then return cb({}) end

  searchInflight[key] = { query = query, callbacks = { cb } }
  searchQueue[#searchQueue + 1] = key
  pumpSearchQueue()
end


-- ============================================================
-- RADIO — playlist curada por videoId semente (config), sem depender de ranking de API
-- ============================================================

local radio = { items = {} }   -- faixas prontas montadas das sementes

-- monta a lista de faixas da radio a partir das sementes validadas em config
local function buildRadio()
  local out = {}
  for _, id in ipairs(WOW_Config.YouTube.radioSeed or {}) do
    if WOW_Config.isValidVideoId(id) then
      out[#out + 1] = {
        id       = id,
        title    = 'Radio da Cidade',
        artist   = 'vHub FM',
        url      = WOW_Config.buildEmbedUrl(id),
        duration = 0,
      }
    end
  end
  radio.items = out
end

-- sorteia 1 faixa da radio (SINCRONO — retorna na hora). nil = radio sem sementes validas.
function WOW_Music.radioTrackSync()
  if #radio.items == 0 then buildRadio() end
  if #radio.items == 0 then return nil end
  return radio.items[math.random(#radio.items)]
end


-- ============================================================
-- WARM-UP — monta a radio no start (sem egress; sementes sao estaticas)
-- ============================================================

CreateThread(function()
  buildRadio()
end)
