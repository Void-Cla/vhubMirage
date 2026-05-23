-- client/zones.lua — vhub_money (Fleeca Camell)
-- Detecta proximidade de banco fisico ou ATM (cold loop 800ms + hot loop on-demand).
-- Mostra hint + [E] e dispara abertura do NUI quando o jogador interage.
-- Padrao P0-5: thread fria identifica, thread quente so quando perto.

local Cfg   = VHubMoneyCfg
local Banks = VHubMoneyBanks
local ATMs  = VHubMoneyATMs

-- ── Estado de proximidade ───────────────────────────────────────────────────

-- _zona = { kind = 'bank'|'atm', idx = n, x, y, z, label }
local _zona = nil

-- ── Blips dos bancos fisicos ────────────────────────────────────────────────

CreateThread(function()
  if not Cfg.BANK.BLIP_SHOW then return end
  for _, b in ipairs(Banks) do
    local blip = AddBlipForCoord(b.x, b.y, b.z)
    SetBlipSprite(blip, Cfg.BANK.BLIP_SPRITE)
    SetBlipColour(blip, Cfg.BANK.BLIP_COLOR)
    SetBlipScale(blip, Cfg.BANK.BLIP_SCALE)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Cfg.BRAND_NAME .. ' — ' .. b.label)
    EndTextCommandSetBlipName(blip)
  end
end)

-- Blips dos ATMs sao opcionais (default off — polui o mapa com 70+ pontos)
CreateThread(function()
  if not Cfg.ATM.BLIP_SHOW then return end
  for _, a in ipairs(ATMs) do
    local blip = AddBlipForCoord(a[1], a[2], a[3])
    SetBlipSprite(blip, Cfg.ATM.BLIP_SPRITE)
    SetBlipColour(blip, Cfg.ATM.BLIP_COLOR)
    SetBlipScale(blip, 0.55)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('ATM')
    EndTextCommandSetBlipName(blip)
  end
end)

-- ── Detector de proximidade (thread fria, 800ms) ────────────────────────────

local function detect_zone()
  local px, py, pz = table.unpack(GetEntityCoords(PlayerPedId()))

  -- Bancos fisicos primeiro (raio maior)
  local bank_r2 = Cfg.BANK.INTERACT_RADIUS * Cfg.BANK.INTERACT_RADIUS
  for i, b in ipairs(Banks) do
    local dx, dy, dz = px - b.x, py - b.y, pz - b.z
    if (dx * dx + dy * dy + dz * dz) <= bank_r2 then
      return { kind = 'bank', idx = i, x = b.x, y = b.y, z = b.z,
               label = Cfg.BRAND_NAME .. ' — ' .. b.label }
    end
  end

  -- ATMs
  local atm_r2 = Cfg.ATM.INTERACT_RADIUS * Cfg.ATM.INTERACT_RADIUS
  for i, a in ipairs(ATMs) do
    local dx, dy, dz = px - a[1], py - a[2], pz - a[3]
    if (dx * dx + dy * dy + dz * dz) <= atm_r2 then
      return { kind = 'atm', idx = i, x = a[1], y = a[2], z = a[3],
               label = 'Caixa Eletronico ' .. Cfg.BRAND_NAME }
    end
  end

  return nil
end

CreateThread(function()
  while true do
    Wait(700)
    _zona = detect_zone()
  end
end)

-- ── Hint [E] (thread quente apenas quando perto) ────────────────────────────

local function draw_hint(label)
  SetTextScale(0.36, 0.36); SetTextFont(4); SetTextProportional(true)
  SetTextColour(255, 255, 255, 220); SetTextOutline()
  SetTextEntry('STRING')
  AddTextComponentString('[E] ' .. label)
  DrawText(0.5, 0.91)
end

CreateThread(function()
  while true do
    if not _zona then
      Wait(500)
    else
      Wait(0)
      draw_hint(_zona.label)
      -- Marker pequeno para ATM (banco fisico ja tem balcao visual)
      if _zona.kind == 'atm' then
        DrawMarker(27,
          _zona.x, _zona.y, _zona.z - 0.95,
          0, 0, 0, 0, 0, 0,
          0.5, 0.5, 0.3,
          243, 181, 58, 140,
          false, false, 2, false, nil, nil, false)
      end
      -- [E] = control 38
      if IsControlJustReleased(0, 38) then
        TriggerServerEvent('vhub_money:nui:open', { mode = _zona.kind })
      end
    end
  end
end)

-- ── /banco (atalho extra: so funciona se estiver perto de banco/ATM) ────────

RegisterCommand(VHubMoneyCfg.CMD_OPEN_PANEL, function()
  if not _zona then
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('Aproxime-se de uma agencia ' ..
      VHubMoneyCfg.BRAND_NAME .. ' ou de um ATM para abrir o painel.')
    EndTextCommandThefeedPostTicker(false, true)
    return
  end
  TriggerServerEvent('vhub_money:nui:open', { mode = _zona.kind })
end, false)
