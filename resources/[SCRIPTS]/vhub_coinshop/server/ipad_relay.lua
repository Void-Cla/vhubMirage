-- server/ipad_relay.lua — app CoinShop no iPad (broker vhub_ipad): relay zero-trust + push
--
-- Superfície do JOGADOR (#58/#59): navegar catálogo, comprar item/oferta, resgatar código,
-- test-drive e comprar moedas via Pix (stub com contrato estável até o PSP real).
-- O painel ADMIN não existe aqui — vive na NUI fullscreen via /coinshop.
-- REGRA 1 do manual: corpo em CreateThread (yield não cruza a fronteira C do export).
-- REGRA 2: src é a única identidade; toda ação revalida char + rate server-side.

VHubCoin = VHubCoin or {}
local Core  = VHubCoin.Core
local Coins = VHubCoin.Coins
local Items = VHubCoin.Items
local Purch = VHubCoin.Purchases

local APP_ID = 'coinshop'


-- ============================================================
-- HELPERS — push ao app (owner-binding do broker) + sanitização
-- ============================================================

-- empurra dados de volta ao app do iPad (pcall na fronteira externa — R7)
local function push(src, action, data)
    pcall(function() return exports.vhub_ipad:appPush(src, APP_ID, action, data) end)
end

-- resposta padrão de ação: { ok, action, message }
local function pushResult(src, action, okFlag, message)
    push(src, 'result', { ok = okFlag == true, action = action, message = tostring(message or '') })
end

-- string sã do payload NUI: tostring + trim + cap (anti-DoS de domínio)
local function str(v, cap)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    return s:sub(1, cap or 64)
end


-- ============================================================
-- AÇÕES — cada uma revalida rate + char (zero-trust, L-01)
-- ============================================================

local actions = {}

-- último snapshot servido por src — quando o rate barra, serve o cache em vez de
-- silêncio (o "app abre vazio" do bug (b) #59); limpo em playerDropped
local _lastSnap = {}

-- invalida o snapshot em cache do src (chamado por Coins.notifyChange para garantir
-- que a próxima abertura do iPad após doação/set de coins não sirva dado stale)
function VHubCoin.IpadRelay_InvalidateSnap(src)
    if src then _lastSnap[src] = nil end
end

-- abre o app: snapshot da loja SEM bloco admin (superfície de jogador)
actions.open = function(src, char_id, _)
    if not Core.rate(src, 'openShop', VHubCoin.cfg.rates.openShop) then
        if _lastSnap[src] then
            push(src, 'data', _lastSnap[src])
        else
            pushResult(src, 'open', false, 'Aguarde um instante e tente de novo.')
        end
        return
    end
    local snap = Core.buildShopData(src, char_id, false)
    _lastSnap[src] = snap
    push(src, 'data', snap)
end

-- compra item do catálogo (mesmo domínio da NUI fullscreen — escritor único)
actions.buy_item = function(src, char_id, data)
    if not Core.rate(src, 'purchaseItem', VHubCoin.cfg.rates.purchaseItem) then
        return pushResult(src, 'buy_item', false, T('purchase_in_progress'))
    end
    local itemId = str(data.itemId)
    if not itemId then return pushResult(src, 'buy_item', false, T('item_not_found')) end

    local okBuy, message = Purch.buyItem(src, char_id, itemId)
    pushResult(src, 'buy_item', okBuy, message)
    push(src, 'coins', { coins = Coins.get(char_id) })
end

-- compra oferta promocional
actions.buy_deal = function(src, char_id, data)
    if not Core.rate(src, 'purchaseDeal', VHubCoin.cfg.rates.purchaseDeal) then
        return pushResult(src, 'buy_deal', false, T('purchase_in_progress'))
    end
    local dealId = str(data.dealId)
    if not dealId then return pushResult(src, 'buy_deal', false, T('deal_not_found')) end

    local okBuy, message = Purch.buyDeal(src, char_id, dealId)
    pushResult(src, 'buy_deal', okBuy, message)
    push(src, 'coins', { coins = Coins.get(char_id) })
end

-- resgata código Tebex (targetId opcional = presente para jogador online)
actions.redeem = function(src, char_id, data)
    if not Core.rate(src, 'redeemCode', VHubCoin.cfg.rates.redeemCode) then
        return pushResult(src, 'redeem', false, T('purchase_in_progress'))
    end
    local redeemKey = str(data.redeemKey, 100)
    if not redeemKey then return pushResult(src, 'redeem', false, T('invalid_order_number')) end
    local targetId = str(data.targetId, 8)

    local okRedeem, message = Purch.redeemCode(src, char_id, redeemKey, targetId)
    pushResult(src, 'redeem', okRedeem, message)
    push(src, 'coins', { coins = Coins.get(char_id) })
end

-- compra de moedas via Pix (#60): roteia para o provider real (MercadoPago) ou
-- retorna stub quando cfg.pix.enabled=false.
-- Contrato de resposta estável (front já consome o shape real):
--   ok=true  → { txid, qrcode_base64, copiaECola, expiresAt, coins, amount }
--   ok=false → { code, message }
actions.pix_create = function(src, char_id, data)
    if not Core.rate(src, 'purchaseItem', VHubCoin.cfg.rates.purchaseItem) then
        return push(src, 'pix', { ok = false, code = 'rate', message = T('purchase_in_progress') })
    end

    local packageId = str(data.packageId)
    local pack = nil
    for _, p in ipairs(VHubCoin.cfg.pix.packages) do
        if p.id == packageId then pack = p break end
    end
    if not pack then
        return push(src, 'pix', { ok = false, code = 'pacote_invalido', message = 'Pacote não encontrado.' })
    end

    if VHubCoin.cfg.pix.enabled ~= true then
        return push(src, 'pix', {
            ok = false, code = 'pix_disabled',
            message = 'Pagamento Pix ainda não está habilitado nesta cidade. Fale com a staff.',
        })
    end

    -- provider MercadoPago: delega para pix_mp.lua (carregado antes deste arquivo)
    if VHubCoin.cfg.pix.provider == 'mercadopago' and VHubCoin.Pix and VHubCoin.Pix.handleCreate then
        VHubCoin.Pix.handleCreate(src, char_id, pack, push)
        return
    end

    -- enabled=true mas provider desconhecido = erro de configuração
    Core.logErr('pix_create: cfg.pix.enabled=true mas provider desconhecido: ' .. tostring(VHubCoin.cfg.pix.provider))
    push(src, 'pix', { ok = false, code = 'pix_sem_provider', message = 'Pix indisponível no momento.' })
end

-- test-drive: SERVER valida item/categoria/spawnName ANTES de acionar o efetor client (R1)
actions.testdrive = function(src, char_id, data)
    if not Core.rate(src, 'testDrive', VHubCoin.cfg.rates.testDrive) then
        return pushResult(src, 'testdrive', false, T('purchase_in_progress'))
    end
    local itemId = str(data.itemId)
    local item = itemId and Items.find(itemId) or nil
    if not item or item.category ~= 'vehicle' or not VHubCoin.isNonEmptyStr(item.spawnName) then
        return pushResult(src, 'testdrive', false, T('vehicle_not_found'))
    end
    if VHubCoin.TestDrive._origin[src] ~= nil then
        return pushResult(src, 'testdrive', false, T('test_drive_already_active'))
    end

    pushResult(src, 'testdrive', true, T('test_drive_started_msg'))
    pcall(function() return exports.vhub_ipad:closeIpad(src) end)
    -- spawnName derivado do catálogo SERVER-side — o client nunca escolhe o modelo
    TriggerClientEvent(VHubCoin.E.TESTDRIVE_START, src, item.spawnName)
end


-- ============================================================
-- EXPORT ipadRelay — receptor único das ações do app (broker opaco)
-- ============================================================

exports('ipadRelay', function(src, action, data)
    if type(src) ~= 'number' or not GetPlayerName(src) then return false end
    if type(action) ~= 'string' or not actions[action] then return false end
    data = (type(data) == 'table') and data or {}

    CreateThread(function()                     -- REGRA 1: yield nunca cruza o export
        local ok, err = pcall(function()
            local char_id = Core.getCharId(src) -- REGRA 2: identidade só do server
            if not char_id then
                return push(src, 'denied', { reason = 'sem_char' })
            end
            actions[action](src, char_id, data)
        end)
        if not ok then
            Core.logErr(('ipadRelay %s (src=%s) estourou: %s'):format(action, tostring(src), tostring(err)))
            pushResult(src, action, false, 'falha interna — avise um admin')
        end
    end)

    return true   -- resposta imediata; resultado volta por appPush
end)


-- limpa o snapshot em cache do jogador que saiu (sem leak por src)
AddEventHandler('playerDropped', function()
    _lastSnap[source] = nil
end)
