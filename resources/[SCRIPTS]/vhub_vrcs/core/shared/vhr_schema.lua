-- core/shared/vhr_schema.lua — contrato do arquivo .vhr (FONTE UNICA do formato).
--
-- Define a versao, os construtores do replay/jogador e os validadores. Puro:
-- sem I/O e sem dependencia de corrida especifica (o binding e quem mapeia a
-- telemetria do racha para este contrato). Coords sao primitivos flat (L-19).

VRCS = VRCS or {}

local S = {}; VRCS.Schema = S

S.VERSION = (VRCS.Cfg and VRCS.Cfg.SCHEMA_VERSION) or 'vhub_racha.vhr.v2'

-- classificacao de confianca dos campos do frame (formalizada a partir da v2).
-- AUTHORITATIVE: ja validado pelo vhub_racha antes da montagem do replay
-- (posicao, tempo, colocacao). COSMETIC: best-effort, vem do client sem
-- validacao server-side — aceitavel pois a verdade competitiva (colocacao,
-- tempo, premio) ja foi decidida antes deste artefato existir (vrcs.md, R3).
S.TRUST = {
    authoritative = { 'x', 'y', 'z', 't', 's', 'placement', 'timeMs' },
    cosmetic      = {
        'rx', 'ry', 'rz', 'rpm', 'g', 'st', 'hb',
        'vv', 'cl', 'th', 'eh', 'tp', 'bp', 'ws', 'wc', 'bf', 'lf',
    },
}


-- ============================================================
-- VALIDADORES
-- ============================================================

-- valida UUID v4 textual (36 chars) — usado antes de tocar em qualquer path
function S.is_uuid(s)
    if type(s) ~= 'string' or #s ~= 36 then return false end
    return s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end

-- valida a estrutura minima de um replay antes de serializar/persistir
function S.validate(replay)
    if type(replay) ~= 'table'        then return false, 'not_table'  end
    if replay.schema ~= S.VERSION     then return false, 'bad_schema' end
    if not S.is_uuid(replay.raceId)   then return false, 'bad_raceId' end
    if type(replay.players) ~= 'table' then return false, 'no_players' end
    return true
end


-- ============================================================
-- CONSTRUTORES
-- ============================================================

-- monta o esqueleto de um replay a partir do meta de abertura.
-- IMPORTANTE (PII): o .vhr identifica o piloto SOMENTE por charId — nunca nick,
-- identifier, license ou IP. O nome de exibicao e resolvido so na publicacao.
function S.new_replay(meta)
    local players = {}
    for _, p in ipairs(meta.players or {}) do
        players[#players + 1] = {
            charId        = tonumber(p.char_id) or 0,
            vehicle       = tostring(p.vehicle or ''),   -- hash do modelo
            plate         = tostring(p.plate or ''),     -- cosmetico no replay
            customization = (type(p.customization) == 'table') and p.customization or nil,
            pedModel      = tostring(p.pedModel or ''),  -- fallback do motorista
            ped           = nil,                          -- look completo (chega via set_look)
            placement     = 0,
            timeMs        = 0,
            finished      = false,
            events        = {},
            frames        = {},
        }
    end

    return {
        schema       = S.VERSION,
        raceId       = meta.raceId,
        track        = tostring(meta.track or '?'),
        kind         = tostring(meta.kind or 'sprint'),
        category     = tostring(meta.category or 'normal'),
        startTime    = meta.startTime or os.date('!%Y-%m-%dT%H:%M:%SZ'),
        duration     = 0,
        winnerCharId = 0,
        trust        = S.TRUST,
        players      = players,
    }
end
