-- server/dealership.lua — DELEGATOR fino: a concessionaria mora no vhub_conce (FASE 2).
-- O garage so resolve a concessionaria (zona/config local) e fala com a NUI; a
-- transacao (catalogo+stock+placa+money+chave+registro) e do vhub_conce.
-- Vendas P2P ficam no garage.lua (ACT_TRANSFER); leilao migra p/ ferinha (FASE 4).
---@diagnostic disable: undefined-global

local Core = VHubGarage.Core
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

-- resolve a concessionaria pela id (zona/config local e do garage)
local function getConc(id)
  for _, c in ipairs(CFG.concessionarias) do
    if c.id == id then return c end
  end
end


-- ============================================================
-- COMPRAR  (delega ao conce; garage so notifica/abre UI)
-- ============================================================
RegisterNetEvent(E.ACT_BUY)
AddEventHandler(E.ACT_BUY, function(model, placa_custom, conc_id)
  local src  = source
  local conc = getConc(conc_id)
  Citizen.CreateThread(function()
    local r = exports.vhub_conce:buy(src, model, placa_custom, conc) or {}
    if r.msg then Core.notify(src, r.msg) end
    if r.ok then
      TriggerClientEvent(E.OPEN_UI, src, {
        view = VHubGarage.UI.NOTIFY,
        payload = { kind = 'buy_ok', plate = r.plate, model = r.model, total = r.total },
      })
    end
  end)
end)


-- ============================================================
-- VENDER PARA A LOJA
-- ============================================================
RegisterNetEvent(E.ACT_SELL_SHOP)
AddEventHandler(E.ACT_SELL_SHOP, function(plate)
  local src = source
  Citizen.CreateThread(function()
    local r = exports.vhub_conce:sellToShop(src, plate) or {}
    if r.msg then Core.notify(src, r.msg) end
  end)
end)


-- ============================================================
-- TEST DRIVE  (conce autoriza/cobra; o cliente do garage faz o spawn temporario)
-- ============================================================
RegisterNetEvent(E.ACT_TESTDRIVE)
AddEventHandler(E.ACT_TESTDRIVE, function(model, conc_id)
  local src  = source
  local conc = getConc(conc_id)
  Citizen.CreateThread(function()
    local r = exports.vhub_conce:testDrive(src, model, conc) or {}
    if r.ok then
      TriggerClientEvent(E.DO_TESTDRIVE, src,
        { model = r.model, spawn = r.spawn, seg = r.seg, raio = r.raio })
    elseif r.msg then
      Core.notify(src, r.msg)
    end
  end)
end)
