-- shared/events.lua  constantes de eventos (centralizadas para evitar drift)
VHubGarage          = VHubGarage or {}
VHubGarage.E        = VHubGarage.E or {}

-- ---------- Servidor   Cliente -----------------------------------------------
VHubGarage.E.SETUP            = 'vhub_garage:setup'             -- envia config das zonas
VHubGarage.E.NOTIFY           = 'vhub_garage:notify'            -- string para feedpost
VHubGarage.E.OPEN_UI          = 'vhub_garage:openUI'            -- abre NUI: view + payload
VHubGarage.E.CLOSE_UI         = 'vhub_garage:closeUI'           -- for a fechar NUI
VHubGarage.E.DO_SPAWN         = 'vhub_garage:doSpawn'           -- spawn de ve culo
VHubGarage.E.DO_DESPAWN       = 'vhub_garage:doDespawn'         -- despawn de ve culo
VHubGarage.E.DO_TESTDRIVE     = 'vhub_garage:doTestDrive'       -- test drive (tempor rio)
VHubGarage.E.SPAWN_OUT        = 'vhub_garage:spawnOut'          -- re-spawn de ve culos que estavam fora
VHubGarage.E.RESCUE_DONE      = 'vhub_garage:rescueDone'        -- p tio liberado
VHubGarage.E.UPDATE_AUCTION   = 'vhub_garage:updateAuction'     -- broadcast de leil o atualizado

-- ---------- Cliente   Servidor -----------------------------------------------
VHubGarage.E.REQ_LIST         = 'vhub_garage:reqList'           -- pede lista de ve culos
VHubGarage.E.REQ_CATALOG      = 'vhub_garage:reqCatalog'        -- pede cat logo concession ria
VHubGarage.E.REQ_AUCTIONS     = 'vhub_garage:reqAuctions'       -- pede leil es ativos
VHubGarage.E.REQ_IMPOUND      = 'vhub_garage:reqImpound'        -- pede lista do p tio
VHubGarage.E.ACT_SPAWN        = 'vhub_garage:actSpawn'          -- pedir spawn
VHubGarage.E.ACT_STORE        = 'vhub_garage:actStore'          -- pedir guardar
VHubGarage.E.ACT_BUY          = 'vhub_garage:actBuy'            -- comprar
VHubGarage.E.ACT_SELL_SHOP    = 'vhub_garage:actSellShop'       -- vender para a loja
VHubGarage.E.ACT_SELL_P2P     = 'vhub_garage:actSellP2P'        -- vender para outro player
VHubGarage.E.ACT_TESTDRIVE    = 'vhub_garage:actTestdrive'      -- iniciar test drive
VHubGarage.E.ACT_RENT         = 'vhub_garage:actRent'           -- alugar
VHubGarage.E.ACT_AUCTION_NEW  = 'vhub_garage:actAuctionNew'     -- criar leil o
VHubGarage.E.ACT_AUCTION_BID  = 'vhub_garage:actAuctionBid'     -- dar lance
VHubGarage.E.ACT_AUCTION_CANC = 'vhub_garage:actAuctionCancel'  -- cancelar leil o (admin)
VHubGarage.E.ACT_IMPOUND_PAY  = 'vhub_garage:actImpoundPay'     -- pagar libera  o
VHubGarage.E.ACT_IPVA_PAY     = 'vhub_garage:actIpvaPay'        -- pagar IPVA
VHubGarage.E.ACT_REPAIR       = 'vhub_garage:actRepair'         -- pagar reparo (na garagem)
VHubGarage.E.ACT_CLONE_KEY    = 'vhub_garage:actCloneKey'       -- clonar chave
VHubGarage.E.ACT_LEND_KEY     = 'vhub_garage:actLendKey'        -- emprestar chave
VHubGarage.E.ACT_REVOKE_KEY   = 'vhub_garage:actRevokeKey'      -- revogar empr stimo
VHubGarage.E.ACT_TRANSFER     = 'vhub_garage:actTransfer'       -- transferir definitivo (P2P)
VHubGarage.E.REPORT_STATE     = 'vhub_garage:reportState'       -- delta peri dico do cliente
VHubGarage.E.ACT_IMPOUND_PUT  = 'vhub_garage:actImpoundPut'     -- admin/police envia ao p tio

-- ---------- NUI postMessage actions ------------------------------------------
VHubGarage.UI = {
  OPEN_GARAGE     = 'openGarage',
  OPEN_DEALERSHIP = 'openDealership',
  OPEN_AUCTION    = 'openAuction',
  OPEN_IMPOUND    = 'openImpound',
  CLOSE           = 'close',
  REFRESH         = 'refresh',
  NOTIFY          = 'notify',
}
