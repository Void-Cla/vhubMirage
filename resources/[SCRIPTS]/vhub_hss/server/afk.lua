-- server/afk.lua — detecção de inatividade AFK; kick em 30 min (budget: 1 Hz, O(N))
---@diagnostic disable: undefined-global

local E = VHubHSS.E

local AFK_TIMEOUT_MS = 30 * 60 * 1000   -- 30 min
local AFK_WARN_MS    = 29 * 60 * 1000   -- aviso em 29 min
local BEAT_THROTTLE  = 4000              -- mínimo entre heartbeats aceitos (anti-spam)

local lastBeat = {}
local warned   = {}


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- inicia rastreio somente após spawn autoritativo (evita kick em tela de criação)
AddEventHandler(E.CHARACTER_LOAD, function()
    local src = source
    lastBeat[src] = GetGameTimer()
    warned[src]   = false
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastBeat[src] = nil
    warned[src]   = nil
end)


-- ============================================================
-- HEARTBEAT
-- ============================================================

-- recebe sinal de atividade do cliente; throttle server-side anti-flood
local function onHeartbeat(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end
    if not lastBeat[src] then return end  -- ignora jogador pré-spawn

    local now = GetGameTimer()
    if (now - lastBeat[src]) < BEAT_THROTTLE then return end

    lastBeat[src] = now
    warned[src]   = false  -- reseta aviso ao detectar atividade
end

RegisterNetEvent(E.AFK_HEARTBEAT)
AddEventHandler(E.AFK_HEARTBEAT, onHeartbeat)


-- ============================================================
-- LOOP DE VERIFICAÇÃO
-- ============================================================

-- budget: 1 Hz — O(N) total, O(1) por player (hash lookup)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        local now = GetGameTimer()
        for _, pid in ipairs(GetPlayers()) do
            local pidN = tonumber(pid)
            if lastBeat[pidN] then
                local elapsed = now - lastBeat[pidN]
                if elapsed >= AFK_TIMEOUT_MS then
                    DropPlayer(pidN, 'AFK: desconectado por inatividade (30 min).')
                elseif elapsed >= AFK_WARN_MS and not warned[pidN] then
                    warned[pidN] = true
                    TriggerClientEvent(E.NOTIFY, pidN, {
                        type    = 'warning',
                        message = 'Você será desconectado por inatividade em 1 minuto.',
                    })
                end
            end
        end
    end
end)
