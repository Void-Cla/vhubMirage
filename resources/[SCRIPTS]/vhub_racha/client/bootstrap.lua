---@diagnostic disable: undefined-global, lowercase-global

-- client/bootstrap.lua — handshake cliente do vhub_racha.
--
-- Modulos client registram callbacks via VHubRachaBoot.on_ready(fn) para
-- rodarem so apos o vhub core estar disponivel + autenticacao do personagem.
--
-- TRES caminhos determinísticos para chegar a READY (ordem natural):
--   (1) Evento oficial `vHub:initDone` chega normalmente.
--   (2) State Bag `LocalPlayer.state.vhub_pronto == true` (cobre o caso de
--       o cliente registrar o listener APOS o servidor ter emitido).
--   (3) Re-emissao explicita: pedimos UMA vez 200ms apos o boot.
--
-- Sem polling de 60s, sem retry triplicado. O primeiro caminho que resolver
-- libera os callbacks; os demais viram noop graças ao guard `if B.READY`.


VHubRachaBoot = {
    READY     = false,
    user_id   = nil,
    char_id   = nil,
    start_ms  = GetGameTimer(),
    ready_at  = 0,
    _queue    = {},
}
local B = VHubRachaBoot
local E = VHubRachaE   -- enums (incl. REQUEST_INIT_DONE)


-- ============================================================
-- API PUBLICA
-- ============================================================

-- Registra callback que sera executado quando o boot terminar.
-- Se ja estiver pronto, executa imediato (mesma semantica de fila).
function B.on_ready(fn, name)
    if type(fn) ~= 'function' then return end

    if B.READY then
        local ok, err = pcall(fn)
        if not ok then
            print(('[vhub_racha][client] callback %s erro: %s')
                :format(tostring(name or '?'), tostring(err)))
        end
        return
    end

    B._queue[#B._queue + 1] = { fn = fn, name = name or '?' }
end


-- ============================================================
-- INTERNAL — dispara fila uma unica vez
-- ============================================================

local function _emit_ready()
    if B.READY then return end
    B.READY    = true
    B.ready_at = GetGameTimer()

    print(('[vhub_racha][client] pronto em %dms (rodando %d callbacks)')
        :format(B.ready_at - B.start_ms, #B._queue))

    for _, entry in ipairs(B._queue) do
        local ok, err = pcall(entry.fn)
        if not ok then
            print(('[vhub_racha][client] %s erro: %s')
                :format(entry.name, tostring(err)))
        end
    end

    B._queue = {}
    TriggerEvent('vhub_racha:boot:ready')
end


-- ============================================================
-- CAMINHO 1 — evento oficial vHub:initDone
-- ============================================================

RegisterNetEvent('vHub:initDone')
AddEventHandler('vHub:initDone', function(user_id, char_id)
    B.user_id = tonumber(user_id)
    B.char_id = tonumber(char_id)
    _emit_ready()
end)


-- ============================================================
-- CAMINHO 2 — State Bag (sinal redundante via vhub_pronto)
-- ============================================================

CreateThread(function()
    -- Janela curta: 30s no maximo, checando a cada 250ms.
    -- E se nada chegar em 30s, ainda nao bloqueia o jogo — apenas loga.
    for _ = 1, 120 do
        if B.READY then return end

        local sb = LocalPlayer and LocalPlayer.state
        if sb and sb.vhub_pronto == true then
            B.user_id = tonumber(sb.vhub_uid) or B.user_id
            B.char_id = tonumber(sb.vhub_char_id) or B.char_id
            _emit_ready()
            return
        end

        Wait(250)
    end

    if not B.READY then
        print('[vhub_racha][client] vhub indisponivel apos 30s — boot ficou na fila.')
    end
end)


-- ============================================================
-- CAMINHO 3 — solicita re-emissao UMA vez (cobre listener tardio)
-- ============================================================

CreateThread(function()
    Wait(200)
    if not B.READY then
        TriggerServerEvent(E.REQUEST_INIT_DONE)
    end
end)


-- ============================================================
-- SHUTDOWN
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    B.READY = false
end)
