---@diagnostic disable: undefined-global, lowercase-global

-- server/publisher.lua — publicacao do RESULTADO + replay no Discord (TESTE Fase 1).
--
-- ATENCAO ARQUITETURAL: o design (vrcs.md 9.4) define que PerformHttpRequest mora
-- no RENDERER isolado (Fase 5), NUNCA no servidor principal. Este modulo e uma
-- CONCESSAO DE TESTE.
--
-- O .mp4 NAO e gerado aqui: render de video exige o jogo rodando numa maquina com
-- GPU (renderer F2-F5) que reproduz o .vhr e captura via FFmpeg. Ate o renderer
-- existir, o canal recebe o RESULTADO + o arquivo .vhr (replay em dados) anexado —
-- que ja identifica o raceId e os char_ids de TODOS os participantes.
--
-- Seguranca: segredo via convar (fail-closed); embed sem PII sensivel (so nick +
-- char_id de jogo); nick tratado como dado HOSTIL (strip de mencao + clamp).

VRCS = VRCS or {}

local Cfg = VRCS.Cfg
local Log = VRCS.Log

local P = {}; VRCS.Publisher = P


-- ============================================================
-- HELPERS
-- ============================================================

-- sanitiza texto para o embed: remove mencao (@everyone/@here/<@id>), markdown
-- perigoso e quebras de linha; limita o tamanho. Trata como texto puro.
local function sanitize(s, maxlen)
    s = tostring(s or '')
    s = s:gsub('@', ''):gsub('[`<>]', ''):gsub('[\r\n]', ' ')
    if maxlen and #s > maxlen then s = s:sub(1, maxlen) end
    if s == '' then s = '—' end
    return s
end


-- formata milissegundos como mm:ss
local function fmt_time(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then return '—' end
    local s = math.floor(ms / 1000)
    return ('%02d:%02d'):format(math.floor(s / 60), s % 60)
end


-- medalha/posicao para a linha do participante
local function medal(pos)
    if pos == 1 then return '🥇' end
    if pos == 2 then return '🥈' end
    if pos == 3 then return '🥉' end
    return ('`#%s`'):format(tostring(pos or '?'))
end


-- monta a lista de participantes (ordenada por colocacao) com char_id p/ identificar
local function participants_field(finalMeta, max_nick)
    local plist = {}
    for _, pl in ipairs((finalMeta and finalMeta.players) or {}) do plist[#plist + 1] = pl end
    table.sort(plist, function(a, b)
        return (tonumber(a.placement) or 99) < (tonumber(b.placement) or 99)
    end)

    local lines = {}
    for _, pl in ipairs(plist) do
        lines[#lines + 1] = ('%s %s — `char %s`%s'):format(
            medal(tonumber(pl.placement) or 0),
            sanitize(pl.nick, max_nick),
            tostring(pl.char_id or '?'),
            pl.finished and '' or ' *(DNF)*')
    end

    local txt = table.concat(lines, '\n')
    if txt == '' then txt = '—' end
    if #txt > 1000 then txt = txt:sub(1, 1000) end
    return txt
end


-- envia o POST: multipart com anexo .vhr quando possivel, senao JSON puro.
local function post(webhook, payload, vhr_data, filename)
    local cb = function(status)
        if status == 429 then
            Log.warn('webhook Discord: 429 (rate limited)')
        elseif type(status) == 'number' and status >= 400 then
            Log.warn(('webhook Discord falhou: HTTP %s'):format(tostring(status)))
        end
    end

    -- anexo: multipart/form-data (payload_json + files[0])
    if vhr_data then
        local boundary = ('----vrcs%d%d'):format(math.random(100000, 999999), os.time())
        local body = table.concat({
            '--' .. boundary,
            'Content-Disposition: form-data; name="payload_json"',
            'Content-Type: application/json',
            '',
            json.encode(payload),
            '--' .. boundary,
            ('Content-Disposition: form-data; name="files[0]"; filename="%s"'):format(filename),
            'Content-Type: application/json',
            '',
            vhr_data,
            '--' .. boundary .. '--',
            '',
        }, '\r\n')
        PerformHttpRequest(webhook, cb, 'POST', body,
            { ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary })
        return
    end

    -- sem anexo: JSON puro
    PerformHttpRequest(webhook, cb, 'POST', json.encode(payload),
        { ['Content-Type'] = 'application/json' })
end


-- ============================================================
-- PUBLISH
-- ============================================================

-- publica o resultado da corrida + anexa o .vhr. vhr_data = string serializada do
-- replay (passada pelo recorder no close); os nicks vem em finalMeta (usados SO
-- aqui — nunca persistidos no .vhr).
function P.publish_result(replay, finalMeta, vhr_data)
    local d = Cfg.DISCORD
    if not d or not d.enabled then return end

    local webhook = GetConvar(d.webhook_convar or 'vrcs_discord_webhook', '')
    if webhook == nil or webhook == '' then return end   -- fail-closed: sem segredo, sem post

    local max_nick = d.max_nick_len or 24

    -- vencedor (1o lugar que terminou)
    local winner_nick, winner_time = '—', 0
    for _, pl in ipairs((finalMeta and finalMeta.players) or {}) do
        if (tonumber(pl.placement) or 0) == 1 and pl.finished then
            winner_nick = sanitize(pl.nick, max_nick)
            winner_time = tonumber(pl.time_ms) or 0
            break
        end
    end

    local payload = {
        username = d.username or 'VHUB Race Cinema',
        embeds = { {
            title = '🏁 Corrida Ranqueada Finalizada',
            description = '🎥 Replay (`.vhr`) em anexo — o `.mp4` cinematográfico entra quando o renderer estiver no ar.',
            color = d.embed_color or 15255170,
            fields = {
                { name = '🏆 Vencedor', value = winner_nick,                                inline = true  },
                { name = '⏱️ Tempo',    value = fmt_time(winner_time),                       inline = true  },
                { name = '🛣️ Pista',    value = sanitize(tostring(replay.track or '?'), 40), inline = true  },
                { name = '👥 Participantes', value = participants_field(finalMeta, max_nick), inline = false },
                { name = '🆔 Race ID',  value = ('`%s`'):format(tostring(replay.raceId)),    inline = false },
            },
            footer = { text = ('%d pilotos • %ds'):format(#(replay.players or {}), replay.duration or 0) },
        } },
    }

    -- anexa o .vhr se habilitado e dentro do teto do webhook
    local attach = nil
    if d.attach_vhr and type(vhr_data) == 'string'
       and #vhr_data <= (d.max_attach_bytes or (8 * 1024 * 1024)) then
        attach = vhr_data
    end

    post(webhook, payload, attach, ('%s.vhr'):format(tostring(replay.raceId)))
end
