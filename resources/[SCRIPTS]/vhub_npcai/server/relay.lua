---@diagnostic disable: undefined-global, unused-local
-- relay.lua - ponte Lua para o sidecar Python via HTTP loopback autenticado

VHubNpcAI       = VHubNpcAI or {}
VHubNpcAI.Relay = {}
local Relay     = VHubNpcAI.Relay
local cfg       = VHubNpcAI.cfg
local _token    = nil


-- ============================================================
-- HELPERS
-- ============================================================

local function _url(path)
    return ('http://%s:%d%s'):format(cfg.sidecar.host, cfg.sidecar.port, path)
end

-- carrega o segredo compartilhado gerado pelo bootstrap
local function _loadToken()
    if _token then return _token end

    local raw = LoadResourceFile(GetCurrentResourceName(), '.sidecar-token')
    raw = type(raw) == 'string' and raw:match('^%s*(.-)%s*$') or ''
    if #raw ~= 64 or raw:find('[^%x]') then return nil end

    _token = raw
    return _token
end

local function _headers(contentType)
    local token = _loadToken()
    if not token then return nil end

    local headers = { ['X-NPCAI-Token'] = token }
    if contentType then headers['Content-Type'] = contentType end
    return headers
end

-- envia JSON ao sidecar e retorna resposta decodificada
local function _post(path, bodyJson, cb)
    local headers = _headers('application/json')
    if not headers then
        cb(false, { err = 'token_ausente' })
        return
    end

    local finalizado = false
    SetTimeout(tonumber(cfg.sidecar.timeout) or 45000, function()
        if finalizado then return end
        finalizado = true
        cb(false, { err = 'sidecar_timeout' })
    end)

    PerformHttpRequest(_url(path), function(statusCode, responseText, _responseHeaders, errorData)
        if finalizado then return end
        finalizado = true

        if statusCode == 200 and responseText then
            local ok, parsed = pcall(json.decode, responseText)
            if ok and parsed then
                cb(true, parsed)
                return
            end
            cb(false, { err = 'json_decode_fail', raw = responseText })
            return
        end
        local err = 'http_' .. tostring(statusCode)
        if type(responseText) == 'string' and #responseText > 0 then
            local ok, parsed = pcall(json.decode, responseText)
            if ok and type(parsed) == 'table' and type(parsed.err) == 'string' then
                err = parsed.err:sub(1, 64)
            end
        elseif type(errorData) == 'string' and #errorData > 0 then
            err = errorData:gsub('[\r\n]', ' '):sub(1, 64)
        end
        cb(false, { err = err, code = statusCode })
    end, 'POST', bodyJson, headers)
end


-- ============================================================
-- HEALTH
-- ============================================================

function Relay.health(cb)
    local headers = _headers()
    if not headers then
        cb(false, { err = 'token_ausente' })
        return
    end

    PerformHttpRequest(_url('/health'), function(code, body)
        if code == 200 and body then
            local ok, parsed = pcall(json.decode, body)
            if ok and parsed and parsed.ok and parsed.service == 'vhub_npcai' then
                cb(true, parsed)
                return
            end
        end
        cb(false, { err = 'sidecar_invalido', code = code })
    end, 'GET', '', headers)
end


-- ============================================================
-- PREWARM
-- ============================================================

function Relay.prewarmName(npcId, charName)
    local ai = VHubNpcAI.resolveAI(npcId)
    local body = json.encode({ npc_id = npcId, char_name = charName, voice = ai.voice })
    local headers = _headers('application/json')
    if not headers then return end

    PerformHttpRequest(_url('/prewarm_name'), function() end, 'POST', body, headers)
end


-- ============================================================
-- CONVERSA
-- ============================================================

function Relay.converse(data, cb)
    -- campos nil são omitidos do JSON para evitar null no sidecar Python
    local payload = {
        char_id  = data.char_id,
        char_name = data.char_name,
        npc_id   = data.npc_id,
        lang     = data.lang or 'pt',
        memory   = data.memory or {},
        ai       = data.ai,
        meta     = data.meta,
    }
    if data.audio       then payload.audio       = data.audio       end
    if data.direct_text then payload.direct_text = data.direct_text end
    if data.interrupted then payload.interrupted = true             end
    _post('/converse', json.encode(payload), cb)
end


-- ============================================================
-- CONFIGURACAO
-- ============================================================

function Relay.pushConfig(keys, cb)
    _post('/config', json.encode(keys or {}), cb or function() end)
end


-- ============================================================
-- RELOAD
-- ============================================================

function Relay.reloadNpcs(cb)
    _post('/reload_npcs', '{}', cb or function() end)
end


-- ============================================================
-- FIM DE SESSÃO — limpa a memória curta efêmera do char no sidecar
-- ============================================================

-- avisa o sidecar para descartar o ring buffer de contexto do char (playerDropped)
function Relay.sessionEnd(charId)
    if not charId or charId <= 0 then return end
    _post('/session_end', json.encode({ char_id = charId }), function() end)
end
