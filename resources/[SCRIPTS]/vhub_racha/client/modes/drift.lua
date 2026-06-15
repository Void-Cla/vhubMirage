-- client/modes/drift.lua — BANCO da pontuacao de drift.
--
-- A mecanica + a fabricacao da pontuacao bruta vivem no resource "Drift"
-- (exports.Drift:getTelemetry). Aqui aplicamos a regra de BANCO:
--   • pontos do drift atual ficam "pendentes" (em risco);
--   • a cada BANK_MS sem bater, o lote pendente vira pontuacao VALIDA (bancada);
--   • bater (impacto) descarta o lote pendente — o ja bancado permanece.
--
-- active.drift_score = bancado (enviado ao server por sync.lua — o VALIDO).
-- active.drift_live  = bancado + pendente (so para o HUD; cai ao bater).

VHubRachaModes = VHubRachaModes or {}
local Cfg = VHubRachaCfg

local BANK_MS = (Cfg.DRIFT and Cfg.DRIFT.BANK_MS) or 5000


-- ============================================================
-- TELEMETRIA DO RESOURCE "Drift"
-- ============================================================

-- snapshot nil-safe; degrada sem pontuar se o resource "Drift" nao estiver ativo.
local function drift_telemetry()
  if not exports.Drift then return nil end
  local ok, snap = pcall(function() return exports.Drift:getTelemetry() end)
  if not ok or type(snap) ~= 'table' then return nil end
  return snap
end


-- ============================================================
-- LIFECYCLE
-- ============================================================

VHubRachaModes.drift = {
  id = 'drift',

  -- prepara o estado de banco no inicio da corrida (grid).
  start = function(active)
    active.drift_score   = 0      -- bancado (pontuacao valida)
    active.drift_live    = 0      -- bancado + pendente (HUD)
    active.drift_combo   = 1.0
    active._pending      = 0      -- lote em risco (zera ao bater)
    active._window_ms    = 0      -- tempo acumulado no lote atual
    active._last_total   = nil    -- baseline do total monotonico do Drift
    active._last_crashes = nil
  end,

  on_start = function(_a) end,
  on_checkpoint = function(_a, _i) end,

  -- chegada limpa: banca o lote pendente (o player nao bateu, entao mantem).
  on_finish = function(active, _p)
    if not active then return end
    active.drift_score = (active.drift_score or 0) + math.floor(active._pending or 0)
    active._pending    = 0
    active.drift_live  = active.drift_score
  end,
}


-- ============================================================
-- BANK LOOP — consome o Drift e banca a cada BANK_MS sem bater
-- ============================================================

CreateThread(function()
  local last_t = GetGameTimer()
  while true do
    local active = VHubRachaLocal and VHubRachaLocal.active_race and VHubRachaLocal.active_race() or nil
    if not active or active.track.kind ~= 'drift'
       or active.aborted or active.finished or active.started_ms == 0 then
      Wait(250)
      last_t = GetGameTimer()
    else
      Wait(100)   -- 10Hz: suficiente p/ o banco; o server faz o cap fino por segundo.
      local now = GetGameTimer()
      local dt = now - last_t
      last_t = now
      if dt < 1 then dt = 100 end

      local snap = drift_telemetry()
      if snap then
        -- baseline na 1a leitura (ignora pontos fabricados antes da corrida).
        if active._last_total == nil then
          active._last_total   = snap.total   or 0
          active._last_crashes = snap.crashes or 0
        end

        local d_total = (snap.total   or 0) - active._last_total
        local crashed = (snap.crashes or 0) ~= active._last_crashes
        active._last_total   = snap.total   or 0
        active._last_crashes = snap.crashes or 0

        if crashed then
          -- bateu: perde o lote pendente; o bancado permanece.
          active._pending   = 0
          active._window_ms = 0
        elseif d_total > 0 then
          active._pending = (active._pending or 0) + d_total
        end

        -- janela de banco: lote sobrevive BANK_MS sem bater → vira valido.
        if (active._pending or 0) > 0 then
          active._window_ms = (active._window_ms or 0) + dt
          if active._window_ms >= BANK_MS then
            active.drift_score = (active.drift_score or 0) + math.floor(active._pending)
            active._pending   = 0
            active._window_ms = 0
          end
        end

        active.drift_combo = snap.combo or active.drift_combo or 1.0
        active.drift_live  = (active.drift_score or 0) + math.floor(active._pending or 0)
      end
    end
  end
end)
