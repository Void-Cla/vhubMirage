---@diagnostic disable: undefined-global, param-type-mismatch
-- world.lua — controle de densidade do mundo GTA (mundo vazio, trânsito mínimo)
-- Só as densidades *ThisFrame precisam rodar por frame (não têm API de "setar uma vez").
-- Os demais (barco/trem/lixo/despacho/procurado) são SETTERS DE ESTADO: aplicados
-- uma única vez na transição liga/desliga (perf gate — fora do hot path).

local cfg = VHubNpcAI.cfg

local _applied = false  -- setters de estado já aplicados no estado atual?


-- ============================================================
-- SETTERS DE ESTADO (uma vez por transição, não por frame)
-- ============================================================

-- aplica os controles de estado do mundo (chamado ao ATIVAR)
local function _applyWorldState(w)
    SetRandomBoats(w.boats == true)
    SetRandomTrains(w.trains == true)
    SetGarbageTrucks(w.garbage_trucks == true)
    SetDispatchCopsForPlayer(PlayerId(), w.emergency_dispatch == true)
    SetMaxWantedLevel(w.max_wanted or 0)
end

-- restaura o mundo ao padrão do GTA (chamado ao DESATIVAR)
local function _restoreWorldState()
    SetRandomBoats(true)
    SetRandomTrains(true)
    SetGarbageTrucks(true)
    SetDispatchCopsForPlayer(PlayerId(), true)
    SetMaxWantedLevel(5)
end


-- ============================================================
-- LOOP — só densidades *ThisFrame por frame (L-18 exceção documentada)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        local w = cfg.world
        if cfg.enabled and w.enabled then
            if not _applied then
                _applyWorldState(w)
                _applied = true
            end
            SetPedDensityMultiplierThisFrame(w.peds + 0.0)
            SetScenarioPedDensityMultiplierThisFrame(w.scenario_peds + 0.0, w.scenario_peds + 0.0)
            SetVehicleDensityMultiplierThisFrame(w.traffic + 0.0)
            SetRandomVehicleDensityMultiplierThisFrame(w.random_traffic + 0.0)
            SetParkedVehicleDensityMultiplierThisFrame(w.parked + 0.0)
            Wait(w.loop_wait or 0)
        else
            if _applied then
                _restoreWorldState()
                _applied = false
            end
            Wait(1000)
        end
    end
end)


-- ============================================================
-- COMANDO ADMIN — liga/desliga densidade em runtime (local)
-- ============================================================

-- /npcai_world [on|off] — alterna o controle de mundo localmente (admin)
RegisterCommand('npcai_world', function(_, args)
    if not IsPlayerAceAllowed(PlayerId(), 'vhub.admin') then return end
    local a = tostring(args[1] or ''):lower()
    cfg.world.enabled = not (a == '0' or a == 'off' or a == 'false')
    -- força reaplicar setters de estado na próxima iteração (config pode ter mudado)
    _applied = false
    VHubNpcAI.Log.info('world density ' .. (cfg.world.enabled and 'ON' or 'OFF'))
end, false)
