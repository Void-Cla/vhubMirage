local VOID = VOID or {}
local Config = VOID.cfg or {}
local Utils = VOID.utils or {}
local Itens = VOID.itens or {}

if Config.player and Config.player.habilitar == false then
    return VOID
end

VOID.player = VOID.player or {}
local Player = VOID.player
Player.cfg = Config.player or {}

local function notify(src, tipo, msg, tempo)
    local notifCfg = Config.notificacoes or {}
    local time = tempo or notifCfg.tempo_exibicao or 5000
    TriggerClientEvent('Notify', src, tipo or 'aviso', msg or '', time)
end

local function sendWebhook(url, message)
    if not url or url == '' then
        return
    end
    PerformHttpRequest(url, function() end, 'POST', json.encode({ content = message }), { ['Content-Type'] = 'application/json' })
end

local function getItemLabel(item)
    local info = Itens[item]
    if info and info.nome then
        return info.nome
    end
    if vRP and vRP.itemNameList then
        return vRP.itemNameList(item)
    end
    return item
end

Player.notify = notify
Player.sendWebhook = sendWebhook
Player.getItemLabel = getItemLabel

function Player.isEnabled()
    return Player.cfg and Player.cfg.habilitar ~= false
end

function Player.getWebhook(key)
    local hooks = Player.cfg.webhooks or {}
    return hooks[key] or ''
end

function Player.safeNumber(value, fallback)
    if Utils.safeNumber then
        return Utils.safeNumber(value, fallback)
    end
    local n = tonumber(value)
    if n == nil then return fallback or 0 end
    return n
end


function VOID.interface.checkRoupas()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end
    if vRP.getInventoryItemAmount(user_id, 'roupas') >= 1 or vRP.hasPermission(user_id, 'platina.permissao') or vRP.hasPermission(user_id, 'seubarriga.permissao') then
        return true
    end
    Player.notify(source, 'negado', 'Voce nao possui Roupas Secundarias na mochila.')
    return false
end
return VOID
