-- server/dealership.lua — concessionária (transação server-authoritative)
-- Cada função roda no thread do delegator do garage (que chama via export) e
-- RETORNA { ok, msg, ... } — quem fala com a NUI é o garage (dono da NUI).
-- conce orquestra: catálogo + estoque + placa única + money + chave-item + registro.
---@diagnostic disable: undefined-global

local SQL = VHubConce.SQL
local Core= VHubConce.Core
local U   = VHubConce.U
local CFG = VHubConce.cfg


-- ============================================================
-- COMPRAR
-- ============================================================

-- compra um veículo do catálogo; conc = concessionária resolvida (passada pelo garage)
function VHubConce.buy(src, model, placa_custom, conc)
  local cid = Core:getCharId(src); if not cid then return { ok = false } end
  local entry = VHubConce.catalog[model]
  if not entry then return { ok = false, msg = 'Modelo inválido.' } end
  if type(conc) ~= 'table' then return { ok = false, msg = 'Concessionária inválida.' } end

  local ok_tipo = false
  for _, t in ipairs(conc.tipos or {}) do if t == entry.tipo then ok_tipo = true; break end end
  if not ok_tipo then return { ok = false, msg = 'Esta loja não vende esse tipo.' } end

  -- limite por jogador
  if SQL:ownedCount(cid) >= CFG.max_veiculos_player then
    return { ok = false, msg = ('Você já tem %d veículos (limite atingido).'):format(CFG.max_veiculos_player) }
  end

  -- estoque opcional
  local stock = SQL:stockGet(model)
  if stock and stock.qty == 0 then return { ok = false, msg = 'Modelo sem estoque.' } end
  local preco = (stock and stock.custom_price) or entry.preco

  -- placa única
  local plate, perr = Core:newPlate(placa_custom)
  if not plate then
    return { ok = false, msg = (perr == 'placa_em_uso' and 'Placa já em uso. Escolha outra.' or 'Placa inválida.') }
  end
  local total = preco
  if placa_custom and placa_custom ~= '' then total = total + CFG.taxa_placa_custom end

  -- pagamento
  if not Core.pay(src, total) then
    return { ok = false, msg = ('Saldo insuficiente. Preço total: R$ %d.'):format(total) }
  end

  -- chave-item física
  if not Core.giveKeyItem(src, plate) then
    Core.refund(src, total)
    return { ok = false, msg = 'Inventário cheio. Pagamento estornado.' }
  end

  -- registro de negócio (+ espelho vh_vehicles dentro do createVehicle)
  local now = os.time()
  local created = SQL:createVehicle({
    plate = plate, model = model, vtype = entry.tipo, category = entry.categoria,
    char_id = cid, status = 'garage',
    customization = U.jenc({ model = model }), locked = false, position = nil,
    ipva_paid_until = now + CFG.ipva_dias * 86400,
    purchase_price = preco, purchase_at = now, last_seen_at = now,
  })
  if not created then
    Core.takeKeyItem(src, plate); Core.refund(src, total)
    return { ok = false, msg = 'Falha ao registrar. Pagamento estornado.' }
  end

  -- autorização lógica de dono + baixa de estoque + auditoria
  SQL:grantKey(plate, cid, 'owner', cid, nil)
  if stock then SQL:stockDecrement(model) end
  Core:log(plate, 'buy', cid, { model = model, preco = preco, total = total })

  return {
    ok = true, plate = plate, model = model, total = total,
    msg = ('Parabéns! %s adquirido. Placa: %s. Chave no inventário!'):format(entry.nome, plate),
  }
end


-- ============================================================
-- VENDER PARA A LOJA
-- ============================================================

-- vende o veículo de volta à loja (apaga registro, paga fração do preço)
function VHubConce.sellToShop(src, plate)
  local cid = Core:getCharId(src); if not cid then return { ok = false } end
  local p   = U.normalizePlate(plate); if not p then return { ok = false } end

  local v = SQL:getVehicle(p)
  if not v or v.char_id ~= cid then return { ok = false, msg = 'Você não é o dono.' } end
  if v.status ~= 'garage' then return { ok = false, msg = 'Veículo precisa estar na garagem.' } end
  if not Core.hasKeyItem(src, p) then return { ok = false, msg = 'Você não tem a chave do veículo.' } end

  local entry = VHubConce.catalog[v.model] or {}
  local preco = (v.purchase_price and v.purchase_price > 0) and v.purchase_price or (entry.preco or 0)
  local valor = math.floor(preco * CFG.fator_revenda_loja)

  Core.takeKeyItem(src, p)
  -- o físico vive no prontuário (vhub_vehicle_state) e morre junto no deleteVehicle —
  -- nada a persistir antes (o bloco antigo gravava uma CÓPIA stale do CORE, no-op real)
  SQL:deleteVehicle(p)
  if valor > 0 then Core.refund(src, valor) end
  Core:log(p, 'sell_shop', cid, { valor = valor })

  return { ok = true, valor = valor, msg = ('Veículo vendido por R$ %d.'):format(valor) }
end


-- ============================================================
-- TEST DRIVE
-- ============================================================

-- autoriza+cobra o test drive; o garage (cliente) executa o spawn temporário
function VHubConce.testDrive(src, model, conc)
  local cid = Core:getCharId(src); if not cid then return { ok = false } end
  local entry = VHubConce.catalog[model]
  if not entry or type(conc) ~= 'table' then return { ok = false } end

  local ok_tipo = false
  for _, t in ipairs(conc.tipos or {}) do if t == entry.tipo then ok_tipo = true; break end end
  if not ok_tipo then return { ok = false } end

  local custo = math.floor(entry.preco * CFG.fator_test_drive)
  if custo > 0 and not Core.payWallet(src, custo) then
    return { ok = false, msg = ('Saldo na carteira insuficiente. Test drive: R$ %d.'):format(custo) }
  end

  Core.testDrive[src] = { model = model, conc_id = conc.id, expires_at = os.time() + CFG.test_drive_segundos }
  Core:log('TEST', 'test_drive', cid, { model = model, custo = custo })

  return {
    ok = true, model = model,
    spawn = conc.test_spawn or { x = conc.x, y = conc.y, z = conc.z, h = 0.0 },
    seg = CFG.test_drive_segundos, raio = CFG.test_drive_raio,
  }
end
