---@diagnostic disable: undefined-global, param-type-mismatch
-- init.lua — lifecycle e handler principal do vhub_npcai (server-side)

local Core  = VHubNpcAI.Core
local Mem   = VHubNpcAI.Memory
local Relay = VHubNpcAI.Relay
local S     = VHubNpcAI.sql
local cfg   = VHubNpcAI.cfg
local E     = VHubNpcAI.E

-- estado de ocupação por npc_id: { src=<dono>, active=<bool>, ts=<ms> }
--   active=false → apenas reservado (warm handoff, ainda gravando)
--   active=true  → fala em processamento no sidecar
local _npc = {}

-- janela (ms) que uma reserva sem fala sobrevive antes de expirar (warm handoff)
local RESERVE_TTL = 12000

-- true se o NPC está ocupado por OUTRO src (reserva viva ou fala ativa)
local function _npcBusyForOther(npcId, src)
    local o = _npc[npcId]
    if not o then return false end
    if o.src == src then return false end
    -- reserva antiga sem fala expira sozinha
    if not o.active and (GetGameTimer() - o.ts) > RESERVE_TTL then
        _npc[npcId] = nil
        return false
    end
    return true
end

-- libera o NPC se pertencer a este src
local function _npcRelease(npcId, src)
    local o = _npc[npcId]
    if o and o.src == src then _npc[npcId] = nil end
end


-- ============================================================
-- BOOT
-- ============================================================

-- verifica sidecar e aplica schema ao iniciar
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end

    S.applySchema()

    -- health-check com RETRY bounded (Whisper leva ~10s p/ subir; ordem de start não importa).
    -- Bounded (12×5s = ~60s), sai no 1º sucesso — não é polling infinito (L-06).
    Citizen.CreateThread(function()
        local ready = false
        for _ = 1, 12 do
            Relay.health(function(ok)
                if ok and not ready then
                    ready = true
                    VHubNpcAI.Log.info('sidecar online')
                    -- ponte de chaves: convar server-only (config/local.cfg) → sidecar (loopback)
                    local gk  = GetConvar('GEMINI_API_KEY', '')
                    local ok2 = GetConvar('OPENAI_API_KEY', '')
                    if gk ~= '' or ok2 ~= '' then
                        Relay.pushConfig({ gemini_key = gk, openai_key = ok2 }, function(pok, pdata)
                            -- loga só o RESULTADO (nomes), NUNCA o valor da chave
                            VHubNpcAI.Log.info('chaves de IA enviadas ao sidecar: ' ..
                                (pok and json.encode(pdata.set or {}) or 'falhou'))
                        end)
                    else
                        VHubNpcAI.Log.warn('GEMINI_API_KEY ausente (convar) — LLM usará fallback')
                    end
                end
            end)
            Wait(5000)
            if ready then break end
        end
        if not ready then
            VHubNpcAI.Log.warn('sidecar offline após ~60s — confira o start_npcai.bat/porta 7513')
        end
    end)
    -- mundo é config estática (shared/config.lua) — o cliente já a possui; sem broadcast (L-15/R5)
end)

-- limpa ao parar o resource
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    _npc = {}
end)


-- ============================================================
-- LIFECYCLE DE PERSONAGEM (replay-guard — L-17)
-- ============================================================

-- abre sessão ao carregar personagem
AddEventHandler('vHub:characterLoad', function(user)
    if type(user) ~= 'table' then return end

    local src = tonumber(user.source)
    local charId = tonumber(user.char_id)
    if not src or src <= 0 or not charId or charId <= 0 then return end
    local charName = tostring(user.name or 'Jogador'):sub(1, 64)

    -- replay-guard: substitui atomicamente a sessão anterior do mesmo source
    Core.closeSession(src)
    Core.openSession(src, charId, charName)

    -- pré-aquece TTS do nome nos NPCs ativos (thinking audio agora é local via WAV pré-gerado)
    for _, npc in pairs(cfg.npcs) do
        if npc.enabled then
            Relay.prewarmName(npc.id, charName)
        end
    end
end)

-- fecha sessão ao deslogar
AddEventHandler('playerDropped', function()
    local src = source
    local s   = Core.getSession(src)
    if s then
        Mem.evict(s.charId)
        Relay.sessionEnd(s.charId)  -- descarta memória curta efêmera no sidecar
    end
    Core.closeSession(src)
    -- libera qualquer NPC reservado/ocupado por este src
    for npcId in pairs(_npc) do
        _npcRelease(npcId, src)
    end
end)


-- ============================================================
-- RESERVA DE NPC (warm handoff) — client reserva ao começar a gravar
-- ============================================================

RegisterNetEvent(E.SRV_RESERVAR)
AddEventHandler(E.SRV_RESERVAR, function(payload)
    local src = source

    local session = Core.getSession(src)
    if not session then return end
    if type(payload) ~= 'table' then return end

    -- rate ANTES de qualquer export ao HSS: sem throttle, um loop de reserva
    -- amplificaria chamadas cross-resource (L-18). Drop silencioso (não amplifica).
    if not Core.rate(src, 'reservar', cfg.rates.reservar) then return end

    local npcId = payload.npc_id
    if type(npcId) ~= 'string' or not cfg.npcs[npcId] then return end

    -- mesmos gates de segurança do falar (HSS + proximidade) antes de segurar o slot
    if not Core.canTalk(src) then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = 'nao_pode_falar' })
        return
    end
    if not Core.validateProximity(src, npcId) then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = 'longe_demais' })
        return
    end

    -- NPC ocupado por outro → nega ANTES do upload do áudio (o player para de gravar)
    if _npcBusyForOther(npcId, src) then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = 'npc_ocupado' })
        return
    end

    -- segura a reserva (não-ativa) por RESERVE_TTL
    _npc[npcId] = { src = src, active = false, ts = GetGameTimer() }
end)


-- ============================================================
-- HANDLER PRINCIPAL — SRV_FALAR
-- ============================================================

-- fingerprint barato de áudio p/ dedup (não é hash forte — só pega duplicata idêntica)
local function _audioFingerprint(audio)
    return #audio .. ':' .. audio:sub(1, 32) .. audio:sub(-32)
end

RegisterNetEvent(E.SRV_FALAR)
AddEventHandler(E.SRV_FALAR, function(payload)
    local src = source

    -- ── 1. sessão ──────────────────────────────────────────
    local session = Core.getSession(src)
    if not session then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = 'sem_sessao' })
        return
    end

    -- ── 2. rate-limit ──────────────────────────────────────
    if not Core.rate(src, 'falar', cfg.rates.falar) then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = 'rate_limit' })
        return
    end

    -- ── 3. payload shape ───────────────────────────────────
    local ok, reason = Core.validateFalarPayload(payload)
    if not ok then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = reason })
        return
    end

    local npcId = payload.npc_id

    -- ── 3.5 dedup de áudio idêntico (double-send / replay) ──
    if type(payload.audio) == 'string' then
        local fp = _audioFingerprint(payload.audio)
        if session.lastAudioFp == fp and (GetGameTimer() - (session.lastAudioTs or 0)) < 4000 then
            return  -- duplicata silenciosa: a 1ª já está sendo processada
        end
        session.lastAudioFp = fp
        session.lastAudioTs = GetGameTimer()
    end

    -- ── 4. gate HSS ────────────────────────────────────────
    if not Core.canTalk(src) then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = 'nao_pode_falar' })
        return
    end

    -- ── 5. proximidade server-side (L-01) ──────────────────
    if not Core.validateProximity(src, npcId) then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = 'longe_demais' })
        return
    end

    -- ── 6. lock de NPC (respeita reserva do próprio src) ────
    if _npcBusyForOther(npcId, src) then
        TriggerClientEvent(E.CLI_REJECT, src, { reason = 'npc_ocupado' })
        return
    end
    _npc[npcId] = { src = src, active = true, ts = GetGameTimer() }
    Core.setTalking(src, true)

    -- ── 7. carrega memória e chama sidecar ─────────────────
    local charId   = session.charId
    local charName = session.charName
    local npcCfg   = cfg.npcs[npcId]

    Mem.load(charId, npcId)
    local memSnapshot = Mem.get(charId, npcId)

    Relay.converse({
        char_id     = charId,
        char_name   = charName,
        npc_id      = npcId,
        lang        = npcCfg.idioma or 'pt',
        audio       = payload.audio,
        direct_text = payload.direct_text,
        interrupted = payload.interrupted == true or nil,
        memory      = memSnapshot,
        ai          = VHubNpcAI.resolveAI(npcId),
        meta        = { nome = npcCfg.nome, profissao = npcCfg.profissao, idioma = npcCfg.idioma },
    }, function(relayOk, data)

        -- libera locks independente do resultado
        _npcRelease(npcId, src)
        Core.setTalking(src, false)

        if not relayOk then
            local relayErr = type(data) == 'table' and tostring(data.err) or 'desconhecido'
            VHubNpcAI.Log.warn('relay falhou src=' .. src .. ' err=' .. relayErr)
            TriggerClientEvent(E.CLI_REJECT, src, {
                reason = 'sidecar_erro',
                detail = relayErr:sub(1, 64),
            })
            return
        end

        -- ── 8. aplica delta de memória ──────────────────────
        if data.memory_delta then
            Mem.applyDelta(charId, npcId, data.memory_delta)
        end

        -- ── 9. auditoria (assíncrona, não bloqueia resposta) ─
        if Core.rate(src, 'audit', cfg.rates.audit) then
            S.audit(charId, npcId, data.intent, data.stage, data.stt_text)
        end

        -- ── 10. resposta ao cliente ─────────────────────────
        -- posição 3D do NPC como primitivo (L-19: não vec3 no payload)
        local nc = npcCfg.coords
        TriggerClientEvent(E.CLI_RESPOSTA, src, {
            npc_id    = npcId,
            npc_nome  = npcCfg.nome,
            intent    = data.intent  or 'unknown',
            stage     = data.stage   or 'cache',
            text      = data.text    or '',
            audio_b64 = data.audio_b64,
            npc_x     = nc.x,
            npc_y     = nc.y,
            npc_z     = nc.z,
        })
    end)
end)


-- ============================================================
-- HANDLER DE CANCELAMENTO
-- ============================================================

RegisterNetEvent(E.SRV_CANCEL)
AddEventHandler(E.SRV_CANCEL, function()
    local src = source
    -- libera qualquer NPC reservado/ocupado por este src (a resposta em voo é descartada)
    for npcId in pairs(_npc) do
        _npcRelease(npcId, src)
    end
    Core.setTalking(src, false)
end)
