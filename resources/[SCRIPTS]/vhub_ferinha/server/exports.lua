-- server/exports.lua — superfície do vhub_ferinha (leilão). Invoker confiável only.
-- O garage delega ACT_AUCTION_NEW/BID + monta a NUI de REQ_AUCTIONS via listActiveAuctions;
-- o vhub_admin chama cancelAuction/finalizeExpired (escrow vive aqui — não pode ser pulado).
---@diagnostic disable: undefined-global

local SQL = VHubFerinha.SQL

local TRUSTED = {
  ['vhub']        = true,
  ['vhub_garage'] = true,
  ['vhub_admin']  = true,
  ['vhub_conce']  = true,
}

local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return true end
  return TRUSTED[caller] == true
end


-- leitura: leilões ativos (o garage enriquece com catálogo + envia à NUI)
exports('listActiveAuctions', function()
  if not _invoker_allowed() then return {} end
  return SQL:listActiveAuctions()
end)

-- leitura: leilão ativo de uma placa (info do painel admin via proxy do garage)
exports('getAuctionByPlate', function(plate)
  if not _invoker_allowed() then return nil end
  return SQL:getAuctionByPlate(plate)
end)

-- transações (retornam {ok,msg}; o garage notifica o ator)
exports('newAuction', function(src, plate, min_bid, buyout, dur_min)
  if not _invoker_allowed() then return { ok = false } end
  return VHubFerinha.newAuction(src, plate, min_bid, buyout, dur_min)
end)

exports('bid', function(src, auction_id, amount)
  if not _invoker_allowed() then return { ok = false } end
  return VHubFerinha.bid(src, auction_id, amount)
end)

-- admin: cancelar + finalizar vencidos (escrow refund acontece aqui dentro)
exports('cancelAuction', function(id, actor_cid)
  if not _invoker_allowed() then return false end
  return VHubFerinha.cancelAuction(id, actor_cid)
end)

exports('finalizeExpired', function()
  if not _invoker_allowed() then return 0 end
  return VHubFerinha.finalizeExpired()
end)


-- ============================================================
-- ZONA (config de localização da casa de leilões — dono desde a decisão #25)
-- vec3 é de uso LOCAL; ao cruzar a fronteira do export, a coord vai ACHATADA
-- p/ primitivo {x,y,z} (msgpack mangle o vetor nativo — L-19).
-- ============================================================

-- zona única do leilão p/ o garage agregar no SETUP (read-only, estática; nil se ausente)
exports('getZones', function()
  if not _invoker_allowed() then return nil end
  local l = VHubFerinha.cfg.leilao_local
  if not l then return nil end
  return {
    id = l.id, label = l.label,
    x = l.coord.x, y = l.coord.y, z = l.coord.z, raio = l.raio,
    blip = l.blip,
  }
end)
