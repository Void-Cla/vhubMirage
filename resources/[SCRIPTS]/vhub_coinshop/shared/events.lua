-- shared/events.lua — registro único de nomes de evento do vhub_coinshop (global, sem return)

VHubCoin = VHubCoin or {}

-- eventos server→client (TriggerClientEvent) — discrete, nunca para estado contínuo
VHubCoin.E = {
    -- notifica o cliente que o saldo de moedas mudou (discreto; NUI admin atualiza display)
    COINS_CHANGED   = 'vhub_coinshop:coinsChanged',
    -- abre a NUI fullscreen (painel ADMIN) — SÓ via /coinshop admin validado no server (C1 #58)
    OPEN_SHOP_ADMIN = 'vhub_coinshop:openShopAdmin',
}

-- eventos client→server: nenhum neste momento (test-drive removido — v2.4.0)
VHubCoin.S = {}

-- ações do RELAY do iPad (whitelist fechada em server/ipad_relay.lua) — superfície do JOGADOR:
--   open | buy_item | buy_deal | redeem | pix_create
-- Contrato do push 'pix' (decisão #59 — shape ESTÁVEL, o front não muda quando o PSP chegar):
--   stub: { ok=false, code='pix_disabled', message }
--   real: { ok=true, txid, qrcode_base64, copiaECola, expiresAt }

-- ações NUI (RegisterNUICallback) — painel ADMIN via /coinshop (decisão #59: a superfície
-- de jogador da NUI fullscreen foi REMOVIDA; jogador usa o app do iPad)
VHubCoin.NUI = {
    CLOSE              = 'close',
    GET_ADMIN_STATS    = 'getAdminStats',
    GET_RECENT_TX      = 'getRecentTransactions',
    GET_TOP_SELLING    = 'getTopSelling',
    GET_PURCHASE_HIST  = 'getPurchaseHistory',
    GET_ONLINE_PLAYERS = 'getOnlinePlayers',
    ADMIN_GIVE_COINS   = 'adminGiveCoins',
    ADMIN_SET_COINS    = 'adminSetCoins',
    ADMIN_CREATE_ITEM  = 'adminCreateItem',
    ADMIN_EDIT_ITEM    = 'adminEditItem',
    ADMIN_DELETE_ITEM  = 'adminDeleteItem',
    ADMIN_CREATE_CAT   = 'adminCreateCategory',
    ADMIN_EDIT_CAT     = 'adminEditCategory',
    ADMIN_DELETE_CAT   = 'adminDeleteCategory',
    ADMIN_CREATE_DEAL  = 'adminCreateDeal',
    ADMIN_EDIT_DEAL    = 'adminEditDeal',
    ADMIN_DELETE_DEAL  = 'adminDeleteDeal',
    ADMIN_CREATE_CODE  = 'adminCreateCode',
    ADMIN_LIST_CODES   = 'adminListCodes',
    ADMIN_DELETE_CODE  = 'adminDeleteCode',
    ADMIN_CLEAR_ALL    = 'adminClearAll',
    ADMIN_SAVE_SETS    = 'adminSaveSettings',
    ADMIN_RESET_SETS   = 'adminResetSettings',
    ADMIN_IMPORT_PREVIEW = 'adminImportPreview',
    ADMIN_IMPORT_RUN     = 'adminImportRun',
}
