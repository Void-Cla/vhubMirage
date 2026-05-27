local VOID = VOID or {}
local Player = VOID.player or {}

if not Player.isEnabled or not Player.isEnabled() then
    return VOID
end

local vRPPrime = VOID.interface
local cfg = Player.cfg or {}
local garmasCfg = cfg.garmas or {}

local numsrc = nil
local IsCounting = 0

RegisterServerEvent('suricato:source:register')
AddEventHandler('suricato:source:register', function(src)
    numsrc = src
    IsCounting = garmasCfg.aviso_segundos or 14
end)

RegisterServerEvent('suricato:source:unregister')
AddEventHandler('suricato:source:unregister', function()
    numsrc = nil
    IsCounting = 0
end)

AddEventHandler('playerDropped', function()
    local source = source
    if IsCounting > 0 and numsrc == source and garmasCfg.banir ~= false then
        local idban = vRP.getUserId(numsrc)
        if idban then
            vRP.setBanned(idban, true)
            Player.sendWebhook(Player.getWebhook('garmas_ban'), 'O ID ' .. idban .. ' tentou sair durante o /garmas e foi banido.')
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if IsCounting > 0 then
            IsCounting = IsCounting - 1
        end
        if IsCounting == 0 and numsrc ~= nil then
            TriggerEvent('suricato:source:unregister')
        end
    end
end)

function vRPPrime.getGarmas()
    if IsCounting == 0 then
        return true
    end
    return IsCounting
end

RegisterServerEvent('garmas:suricato')
AddEventHandler('garmas:suricato', function()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return end
    local identity = vRP.getUserIdentity(user_id) or {}

    local weapons = vRPclient.replaceWeapons(source, {})
    for k, v in pairs(weapons or {}) do
        vRP.giveInventoryItem(user_id, 'wbody|' .. k, 1)
        if v.ammo and v.ammo > 0 then
            vRP.giveInventoryItem(user_id, 'wammo|' .. k, v.ammo)
        end
        Player.sendWebhook(Player.getWebhook('garmas_tentativa'), '[ID]: ' .. user_id .. ' GUARDOU ' .. k .. ' AMMO: ' .. tostring(v.ammo or 0))
    end
end)

return VOID
