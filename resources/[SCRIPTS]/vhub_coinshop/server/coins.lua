-- server/coins.lua — moedas do coinshop: cache VRAM-first, escrita por CData (L-13, R3)

VHubCoin = VHubCoin or {}
local Core = VHubCoin.Core
local Coins = {}
VHubCoin.Coins = Coins


-- cache VRAM: [char_id] = saldo (inteiro >= 0)
local _cache = {}

-- lock anti-double-spend: [char_id] = true enquanto uma compra está em andamento
local _locks = {}


-- retorna saldo de moedas do personagem (cache-first, fallback CData→SQL via core)
function Coins.get(char_id)
    if not char_id then return 0 end
    if _cache[char_id] ~= nil then return _cache[char_id] end

    local ok, value = pcall(exports.vhub.getCData, char_id, 'coinshop_coins')
    local cached = ok and tonumber(value) or 0
    _cache[char_id] = cached
    return cached
end


-- define saldo (escrita por CData — batch do core; cache local sincronizado)
function Coins.set(char_id, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    _cache[char_id] = amount
    pcall(exports.vhub.setCData, char_id, 'coinshop_coins', amount)
    return amount
end


-- tenta debitar `amount` moedas; em SUCESSO o lock permanece ADQUIRIDO até o
-- call-site chamar releaseLock (cobre toda a janela débito→entrega, que tem yields
-- de export cross-resource — sem isso duplo-clique/concorrência entrega 2x por 1 débito).
-- Em FALHA (lock ativo ou saldo insuficiente) o lock não é retido.
function Coins.tryDebit(char_id, amount)
    if not char_id or not amount or amount <= 0 then return false end
    if _locks[char_id] then return false end
    _locks[char_id] = true

    local current = Coins.get(char_id)
    if current < amount then
        _locks[char_id] = nil
        return false
    end

    Coins.set(char_id, current - amount)
    return true   -- lock RETIDO; liberação é responsabilidade do call-site (releaseLock)
end


-- credita `amount` moedas (atomicamente)
function Coins.credit(char_id, amount)
    if not char_id or not amount or amount <= 0 then return false end
    local current = Coins.get(char_id)
    Coins.set(char_id, current + amount)
    return true
end


-- libera o lock de compra de um personagem (em caso de erro antes do debit)
function Coins.releaseLock(char_id)
    if char_id then _locks[char_id] = nil end
end


-- retorna true se o personagem está em lock de compra (para anti-double-click)
function Coins.isLocked(char_id)
    return _locks[char_id] == true
end


-- notifica o cliente que o saldo mudou (discreto; não é estado contínuo)
function Coins.notifyChange(src, char_id)
    if not src or not char_id then return end
    TriggerClientEvent(VHubCoin.E.COINS_CHANGED, src, Coins.get(char_id))
end


-- limpa cache ao desconectar (evita leak e dado stale de outra sessão)
function Coins.onPlayerDropped(src)
    local sess = Core.sessions[src]
    if sess and sess.char_id then
        _cache[sess.char_id] = nil
        _locks[sess.char_id] = nil
    end
end
