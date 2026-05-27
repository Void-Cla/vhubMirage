-- client/hud.lua — HUD cinematografica de corrida (sem conflito com velocimetro).
-- Layout conforme roadmap:
--   Topo central     : timer principal (grande, dourado)
--   Logo abaixo      : recorde pessoal (menor)
--   Direita superior : POSICAO 1/5
--   Esquerda superior: VOLTA 2/3
--   Esquerda inferior: PROXIMO CP 1.24 KM
--
-- SEM fundo opaco, SEM caixa pesada — apenas DrawText com outline + sombra dourada.
-- Render condicional: so quando ha corrida ativa em estado 'racing'.

local Cfg  = VHubRachaCfg
local U    = VHubRachaUtils
local Lang = VHubRachaLang
local L    = VHubRachaLocal
local MA   = VHubRachaMath

local C = Cfg.HUD or {}

-- If the HTML/CSS NUI is active, disable this Lua DrawText HUD.
-- The `client/nui_bridge.lua` will forward statebag/telemetry to the NUI.
if C.USE_NUI then return end

-- ── Helpers de desenho (sem fundo opaco) ───────────────────────────────────

local function draw_text(x, y, txt, scale, r, g, b, a, font, centre)
  SetTextFont(font or 7)
  SetTextScale(0.0, scale or 0.5)
  SetTextColour(r or 255, g or 255, b or 255, a or 235)
  SetTextOutline()
  SetTextDropShadow()
  SetTextEntry('STRING')
  AddTextComponentString(tostring(txt))
  if centre then SetTextCentre(true) end
  DrawText(x, y)
end

-- Calcula distancia 2D em metros do player ao proximo CP
local function next_cp_distance_m(active)
  if not active or not active.track or not active.track.checkpoints then return nil end
  local cps = active.track.checkpoints
  if #cps == 0 then return nil end
  local idx = ((active.cp_index - 1) % #cps) + 1
  local cp = cps[idx]; if not cp then return nil end

  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  return MA.cp_distance_m(pos.x, pos.y, cp)
end

-- ── Loop principal do HUD ──────────────────────────────────────────────────

CreateThread(function()
  while true do
    local active = VHubRachaLocal.active_race()
    if not active or not active.started_ms or active.started_ms == 0
       or active.finished or active.aborted then
      Wait(400)
    else
      Wait(0)
      local now      = GetGameTimer()
      local elapsed  = now - active.started_ms
      local bag      = L.bag or {}
      local kind     = active.track and active.track.kind or 'sprint'
      local laps     = active.laps or 1
      local cp_done  = bag.cp_done or 0
      local cp_total = active.cp_total or 0

      local gold = C.GOLD or { r = 243, g = 181, b = 58 }
      local sand = C.SAND or { r = 217, g = 193, b = 154 }

      -- ── Timer central (topo). Fallbacks: use bag.started_ms quando
      -- cliente pode nao ter setado active.started_ms por causa de race
      local started = active.started_ms and active.started_ms > 0 and active.started_ms or (bag.started_ms or 0)
      local elapsed_local = 0
      if started and started > 0 then elapsed_local = now - started end
      draw_text(C.TIMER_X or 0.50, C.TIMER_Y or 0.04,
        U.time_short_ms(elapsed_local),
        C.TIMER_SCALE or 0.72,
        gold.r, gold.g, gold.b, 245, 7, true)

      -- Recorde pessoal logo abaixo (se houver)
      if active.record_ms and active.record_ms > 0 then
        draw_text(C.RECORD_X or 0.50, C.RECORD_Y or 0.082,
          Lang.t('race.record') .. ' ' .. U.time_short_ms(active.record_ms),
          C.RECORD_SCALE or 0.38,
          sand.r, sand.g, sand.b, 210, 4, true)
      end

      -- Badge "MODO TREINO" (se for treino)
      if (active.mode or bag.mode) == 'treino' then
        draw_text(0.50, 0.115,
          Lang.t('lobby.training_badge'),
          0.32,
          255, 154, 31, 235, 4, true)
      end

      -- ── Direita superior: posicao ────────────────────────────────────────
      local pos    = bag.placement or 0
      local total  = active.players_total or 0
      local pos_lbl
      if total > 0 and pos > 0 then
        pos_lbl = Lang.t('race.position_x_of_y', { pos, total })
      else
        pos_lbl = '— / —'
      end
      -- Label "POSICAO" pequeno
      draw_text(C.POS_X or 0.97, (C.POS_Y or 0.04) - 0.018,
        Lang.t('race.position'), 0.30,
        sand.r, sand.g, sand.b, 200, 4, false)
      -- Numero grande
      SetTextFont(7); SetTextScale(0.0, C.POS_SCALE or 0.60)
      SetTextColour(gold.r, gold.g, gold.b, 240); SetTextOutline(); SetTextDropShadow()
      SetTextEntry('STRING'); AddTextComponentString(pos_lbl)
      SetTextJustification(2)   -- 2 = right-justify
      SetTextWrap(0.0, C.POS_X or 0.97)
      DrawText(0.0, (C.POS_Y or 0.04) + 0.002)

      -- ── Esquerda superior: volta (so circuito) ───────────────────────────
      if kind == 'circuit' and laps > 1 then
        draw_text(C.LAP_X or 0.03, (C.LAP_Y or 0.04) - 0.018,
          Lang.t('race.lap'), 0.30,
          sand.r, sand.g, sand.b, 200, 4, false)
        local lap = math.max(1, math.min(laps, bag.lap or 1))
        local lap_lbl = Lang.t('race.lap_x_of_y', { lap, laps })
        draw_text(C.LAP_X or 0.03, (C.LAP_Y or 0.04) + 0.002,
          lap_lbl, C.LAP_SCALE or 0.60,
          gold.r, gold.g, gold.b, 240, 7, false)
      end

      -- ── Proximo CP (moved to top-left). Se o cliente nao tiver active,
      -- usa bag para calcular distancia/indice.
      if cp_total > 0 and cp_done < cp_total then
        local dist = next_cp_distance_m(active) or next_cp_distance_m({ track = bag.track, cp_index = bag.cp_index, cp_total = bag.cp_total })
        if dist then
          draw_text(C.NEXT_X or 0.03, (C.NEXT_Y or 0.04) - 0.020,
            Lang.t('race.next_cp'), 0.30,
            sand.r, sand.g, sand.b, 220, 4, false)
          local dist_lbl
          if dist >= 1000 then
            dist_lbl = Lang.t('race.cp_distance_km', { dist / 1000 })
          else
            dist_lbl = Lang.t('race.cp_distance_m', { math.floor(dist) })
          end
          draw_text(C.NEXT_X or 0.03, C.NEXT_Y or 0.04,
            dist_lbl, C.NEXT_SCALE or 0.50,
            gold.r, gold.g, gold.b, 240, 7, false)
        end
        -- CP atual / total como meta inferior pequena
        draw_text(C.NEXT_X or 0.03, (C.NEXT_Y or 0.04) + 0.028,
          ('CP %d/%d'):format(cp_done + 1, cp_total), 0.28,
          sand.r, sand.g, sand.b, 200, 4, false)
      end

      -- ── Drift score (modo drift) ─────────────────────────────────────────
      if kind == 'drift' then
        local drift = active.drift_score or bag.drift_score or 0
        -- canto direito inferior (acima do velocimetro padrao)
        draw_text(0.97, 0.85,
          'DRIFT', 0.30, sand.r, sand.g, sand.b, 220, 4, false)
        SetTextFont(7); SetTextScale(0.0, 0.60)
        SetTextColour(255, 213, 115, 240); SetTextOutline(); SetTextDropShadow()
        SetTextEntry('STRING'); AddTextComponentString(U.fmt_num(drift))
        SetTextJustification(2); SetTextWrap(0.0, 0.97)
        DrawText(0.0, 0.87)
        if active.drift_combo and active.drift_combo > 1.0 then
          draw_text(0.97, 0.92,
            ('x%.1f'):format(active.drift_combo),
            0.40, 255, 100, 100, 240, 7, false)
          SetTextJustification(2); SetTextWrap(0.0, 0.97)
        end
      end
    end
  end
end)
