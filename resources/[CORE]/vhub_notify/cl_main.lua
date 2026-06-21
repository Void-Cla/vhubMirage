-- cl_main.lua — front-end cliente do toast global (escuta vHub:notify, normaliza e entrega ao NUI)


-- ============================================================
-- NORMALIZACAO / VALIDACAO
-- ============================================================

-- mapa de tipo PT-BR/EN -> tipo canonico do NUI (desconhecido cai em 'info')
local TYPE_MAP = {
    sucesso = 'success', success = 'success',
    negado  = 'error',   erro    = 'error',   error = 'error',
    aviso   = 'warning', warning = 'warning',
    info    = 'info',
}

local TITLE_MAX, MSG_MAX       = 200, 500
local DUR_MIN, DUR_MAX, DUR_DEF = 1000, 10000, 5000

-- coage para string e aplica teto de tamanho (anti-flood de DOM)
local function clampStr(v, max)
    v = tostring(v or '')
    if #v > max then v = v:sub(1, max) end
    return v
end

-- monta payload normalizado a partir das 2 formas aceitas (simples ou tabela rica)
local function buildPayload(a, b)
    local raw
    if type(a) == 'table' then
        raw = {
            type     = a.type,
            title    = a.title or a.titulo,
            msg      = a.msg or a.message or a.mensagem,
            duration = a.duration or a.tempo,
        }
    else
        raw = { type = a, msg = b }
    end

    local dur = tonumber(raw.duration) or DUR_DEF
    if dur ~= dur then dur = DUR_DEF end          -- descarta NaN
    dur = math.max(DUR_MIN, math.min(DUR_MAX, dur))

    return {
        type     = TYPE_MAP[tostring(raw.type or ''):lower()] or 'info',
        title    = clampStr(raw.title, TITLE_MAX),
        msg      = clampStr(raw.msg,   MSG_MAX),
        duration = dur,
    }
end


-- ============================================================
-- RATE LIMIT (anti-spam local de toast)
-- ============================================================

local _tokens, _lastRefill = 10, GetGameTimer()

-- token bucket (~10 toasts/s, rajada 10) sobre o proprio cliente
local function allowed()
    local now = GetGameTimer()
    _tokens = math.min(10, _tokens + (now - _lastRefill) / 100)
    _lastRefill = now
    if _tokens < 1 then return false end
    _tokens = _tokens - 1
    return true
end


-- ============================================================
-- ENTREGA AO NUI
-- ============================================================

-- normaliza, valida e envia o toast ao NUI
local function show(a, b)
    if not allowed() then return end
    SendNUIMessage({ action = 'notify', data = buildPayload(a, b) })
end

-- exibe um toast a partir de tabela rica { type, title|titulo, msg, duration|tempo }
exports('notify', function(data) show(data) end)

-- alias de compatibilidade (mesma assinatura de tabela rica)
exports('sendAlert', function(data) show(data) end)


-- ============================================================
-- EVENTO CANONICO GLOBAL
-- ============================================================

-- porta unica do toast: aceita forma simples (type, msg) e tabela rica
RegisterNetEvent('vHub:notify', function(a, b)
    show(a, b)
end)


-- ============================================================
-- DEV / TESTE  (TEMPORARIO — remover apos validar o visual)
-- ============================================================

-- /testnotify — dispara um toast de cada tipo (apenas validacao visual)
RegisterCommand('testnotify', function()
    show('sucesso', 'Veiculo guardado com sucesso.')
    show('erro',    'Saldo insuficiente para a operacao.')
    show({ type = 'aviso', title = 'Concessionaria', msg = 'IPVA vence em 2 dias.', duration = 7000 })
    show('info',    'Pressione E para interagir.')
end, false)
