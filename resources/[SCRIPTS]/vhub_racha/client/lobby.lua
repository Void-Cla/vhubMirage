-- client/lobby.lua — ready zone visual + confirmacao de presenca.
-- Quando o servidor envia LOBBY_PENDING, ativa render do circulo no chao
-- mais hint "[E] confirmar presenca" quando dentro do raio.

local Cfg  = VHubRachaCfg
local E    = VHubRachaE
local Lang = VHubRachaLang
local MA   = VHubRachaMath
local U    = VHubRachaUtils
local L    = VHubRachaLocal

-- ── Recebe estado pending do servidor ─────────────────────────────────────

RegisterNetEvent(E.LOBBY_PENDING, function(data)
  if type(data) ~= 'table' or not data.ready_zone then return end
  VHubRachaLocal.set_pending({
    inst_id          = data.inst_id,
    ready_zone       = data.ready_zone,
    pending_deadline = data.pending_deadline,
    mode             = data.mode,
    track_label      = data.track_label,
  })

  -- Notifica jogador para se dirigir ate o ponto
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(Lang.t('lobby.confirm_presence'))
  EndTextCommandThefeedPostTicker(false, true)

  -- Marca blip temporario no mapa para a ready zone
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
end)

RegisterNetEvent(E.LOBBY_CONFIRMED, function(_data)
  -- Servidor confirmou: limpa blip de rota e notifica o jogador
  if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
    RemoveBlip(VHubRachaLocal._pending_blip)
    VHubRachaLocal._pending_blip = nil
  end
  VHubRachaLocal.confirmed = true
  -- Notifica com feed nativo
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(Lang.t('lobby.confirmed_notify') or 'Presença confirmada — aguarde o início.')
  EndTextCommandThefeedPostTicker(false, true)
end)

-- ── Render da ready zone (circulo no chao + glow) ─────────────────────────

local function is_inside(zone)
  if not zone then return false end
  local pos = GetEntityCoords(PlayerPedId())
  if math.abs(pos.z - zone.z) > (zone.z_tol or 5.0) then return false end
  return MA.point_in_circle(pos.x, pos.y, zone.x, zone.y, zone.radius or 18.0)
end

CreateThread(function()
  while true do
    local pending = L.pending
    if not pending or not pending.ready_zone then
      Wait(500)
    else
      local zone = pending.ready_zone
      local pos = GetEntityCoords(PlayerPedId())
      local d2  = MA.dist2_xy(pos.x, pos.y, zone.x, zone.y)
      local far = d2 > (300 * 300)   -- > 300m: nao desenha

      if far then
        Wait(800)
      else
        Wait(0)
        -- Mostrar cronometro de tempo restante para confirmar/chegar na ready zone
        if pending.pending_deadline and not L.confirmed then
          local remaining = math.max(0, pending.pending_deadline - GetGameTimer())
          local label = ('%s: %s'):format('Tempo p/ confirmar', (U and U.time_short_ms) and U.time_short_ms(remaining) or (math.ceil(remaining/1000) .. 's'))
          SetTextFont(7); SetTextScale(0.0, 0.44)
          SetTextColour(255, 255, 255, 240); SetTextOutline(); SetTextDropShadow()
          SetTextEntry('STRING'); AddTextComponentString(label)
          SetTextCentre(false); DrawText(0.03, 0.02)
        end
        local cfg = Cfg.READY_ZONE.GLOW_COLOR or { r = 243, g = 181, b = 58, a = 90 }
        local r = zone.radius or 18.0

        -- Disco no chao (sem fundo opaco — alpha baixo)
        DrawMarker(1,
          zone.x, zone.y, zone.z - 1.0,
          0, 0, 0, 0, 0, 0,
          r * 2.0, r * 2.0, 0.8,
          cfg.r, cfg.g, cfg.b, cfg.a or 90,
          false, false, 2, false, nil, nil, false)

        -- Cilindro etereo
        DrawMarker(28,
          zone.x, zone.y, zone.z + 1.5,
          0, 0, 0, 0, 0, 0,
          r * 1.8, r * 1.8, Cfg.READY_ZONE.GLOW_HEIGHT or 4.0,
          cfg.r, cfg.g, cfg.b, 50,
          false, false, 2, false, nil, nil, false)

        -- Hint [E] quando dentro
        if not L.confirmed and is_inside(zone) then
          local on_screen, sx, sy = GetScreenCoordFromWorldCoord(zone.x, zone.y, zone.z + 2.0)
          if on_screen then
            SetTextFont(7); SetTextScale(0.0, 0.55)
            SetTextColour(255, 255, 255, 240); SetTextOutline(); SetTextDropShadow()
            SetTextEntry('STRING')
            AddTextComponentString(Lang.t('lobby.press_e_confirm'))
            SetTextCentre(true); DrawText(sx, sy)
          end
          -- Tecla E (control 38) → confirma
          if IsControlJustReleased(0, 38) then
            -- Bloqueia reenvio local imediato se ja confirmando
            VHubRachaLocal.confirmed = true
            TriggerServerEvent(E.LOBBY_CONFIRM, pending.inst_id)
          end
        elseif L.confirmed then
          -- Ja confirmado: mostra um check etereo
          local on_screen, sx, sy = GetScreenCoordFromWorldCoord(zone.x, zone.y, zone.z + 2.0)
          if on_screen then
            SetTextFont(7); SetTextScale(0.0, 0.50)
            SetTextColour(100, 220, 120, 235); SetTextOutline(); SetTextDropShadow()
            SetTextEntry('STRING')
            AddTextComponentString(Lang.t('lobby.confirmed') .. ' ✓')
            SetTextCentre(true); DrawText(sx, sy)
          end
        end
        
        -- Soft particles (sutileza de areia) ao redor da ready zone — leve custo
        if not L.confirmed then
          local N = 12
          local t = GetGameTimer() / 1000.0
          for i = 1, N do
            local angle = (i / N) * (math.pi * 2) + (t * 0.6)
            local rr = (r * 0.5) + math.sin(t + i) * (r * 0.12)
            local px = zone.x + math.cos(angle) * rr
            local py = zone.y + math.sin(angle) * rr
            local pz = zone.z + 0.2 + (math.sin(t * 1.3 + i) * 0.08)
            DrawMarker(1, px, py, pz, 0,0,0, 0,0,0, 0.12, 0.12, 0.12, cfg.r, cfg.g, cfg.b, 60, false, false, 2, false, nil, nil, false)
          end
        end
      end
    end
  end
end)

-- ── Limpeza quando entra em corrida ou sai do lobby ───────────────────────

AddEventHandler('vhub_racha:local:bag_update', function(bag)
  if bag and (bag.state == 'racing' or bag.state == 'warmup') then
    if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
      RemoveBlip(VHubRachaLocal._pending_blip)
      VHubRachaLocal._pending_blip = nil
    end
    -- mantem pending=nil quando entrar em race (lobby virou warmup)
    L.pending = nil
  elseif (not bag) or next(bag) == nil then
    -- bag limpa = saiu do lobby/corrida
    if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
      RemoveBlip(VHubRachaLocal._pending_blip)
      VHubRachaLocal._pending_blip = nil
    end
    L.pending = nil
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  if VHubRachaLocal._pending_blip and DoesBlipExist(VHubRachaLocal._pending_blip) then
    RemoveBlip(VHubRachaLocal._pending_blip)
  end
end)
