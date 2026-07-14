-- server/pix_df.lua — ponte coinshop → vhub_df (gateway Pix central)
--
-- Papel: o coinshop NÃO fala mais com o MercadoPago quando cfg.pix.provider='vhub_df'.
-- Ele registra o handler 'coins' no gateway e cria cobranças via export gated.
-- O vhub_df re-verifica status E valor na API do MP, garante entrega única (lock
-- atômico) e re-tenta em falha — este arquivo só credita e sincroniza a UI.

VHubCoin = VHubCoin or {}
local Core  = VHubCoin.Core
local Coins = VHubCoin.Coins

local PixDF = {}
VHubCoin.PixDF = PixDF


-- ============================================================
-- HELPERS
-- ============================================================

-- resolve o src online de um char_id (nil se offline) — O(n) só na entrega
local function srcByChar(charId)
    for _, id in ipairs(GetPlayers()) do
        local pid = tonumber(id)
        if pid and Core.getCharId(pid) == charId then return pid end
    end
    return nil
end


-- ============================================================
-- ENTREGA — handler 'coins' chamado pelo vhub_df após aprovação
-- ============================================================

-- credita as moedas do pedido aprovado; done(false) faz o gateway re-tentar depois
local function deliverCoins(charId, orderId, meta, done)
    local coinsToAdd = meta and tonumber(meta.coins) or nil
    if not coinsToAdd or coinsToAdd <= 0 or coinsToAdd > 1000000 then
        return done(false, 'meta.coins invalido (order ' .. tostring(orderId) .. ')')
    end
    coinsToAdd = math.floor(coinsToAdd)

    if not Coins.credit(charId, coinsToAdd) then
        return done(false, 'credito falhou — gateway re-tenta')
    end

    -- sincroniza jogador online: saldo, toast e checkout aberto no iPad
    local src = srcByChar(charId)
    if src then
        Coins.notifyChange(src, charId)
        Core.notify(src, ('Pix aprovado! +%d moedas na sua conta.'):format(coinsToAdd), 'success')
        pcall(function()
            exports.vhub_ipad:appPush(src, 'coinshop', 'pix_paid', {
                coins      = coinsToAdd,
                newBalance = Coins.get(charId),
            })
        end)
        VHubCoin.IpadRelay_InvalidateSnap(src)
    end

    Core.log('pix_df: entrega ok', charId, coinsToAdd, 'order', orderId)
    done(true, 'creditado')
end


-- ============================================================
-- REGISTRO NO GATEWAY (re-registra se o vhub_df reiniciar)
-- ============================================================

-- registra o handler 'coins' no vhub_df com retry — no boot o gateway (ou o convar
-- de trust) pode ainda não estar pronto; re-tenta a cada 2s por até 60s
local _registered = false

local function tryRegister()
    if _registered then return end
    local ok, res = pcall(function()
        return exports.vhub_df:registerHandler('coins', deliverCoins)
    end)
    if ok and res == true then
        _registered = true
        Core.log('pix_df: handler coins registrado no vhub_df')
    end
end

local function registerWithRetry()
    Citizen.CreateThread(function()
        for attempt = 1, 30 do
            tryRegister()
            if _registered then return end
            Citizen.Wait(2000)
        end
        Core.logErr('pix_df: registro no vhub_df falhou após 60s (gateway parado ou fora do trust)')
    end)
end

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        registerWithRetry()
    elseif res == 'vhub_df' then
        _registered = false   -- gateway reiniciou: handlers foram limpos lá
        registerWithRetry()
    end
end)


-- ============================================================
-- CRIAÇÃO — cobrança nasce no gateway; QR volta para o app do iPad
-- ============================================================

-- cria a cobrança do pacote no vhub_df e devolve QR/copia-e-cola pelo push do relay
-- (contrato 'pix' do coinshop.js: qrcode_base64, copiaECola, expiresAt, coins, amount)
function PixDF.handleCreate(src, char_id, pack, push)
    -- garante o handler ANTES de criar a cobrança: se o registro do boot se perdeu
    -- (restart fora de ordem), este é o último ponto seguro para refazê-lo
    if not _registered then tryRegister() end

    local totalCoins = math.floor((tonumber(pack.coins) or 0) + (tonumber(pack.bonus) or 0))

    local ok = pcall(function()
        exports.vhub_df:createPayment(src, {
            amountBRL   = pack.priceBRL,
            productKey  = 'coins:' .. tostring(pack.id),
            productDesc = ('%s — %d moedas vHub'):format(pack.name or pack.id, totalCoins),
            metadata    = { coins = totalCoins, packId = pack.id },
            openNui     = false,   -- o QR aparece DENTRO do app do iPad, não na NUI do df
        }, function(okCreate, result)
            if okCreate then
                push(src, 'pix', {
                    ok            = true,
                    txid          = result.txid,
                    qrcode_base64 = result.qrBase64,
                    copiaECola    = result.copiaECola,
                    expiresAt     = result.expiresAt,
                    coins         = totalCoins,
                    amount        = result.amountBRL,
                })
            else
                push(src, 'pix', {
                    ok      = false,
                    code    = result and result.code or 'df_erro',
                    message = result and result.message or 'Falha ao criar a cobrança Pix.',
                })
            end
        end)
    end)

    if not ok then
        push(src, 'pix', {
            ok = false, code = 'df_off',
            message = 'Gateway de pagamento indisponível no momento. Avise a staff.',
        })
    end
end
