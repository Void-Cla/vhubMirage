-- server/init.lua  bootstrap do vhub_garage
-- Ordem de carregamento (fxmanifest):
--   shared/{config,events,types,utils}
--   server/{sql, core, init,
--           garage, dealership, auction, rental,
--           impound, ipva, maintenance, exports}
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

-- ----------------------------------------------------------------------------
-- Boot
-- ----------------------------------------------------------------------------
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    SQL:initSchema()
    print('[vhub_garage] schema verificado')
    -- envia setup a quem est  online (resource restart em produ  o)
    for _, src in ipairs(GetPlayers()) do
      TriggerClientEvent(E.SETUP, tonumber(src), {
        garagens        = CFG.garagens,
        concessionarias = CFG.concessionarias,
        leilao          = CFG.leilao_local,
        patio           = CFG.patio_local,
        catalog         = VHubGarage.catalog,
        types           = VHubGarage.types,
      })
    end
    print('[vhub_garage] pronto')
  end)
end)

-- ----------------------------------------------------------------------------
-- Sess es (referencia viva do user para todos os m dulos)
-- ----------------------------------------------------------------------------
AddEventHandler('vHub:characterLoad', function(user)
  Core:setSession(user.source, user)
end)

AddEventHandler('vHub:playerSpawn', function(user)
  Core:setSession(user.source, user)
  TriggerClientEvent(E.SETUP, user.source, {
    garagens        = CFG.garagens,
    concessionarias = CFG.concessionarias,
    leilao          = CFG.leilao_local,
    patio           = CFG.patio_local,
    catalog         = VHubGarage.catalog,
    types           = VHubGarage.types,
  })
end)

AddEventHandler('playerDropped', function()
  Core:dropSession(source)
end)

-- ----------------------------------------------------------------------------
-- Listagens (pedidas pelo cliente ao abrir uma view do NUI)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REQ_LIST)
AddEventHandler(E.REQ_LIST, function()
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  Citizen.CreateThread(function()
    local mine = SQL:listByOwner(cid) or {}
    local keys = SQL:listKeysOfChar(cid) or {}
    -- agrega ve culos onde sou dono OU tenho chave
    local seen, snaps = {}, {}
    for _, v in ipairs(mine) do
      seen[v.plate] = true; snaps[#snaps+1] = Core:vehicleSnapshot(v)
    end
    for _, k in ipairs(keys) do
      if not seen[k.plate] then
        local v = SQL:getVehicle(k.plate)
        if v then
          local snap = Core:vehicleSnapshot(v)
          snap.role = k.kind   -- 'shared', 'clone', 'rental'
          snaps[#snaps+1] = snap
          seen[k.plate] = true
        end
      end
    end
    TriggerClientEvent(E.OPEN_UI, src, {
      view = VHubGarage.UI.OPEN_GARAGE,
      payload = { vehicles = snaps, types = VHubGarage.types.list },
    })
  end)
end)

RegisterNetEvent(E.REQ_CATALOG)
AddEventHandler(E.REQ_CATALOG, function(conc_id)
  local src = source
  local conc
  for _, c in ipairs(CFG.concessionarias) do
    if c.id == conc_id then conc = c; break end
  end
  if not conc then return end
  Citizen.CreateThread(function()
    -- monta cat logo aplicando estoque + custom_price
    local out = {}
    for model, entry in pairs(VHubGarage.catalog) do
      local match_tipo = false
      for _, t in ipairs(conc.tipos) do
        if t == entry.tipo then match_tipo = true; break end
      end
      if match_tipo then
        local stock = SQL:stockGet(model)
        local qty   = stock and stock.qty or -1
        local preco = (stock and stock.custom_price) or entry.preco
        if qty ~= 0 then
          out[#out+1] = {
            model = model, nome = entry.nome, preco = preco,
            tipo = entry.tipo, categoria = entry.categoria,
            stats = entry.stats, tags = entry.tags or {},
            estoque = qty,
          }
        end
      end
    end
    table.sort(out, function(a, b) return a.preco < b.preco end)
    TriggerClientEvent(E.OPEN_UI, src, {
      view = VHubGarage.UI.OPEN_DEALERSHIP,
      payload = {
        conc = conc, catalog = out,
        cfg = {
          taxa_placa = CFG.taxa_placa_custom,
          fator_revenda = CFG.fator_revenda_loja,
          fator_test = CFG.fator_test_drive,
          test_seg = CFG.test_drive_segundos,
          fator_aluguel = CFG.fator_aluguel,
          aluguel_h = CFG.aluguel_periodo_h,
        },
      },
    })
  end)
end)

-- ----------------------------------------------------------------------------
-- Limpeza peri dica de chaves expiradas (1x por hora)
-- ----------------------------------------------------------------------------
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(60 * 60 * 1000)
    SQL:purgeExpiredKeys()
  end
end)
