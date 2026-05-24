-- client/editor.lua — editor visual de pistas (hibrido: NUI inicia, in-game captura).
-- Fluxo:
--   1) Jogador abre /racha → vai na aba 'Editor' → clica 'Iniciar' (NUI envia editor_open)
--   2) Server cria draft → manda editor_opened com phase='grid'
--   3) Cliente NUI passa para tela contextual em-corrida (overlay sem bg.png)
--   4) Fase GRID: jogador estaciona, aperta E (ou buzina) → server captura posicao
--   5) NUI envia editor_phase para CPS → jogador dirige, aperta E em cada CP
--   6) NUI envia editor_phase para META → preenche metadados → save
--
-- Overlays in-game: hint contextual + render dos CPs/grid ja salvos.

local Cfg  = VHubRachaCfg
local E    = VHubRachaE
local Lang = VHubRachaLang
local V    = VHubRachaVeh
local L    = VHubRachaLocal

-- ── Estado local do editor ────────────────────────────────────────────────

local function draft() return L.editor_draft end

local function in_phase(phase)
  local d = draft()
  return d and d.phase == phase
end

-- ── Helpers de input ──────────────────────────────────────────────────────

-- E = control 38 (input nativo "PICKUP/CONTEXT")
-- T = control 245 (chat) → conflito; usamos H = horn (86) ou MULTIPLAYER_INFO (20)
-- G = control 47 (vehicle horn alt?) → simplicidade: usamos H para "next phase" (control 74 = headlight, neutro)
-- Por seguranca: nao usa controls que conflitam com chat/dialog.

-- ── Render overlay (CPs + grid salvos) ────────────────────────────────────

CreateThread(function()
  while true do
    local d = draft()
    if not L.open_editor or not d then
      Wait(800)
    else
      Wait(0)

      -- CPs em laranja claro
      for i, cp in ipairs(d.checkpoints or {}) do
        DrawMarker(28,
          cp.x, cp.y, cp.z + 2.0,
          0, 0, 0, 0, 0, 0,
          1.4, 1.4, 4.0,
          255, 154, 31, 130,
          false, false, 2, false, nil, nil, false)
        DrawMarker(1,
          cp.x, cp.y, cp.z - 1.0,
          0, 0, 0, 0, 0, 0,
          (cp.radius or 11.0) * 1.4, (cp.radius or 11.0) * 1.4, 1.5,
          255, 154, 31, 100,
          false, false, 2, false, nil, nil, false)
        local on_screen, sx, sy = GetScreenCoordFromWorldCoord(cp.x, cp.y, cp.z + 2.5)
        if on_screen then
          SetTextFont(7); SetTextScale(0.0, 0.5)
          SetTextColour(255, 154, 31, 240); SetTextOutline()
          SetTextEntry('STRING'); AddTextComponentString('CP ' .. i)
          SetTextCentre(true); DrawText(sx, sy)
        end
      end

      -- Grid em verde
      for i, g in ipairs(d.grid or {}) do
        DrawMarker(1,
          g.x, g.y, g.z - 1.0,
          0, 0, 0, 0, 0, 0,
          3.0, 3.0, 1.5,
          80, 220, 100, 140,
          false, false, 2, false, nil, nil, false)
        local on_screen, sx, sy = GetScreenCoordFromWorldCoord(g.x, g.y, g.z + 1.5)
        if on_screen then
          SetTextFont(7); SetTextScale(0.0, 0.45)
          SetTextColour(80, 220, 100, 240); SetTextOutline()
          SetTextEntry('STRING'); AddTextComponentString('GRID ' .. i)
          SetTextCentre(true); DrawText(sx, sy)
        end
      end

      -- Banner de fase (texto contextual no topo)
      local label, help, color
      if d.phase == 'grid' then
        label = Lang.t('editor.phase_grid')
        help  = Lang.t('editor.phase_grid_help')
        color = { 80, 220, 100 }
      elseif d.phase == 'cps' then
        label = Lang.t('editor.phase_cps')
        help  = Lang.t('editor.phase_cps_help')
        color = { 255, 154, 31 }
      elseif d.phase == 'meta' then
        label = Lang.t('editor.phase_meta')
        help  = ''
        color = { 243, 181, 58 }
      else
        label = Lang.t('editor.welcome')
        help  = ''
        color = { 243, 181, 58 }
      end

      SetTextFont(7); SetTextScale(0.0, 0.62)
      SetTextColour(color[1], color[2], color[3], 245); SetTextOutline(); SetTextDropShadow()
      SetTextEntry('STRING'); AddTextComponentString(label)
      SetTextCentre(true); DrawText(0.5, 0.04)

      if help ~= '' then
        SetTextFont(4); SetTextScale(0.0, 0.38)
        SetTextColour(217, 193, 154, 220); SetTextOutline()
        SetTextEntry('STRING'); AddTextComponentString(help)
        SetTextCentre(true); DrawText(0.5, 0.085)
      end

      -- Contadores
      SetTextFont(4); SetTextScale(0.0, 0.36)
      SetTextColour(217, 193, 154, 220); SetTextOutline()
      SetTextEntry('STRING')
      AddTextComponentString(('Slots: %d / %d   CPs: %d / %d')
        :format(#(d.grid or {}), Cfg.EDITOR_MAX_GRID or 12,
                #(d.checkpoints or {}), Cfg.EDITOR_MAX_CPS or 80))
      SetTextCentre(true); DrawText(0.5, 0.116)

      -- ── Input: depende da fase ──────────────────────────────────────────
      -- E = adicionar (38)
      -- Buzina = adicionar (86) — atalho extra no veiculo
      -- H = headlight (74) → usado pra "remover ultimo CP" (so na fase CPS, evita conflito)
      -- G = vehicle horn alt (47) → "proxima fase"
      local ped = PlayerPedId()
      local _, veh = V.is_driver(ped)

      if d.phase == 'grid' then
        -- E ou buzina → adicionar slot
        if IsControlJustReleased(0, 38) or
           (veh ~= 0 and IsControlJustPressed(0, 86)) then
          TriggerServerEvent(E.EDITOR_ADD_GRID)
        end
        -- G → proxima fase (cps)
        if IsControlJustReleased(0, 47) then
          TriggerServerEvent(E.EDITOR_PHASE, { phase = 'cps' })
        end
      elseif d.phase == 'cps' then
        if IsControlJustReleased(0, 38) then
          TriggerServerEvent(E.EDITOR_ADD_CP)
        end
        if IsControlJustReleased(0, 74) then
          TriggerServerEvent(E.EDITOR_UNDO)
        end
        if IsControlJustReleased(0, 47) then
          TriggerServerEvent(E.EDITOR_PHASE, { phase = 'meta' })
        end
      end
    end
  end
end)

-- ── Limpeza ──────────────────────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  L.open_editor = false
  L.editor_draft = nil
end)
