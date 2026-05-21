-- server/dealership.lua  concession ria (compra, venda  -loja, test drive)
-- Vendas P2P ficam no garage.lua (ACT_TRANSFER).
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local U    = VHubGarage.U
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

local function getConc(id)
  for _, c in ipairs(CFG.concessionarias) do
    if c.id == id then return c end
  end
end

-- limite por jogador
local function ownedCount(cid)
  local r = SQL.scalar('SELECT COUNT(*) FROM vhub_vehicles WHERE char_id = ?', { cid })
  return tonumber(r) or 0
end

-- ----------------------------------------------------------------------------
-- COMPRAR
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_BUY)
AddEventHandler(E.ACT_BUY, function(model, placa_custom, conc_id)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local entry = VHubGarage.catalog[model]
  if not entry then Core.notify(src, 'Modelo inv lido.'); return end
  local conc = getConc(conc_id)
  if not conc then Core.notify(src, 'Concession ria inv lida.'); return end

  -- valida tipo permitido nessa concession ria
  local ok_tipo = false
  for _, t in ipairs(conc.tipos) do if t == entry.tipo then ok_tipo = true; break end end
  if not ok_tipo then Core.notify(src, 'Esta loja n o vende esse tipo.'); return end

  Citizen.CreateThread(function()
    -- limite
    if ownedCount(cid) >= CFG.max_veiculos_player then
      Core.notify(src, ('Voc  j  tem %d ve culos (limite atingido).')
        :format(CFG.max_veiculos_player))
      return
    end

    -- estoque opcional
    local stock = SQL:stockGet(model)
    if stock and stock.qty == 0 then
      Core.notify(src, 'Modelo sem estoque.'); return
    end
    local preco = (stock and stock.custom_price) or entry.preco

    -- placa
    local plate, perr = Core:newPlate(placa_custom)
    if not plate then
      Core.notify(src, perr == 'placa_em_uso'
        and 'Placa j  em uso. Escolha outra.'
        or  'Placa inv lida.')
      return
    end
    local total = preco
    if placa_custom and placa_custom ~= '' then total = total + CFG.taxa_placa_custom end

    -- pagamento
    if not Core.pay(src, total) then
      Core.notify(src, ('Saldo insuficiente. Pre o total: R$ %d.'):format(total))
      return
    end

    -- entrega chave-item
    if not Core.giveKeyItem(src, plate) then
      Core.refund(src, total)
      Core.notify(src, 'Invent rio cheio. Pagamento estornado.')
      return
    end

    -- cria registro
    local now = os.time()
    local ipva_until = now + CFG.ipva_dias * 86400
    local created = SQL:createVehicle({
      plate = plate, model = model, vtype = entry.tipo,
      category = entry.categoria, char_id = cid,
      status = 'garage',
      customization = U.jenc({ model = model }),
      locked = false, position = nil,
      ipva_paid_until = ipva_until,
      purchase_price = preco, purchase_at = now,
      last_seen_at = now,
    })
    if not created then
      -- estorna em caso de SQL erro
      Core.takeKeyItem(src, plate)
      Core.refund(src, total)
      Core.notify(src, 'Falha ao registrar. Pagamento estornado.')
      return
    end

    -- registro de chave-owner (autoriza  o l gica)
    SQL:grantKey(plate, cid, 'owner', cid, nil)
    if stock then SQL:stockDecrement(model) end
    Core:log(plate, 'buy', cid, { model = model, preco = preco, total = total })

    Core.notify(src, ('Parab ns! %s adquirido. Placa: %s. Chave no invent rio!')
      :format(entry.nome, plate))
    TriggerClientEvent(E.OPEN_UI, src, {
      view = VHubGarage.UI.NOTIFY,
      payload = { kind = 'buy_ok', plate = plate, model = model, total = total },
    })
  end)
end)

-- ----------------------------------------------------------------------------
-- VENDER PARA A LOJA
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_SELL_SHOP)
AddEventHandler(E.ACT_SELL_SHOP, function(plate)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end

  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p)
    if not v or v.char_id ~= cid then
      Core.notify(src, 'Voc  n o   o dono.'); return
    end
    if v.status ~= 'garage' then
      Core.notify(src, 'Ve culo precisa estar na garagem.'); return
    end
    if not Core.hasKeyItem(src, p) then
      Core.notify(src, 'Voc  n o tem a chave do ve culo.'); return
    end

    local entry  = VHubGarage.catalog[v.model] or {}
    local preco  = (v.purchase_price > 0) and v.purchase_price or (entry.preco or 0)
    local valor  = math.floor(preco * CFG.fator_revenda_loja)

    Core.takeKeyItem(src, p)
    SQL:deleteVehicle(p)
    if valor > 0 then Core.refund(src, valor) end
    Core:log(p, 'sell_shop', cid, { valor = valor })
    Core.notify(src, ('Ve culo vendido por R$ %d.'):format(valor))
  end)
end)

-- ----------------------------------------------------------------------------
-- TEST DRIVE
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_TESTDRIVE)
AddEventHandler(E.ACT_TESTDRIVE, function(model, conc_id)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local entry = VHubGarage.catalog[model]
  if not entry then return end
  local conc = getConc(conc_id); if not conc then return end

  -- valida tipo permitido
  local ok_tipo = false
  for _, t in ipairs(conc.tipos) do if t == entry.tipo then ok_tipo = true; break end end
  if not ok_tipo then return end

  local custo = math.floor(entry.preco * CFG.fator_test_drive)
  if custo > 0 and not Core.payWallet(src, custo) then
    Core.notify(src, ('Saldo na carteira insuficiente. Test drive: R$ %d.'):format(custo))
    return
  end

  Core.testDrive[src] = {
    model = model, conc_id = conc_id,
    expires_at = os.time() + CFG.test_drive_segundos,
  }
  TriggerClientEvent(E.DO_TESTDRIVE, src, {
    model = model, spawn = conc.test_spawn or { x = conc.x, y = conc.y, z = conc.z, h = 0.0 },
    seg   = CFG.test_drive_segundos, raio = CFG.test_drive_raio,
  })
  Core:log('TEST', 'test_drive', cid, { model = model, custo = custo })
end)

-- ----------------------------------------------------------------------------
-- Exports administrativos (estoque)
-- ----------------------------------------------------------------------------
exports('adminSetStock', function(src, model, qty, custom_price)
  if not Core.hasPerm(src, CFG.perms.stock_admin) then return false end
  Citizen.CreateThread(function() SQL:stockSet(model, qty, custom_price) end)
  return true
end)
