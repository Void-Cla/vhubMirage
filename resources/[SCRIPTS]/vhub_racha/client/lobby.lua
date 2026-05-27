-- client/lobby.lua — ready zone visual + confirmacao de presenca.
-- DrawMarker no mundo (sempre) + thread NUI que projeta coords de tela.
-- FIX: USE_NUI agora recebe projeção contínua → overlay HTML/CSS funciona.

local Cfg  = VHubRachaCfg
local E    = VHubRachaE
local Lang = VHubRachaLang
local MA   = VHubRachaMath
local U    = VHubRachaUtils
local L    = VHubRachaLocal

local USE_NUI = Cfg and Cfg.HUD and Cfg.HUD.USE_NUI

-- ── Recebe estado pending do servidor ──────────────────────────────────────

RegisterNetEvent(E.LOBBY_PENDING, function(data)
  if type(data) ~= 'table' then return end
  VHubRachaLocal.set_pending({
    inst_id          = data.inst_id,
    ready_zone       = data.ready_zone,
    pending_deadline = data.pending_deadline,
    mode             = data.mode,
    track_label      = data.track_label,
  })

  -- Notifica via feed nativo
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(Lang.t('lobby.confirm_presence'))
  EndTextCommandThefeedPostTicker(false, true)

  -- Tempo restante (feed imediato)
  if data.pending_deadline and tonumber(data.pending_deadline) and data.pending_deadline > 0 then
    local remaining = math.max(0, (data.pending_deadline or 0) - GetGameTimer())
    local label = ('Tempo p/ confirmar: %s'):format(
      (U and U.time_short_ms) and U.time_short_ms(remaining) or (math.ceil(remaining/1000) .. 's'))
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandThefeedPostTicker(false, true)
  end

  -- Blip no mapa
  if data.ready_zone then
    if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
      RemoveBlip(VHubRachaLocal._pending_blip)
    end
    local b = AddBlipForCoord(data.ready_zone.x, data.ready_zone.y, data.ready_zone.z)
    SetBlipSprite(b, 38)
    SetBlipColour(b, 5)
    SetBlipScale(b, 1.0)
    SetBlipRoute(b, true)
    SetBlipRouteColour(b, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(
      Lang.t('brand.title') .. ' — ' .. (data.track_label or 'Largada'))
    EndTextCommandSetBlipName(b)
    VHubRachaLocal._pending_blip = b
  end

  -- Notifica NUI: mostra overlay de ready zone
  if USE_NUI then
    SendNUIMessage({ type = 'vhub_racha.lobby.pending', data = data })
  end
end)

RegisterNetEvent(E.LOBBY_CONFIRMED, function(_data)
  if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
    RemoveBlip(VHubRachaLocal._pending_blip)
    VHubRachaLocal._pending_blip = nil
  end
  VHubRachaLocal.confirmed = true
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(
    Lang.t('lobby.confirmed_notify') or 'Presença confirmada — aguarde o início.')
  EndTextCommandThefeedPostTicker(false, true)
  if USE_NUI then
    SendNUIMessage({ type = 'vhub_racha.lobby.confirmed', data = _data or {} })
  end
end)

-- ── Helpers ────────────────────────────────────────────────────────────────

local function is_inside(zone)
  if not zone then return false end
  local pos = GetEntityCoords(PlayerPedId())
  if math.abs(pos.z - zone.z) > (zone.z_tol or 5.0) then return false end
  return MA.point_in_circle(pos.x, pos.y, zone.x, zone.y, zone.radius or 18.0)
end

-- ── Thread render DrawMarker (sempre ativa, independente de NUI) ───────────

CreateThread(function()
  while true do
    local pending = L.pending
    if not pending or not pending.ready_zone then
      Wait(500)
    else
      local zone = pending.ready_zone
      local pos  = GetEntityCoords(PlayerPedId())
      local d2   = MA.dist2_xy(pos.x, pos.y, zone.x, zone.y)
      local far  = d2 > (300 * 300)

      if far then
        Wait(800)
      else
        Wait(0)

        -- Cronômetro de deadline
        if pending.pending_deadline and not L.confirmed then
          local remaining = math.max(0, pending.pending_deadline - GetGameTimer())
          local label = ('%s: %s'):format('Tempo p/ confirmar',
            (U and U.time_short_ms) and U.time_short_ms(remaining)
            or (math.ceil(remaining/1000) .. 's'))
          SetTextFont(7); SetTextScale(0.0, 0.44)
          SetTextColour(255, 255, 255, 240); SetTextOutline(); SetTextDropShadow()
          SetTextEntry('STRING'); AddTextComponentString(label)
          SetTextCentre(false); DrawText(0.03, 0.02)
        end

        local cfg = Cfg.READY_ZONE.GLOW_COLOR or { r = 243, g = 181, b = 58, a = 90 }
        local r   = zone.radius or 18.0

        -- Disco no chão
        DrawMarker(1,
          zone.x, zone.y, zone.z - 1.0,
          0,0,0, 0,0,0,
          r * 2.0, r * 2.0, 0.8,
          cfg.r, cfg.g, cfg.b, cfg.a or 90,
          false, false, 2, false, nil, nil, false)

        -- Cilindro etéreo
        DrawMarker(28,
          zone.x, zone.y, zone.z + 1.5,
          0,0,0, 0,0,0,
          r * 1.8, r * 1.8, Cfg.READY_ZONE.GLOW_HEIGHT or 4.0,
          cfg.r, cfg.g, cfg.b, 50,
          false, false, 2, false, nil, nil, false)

        -- Hint in-world
        if not L.confirmed and is_inside(zone) then
          local on_screen, sx, sy = GetScreenCoordFromWorldCoord(zone.x, zone.y, zone.z + 2.0)
          if on_screen then
            SetTextFont(7); SetTextScale(0.0, 0.55)
            SetTextColour(255, 255, 255, 240); SetTextOutline(); SetTextDropShadow()
            SetTextEntry('STRING')
            AddTextComponentString(Lang.t('lobby.press_e_confirm'))
            SetTextCentre(true); DrawText(sx, sy)
          end
          if IsControlJustReleased(0, 38) then
            VHubRachaLocal.confirmed = true
            TriggerServerEvent(E.LOBBY_CONFIRM, pending.inst_id)
          end
        elseif L.confirmed then
          local on_screen, sx, sy = GetScreenCoordFromWorldCoord(zone.x, zone.y, zone.z + 2.0)
          if on_screen then
            SetTextFont(7); SetTextScale(0.0, 0.50)
            SetTextColour(100, 220, 120, 235); SetTextOutline(); SetTextDropShadow()
            SetTextEntry('STRING')
            AddTextComponentString(Lang.t('lobby.confirmed') .. ' ✓')
            SetTextCentre(true); DrawText(sx, sy)
          end
        end

        -- Partículas suaves ao redor da zona
        if not L.confirmed then
          local N = 12
          local t = GetGameTimer() / 1000.0
          for i = 1, N do
            local angle = (i / N) * (math.pi * 2) + (t * 0.6)
            local rr = (r * 0.5) + math.sin(t + i) * (r * 0.12)
            local px = zone.x + math.cos(angle) * rr
            local py = zone.y + math.sin(angle) * rr
            local pz = zone.z + 0.2 + (math.sin(t * 1.3 + i) * 0.08)
            DrawMarker(1, px, py, pz, 0,0,0, 0,0,0,
              0.12, 0.12, 0.12, cfg.r, cfg.g, cfg.b, 60,
              false, false, 2, false, nil, nil, false)
          end
        end
      end
    end
  end
end)

-- ── Thread NUI: projeta ready zone → overlay HTML/CSS ─────────────────────
-- FIX PRINCIPAL: envia vhub_racha.readyzone.project a 20Hz.
-- O app.js posiciona o elemento anchor na tela e atualiza distância/countdown.

if USE_NUI then
  CreateThread(function()
    while true do
      local pending = L.pending
      if not pending or not pending.ready_zone then
        Wait(200)
      else
        Wait(50)   -- 20Hz
        local zone = pending.ready_zone
        local ped  = PlayerPedId()
        local pos  = GetEntityCoords(ped)

        local dx   = pos.x - zone.x
        local dy   = pos.y - zone.y
        local dz   = pos.z - zone.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        -- Projeta centro da zona (ligeiramente acima do chão) na tela
        local on_screen, sx, sy = GetScreenCoordFromWorldCoord(zone.x, zone.y, zone.z + 3.0)

        local inside = MA.point_in_circle(pos.x, pos.y, zone.x, zone.y, zone.radius or 18.0)
        local deadline   = pending.pending_deadline or 0
        local remaining_ms = math.max(0, deadline - GetGameTimer())

        local dist_label
        if dist >= 1000.0 then
          dist_label = ('%.1f KM'):format(dist / 1000.0)
        else
          dist_label = ('%d M'):format(math.floor(dist))
        end

        SendNUIMessage({
          type    = 'vhub_racha.readyzone.project',
          payload = {
            visible      = (on_screen == true),
            x            = sx or 0.0,
            y            = sy or 0.0,
            dist         = math.floor(dist),
            dist_label   = dist_label,
            inside       = inside,
            confirmed    = L.confirmed == true,
            remaining_ms = remaining_ms,
            track_label  = pending.track_label or 'LARGADA',
            mode         = pending.mode or 'rankeada',
          }
        })
      end
    end
  end)
end

-- ── Tecla E (fallback: confirma mesmo sem a ready zone visível) ───────────

CreateThread(function()
  local last_press_ms = 0
  while true do
    local pending = L.pending
    if pending and not L.confirmed and pending.inst_id then
      Wait(0)
      if IsControlJustReleased(0, 38) and (GetGameTimer() - last_press_ms) > 800 then
        last_press_ms = GetGameTimer()
        TriggerServerEvent(E.LOBBY_CONFIRM, pending.inst_id)
      end
    else
      Wait(1000)
    end
  end
end)

-- ── Limpeza ao entrar em corrida / sair ───────────────────────────────────

AddEventHandler('vhub_racha:local:bag_update', function(bag)
  if bag and (bag.state == 'racing' or bag.state == 'warmup') then
    if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
      RemoveBlip(VHubRachaLocal._pending_blip)
      VHubRachaLocal._pending_blip = nil
    end
    L.pending = nil
    if USE_NUI then SendNUIMessage({ type = 'vhub_racha.readyzone.clear' }) end
  elseif (not bag) or next(bag) == nil then
    if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
      RemoveBlip(VHubRachaLocal._pending_blip)
      VHubRachaLocal._pending_blip = nil
    end
    L.pending = nil
    if USE_NUI then SendNUIMessage({ type = 'vhub_racha.readyzone.clear' }) end
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
    RemoveBlip(VHubRachaLocal._pending_blip)
  end
end)
