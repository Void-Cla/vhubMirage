-- client/init.lua  bootstrap do vhub_garage no cliente
-- Responsabilidade: receber setup, abrir/fechar NUI, rotear payloads e callbacks.
---@diagnostic disable: undefined-global, undefined-field

local E  = VHubGarage.E
local UI = VHubGarage.UI

VHubGarage.state = VHubGarage.state or {
  pronto          = false,
  garagens        = {},
  concessionarias = {},
  leilao          = nil,
  patio           = nil,
  catalog         = {},
  types           = nil,
  zona            = nil,   -- { kind = 'garage'|'dealer'|'auction'|'impound', id, data }
  nui_aberta      = false,
  veiculos        = {},    -- plate   entity (gerenciado em vehicles.lua)
}

-- ----------------------------------------------------------------------------
-- SETUP recebido do servidor
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.SETUP)
AddEventHandler(E.SETUP, function(setup)
  if type(setup) ~= 'table' then return end
  local s = VHubGarage.state
  s.garagens        = setup.garagens        or {}
  s.concessionarias = setup.concessionarias or {}
  s.leilao          = setup.leilao
  s.patio           = setup.patio
  s.catalog         = setup.catalog         or {}
  s.types           = setup.types           or VHubGarage.types
  s.pronto          = true
  TriggerEvent('vhub_garage:setupReady')
end)

-- ----------------------------------------------------------------------------
-- Notifica  o textual (feedpost)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.NOTIFY)
AddEventHandler(E.NOTIFY, function(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg or ''))
  EndTextCommandThefeedPostTicker(false, true)
end)

-- ----------------------------------------------------------------------------
-- Abrir/fechar NUI (centralizado aqui; views s o roteadas via postMessage)
-- ----------------------------------------------------------------------------
local function openNui(payload)
  VHubGarage.state.nui_aberta = true
  SetNuiFocus(true, true)
  SendNUIMessage(payload)
end

local function closeNui()
  if not VHubGarage.state.nui_aberta then return end
  VHubGarage.state.nui_aberta = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = UI.CLOSE })
end

-- expor para outros m dulos do client
VHubGarage.openNui  = openNui
VHubGarage.closeNui = closeNui

RegisterNetEvent(E.OPEN_UI)
AddEventHandler(E.OPEN_UI, function(req)
  if type(req) ~= 'table' or not req.view then return end
  if req.view == UI.NOTIFY then
    -- s  notifica  o (n o muda foco)
    SendNUIMessage({ action = UI.NOTIFY, data = req.payload or {} })
    return
  end
  openNui({ action = req.view, data = req.payload or {} })
end)

RegisterNetEvent(E.CLOSE_UI)
AddEventHandler(E.CLOSE_UI, closeNui)

-- ----------------------------------------------------------------------------
-- NUI callbacks (mensagens vindas do HTML)
-- ----------------------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
  closeNui(); cb({ ok = true })
end)

-- pega ID da garagem da zona ATUAL do cliente (cliente   fonte de verdade da posi  o)
local function currentGarageId()
  local z = VHubGarage.state and VHubGarage.state.zona
  return (z and z.kind == 'garage') and z.id or nil
end

RegisterNUICallback('spawn', function(data, cb)
  local plate = data and data.plate
  local g     = currentGarageId()
  if plate and g then
    TriggerServerEvent(E.ACT_SPAWN, plate, g)
  else
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('Saia e entre na garagem novamente.')
    EndTextCommandThefeedPostTicker(false, true)
  end
  closeNui(); cb({ ok = true })
end)

RegisterNUICallback('store', function(data, cb)
  local plate = data and data.plate
  local g     = currentGarageId()
  if plate and g then
    local payload = nil
    -- collectClientState   um event handler em vehicles.lua que devolve via return
    TriggerEvent('vhub_garage:collectClientState', plate, function(s) payload = s end)
    TriggerServerEvent(E.ACT_STORE, plate, g, payload or {})
  end
  closeNui(); cb({ ok = true })
end)

RegisterNUICallback('buy', function(data, cb)
  TriggerServerEvent(E.ACT_BUY,
    data and data.model, data and data.plate or '', data and data.conc_id)
  closeNui(); cb({ ok = true })
end)

RegisterNUICallback('sellShop', function(data, cb)
  if data and data.plate then TriggerServerEvent(E.ACT_SELL_SHOP, data.plate) end
  closeNui(); cb({ ok = true })
end)

RegisterNUICallback('testDrive', function(data, cb)
  TriggerServerEvent(E.ACT_TESTDRIVE, data and data.model, data and data.conc_id)
  closeNui(); cb({ ok = true })
end)

RegisterNUICallback('rent', function(data, cb)
  TriggerServerEvent(E.ACT_RENT,
    data and data.model, data and data.conc_id, data and data.horas)
  closeNui(); cb({ ok = true })
end)

RegisterNUICallback('auctionNew', function(data, cb)
  TriggerServerEvent(E.ACT_AUCTION_NEW,
    data and data.plate, data and data.min_bid, data and data.buyout, data and data.dur_min)
  closeNui(); cb({ ok = true })
end)

RegisterNUICallback('auctionBid', function(data, cb)
  TriggerServerEvent(E.ACT_AUCTION_BID, data and data.id, data and data.amount)
  cb({ ok = true })
end)

RegisterNUICallback('impoundPay', function(data, cb)
  if data and data.plate then TriggerServerEvent(E.ACT_IMPOUND_PAY, data.plate) end
  cb({ ok = true })
end)

RegisterNUICallback('ipvaPay', function(data, cb)
  if data and data.plate then TriggerServerEvent(E.ACT_IPVA_PAY, data.plate) end
  cb({ ok = true })
end)

RegisterNUICallback('repair', function(data, cb)
  if data and data.plate then TriggerServerEvent(E.ACT_REPAIR, data.plate) end
  cb({ ok = true })
end)

RegisterNUICallback('cloneKey', function(data, cb)
  if data and data.plate then TriggerServerEvent(E.ACT_CLONE_KEY, data.plate) end
  cb({ ok = true })
end)

RegisterNUICallback('lendKey', function(data, cb)
  if data and data.plate and data.target_src and data.dias then
    TriggerServerEvent(E.ACT_LEND_KEY, data.plate, data.target_src, data.dias)
  end
  cb({ ok = true })
end)

RegisterNUICallback('revokeKey', function(data, cb)
  if data and data.plate and data.target_char then
    TriggerServerEvent(E.ACT_REVOKE_KEY, data.plate, data.target_char)
  end
  cb({ ok = true })
end)

RegisterNUICallback('transfer', function(data, cb)
  if data and data.plate and data.target_src then
    TriggerServerEvent(E.ACT_TRANSFER, data.plate, data.target_src, data.valor or 0)
  end
  cb({ ok = true })
end)

-- comandos r pidos
RegisterCommand('garagem', function()
  if VHubGarage.state.zona and VHubGarage.state.zona.kind == 'garage' then
    TriggerServerEvent(E.REQ_LIST)
  end
end, false)

RegisterCommand('concessionaria', function()
  if VHubGarage.state.zona and VHubGarage.state.zona.kind == 'dealer' then
    TriggerServerEvent(E.REQ_CATALOG, VHubGarage.state.zona.id)
  end
end, false)

RegisterCommand('leilao', function()
  if VHubGarage.state.zona and VHubGarage.state.zona.kind == 'auction' then
    TriggerServerEvent(E.REQ_AUCTIONS)
  end
end, false)

RegisterCommand('patio', function()
  if VHubGarage.state.zona and VHubGarage.state.zona.kind == 'impound' then
    TriggerServerEvent(E.REQ_IMPOUND)
  end
end, false)
