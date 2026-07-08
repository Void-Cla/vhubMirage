-- client/zones.lua — vhub_money (Fleeca Camell)
-- Interação de banco/ATM via vhub_target (olho), não mais por proximidade [E].
-- Threads de proximidade + hint + marker REMOVIDAS (decisão #57): o target dá o
-- affordance (highlight ao mirar) e o SERVIDOR revalida o raio em `nui:open`
-- (near_bank/near_atm, raio 3.0) — a mudança de gatilho é neutra em segurança.
-- Mantém apenas os BLIPS (não são interação).
---@diagnostic disable: undefined-global, lowercase-global

local Cfg   = VHubMoneyCfg
local Banks = VHubMoneyBanks


-- ============================================================
-- BLIPS (criados 1x no boot, nunca em loop)
-- ============================================================

-- blips das agências físicas
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

-- blips dos ATMs são opcionais (default off — polui o mapa; interação vem das box zones)
CreateThread(function()
  if not Cfg.ATM.BLIP_SHOW then return end
  for _, a in ipairs(VHubMoneyATMs) do
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


-- ============================================================
-- INTERAÇÃO VIA TARGET (olho)
-- ============================================================

-- pede ao servidor a abertura do painel; o servidor decide (revalida o raio)
local function openStation(mode)
  TriggerServerEvent('vhub_money:nui:open', { mode = mode })
end

-- não abre banco/ATM de dentro de um veículo (bloqueio client leve; não é verdade crítica)
local function onFoot()
  return not IsPedInAnyVehicle(PlayerPedId(), false)
end

CreateThread(function()
  -- ATMs = box zone por coord de VHubMoneyATMs — a MESMA lista que o servidor usa
  -- p/ revalidar em near_atm() (decisão #57-A): onde o olho aparece, o server aceita.
  for i, a in ipairs(VHubMoneyATMs) do
    exports.vhub_target:addBoxZone({
      coords  = vec3(a[1], a[2], a[3]),
      size    = vec3(1.2, 1.2, 2.0),
      options = {
        {
          name     = ('vhub_money:atm_%d'):format(i),
          label    = 'Caixa Eletrônico ' .. Cfg.BRAND_NAME,
          icon     = 'card',
          distance = 1.5,
          canInteract = onFoot,
          onSelect = function() openStation('atm') end,
        },
      },
    })
  end

  -- Agências = 7 balcões físicos (box zone por coord)
  for _, b in ipairs(Banks) do
    exports.vhub_target:addBoxZone({
      coords   = vec3(b.x, b.y, b.z),
      size     = vec3(2.0, 2.0, 2.5),
      rotation = 0.0,
      options  = {
        {
          name     = 'vhub_money:bank',
          label    = Cfg.BRAND_NAME .. ' — ' .. b.label,
          icon     = 'bank',
          distance = 2.0,
          canInteract = onFoot,
          onSelect = function() openStation('bank') end,
        },
      },
    })
  end
end)
