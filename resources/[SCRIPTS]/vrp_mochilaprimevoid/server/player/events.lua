local VOID = VOID or {}
local Player = VOID.player or {}

if not Player.isEnabled or not Player.isEnabled() then
    return VOID
end

local cfg = Player.cfg or {}

local veiculos = {}

RegisterServerEvent('salario:pagamento')
AddEventHandler('salario:pagamento', function()
    if not (cfg.salario and cfg.salario.habilitar) then
        return
    end
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then
        return
    end
    local grupos = (cfg.salario and cfg.salario.grupos) or {}
    for _, v in pairs(grupos) do
        if v and v.permissao and vRP.hasPermission(user_id, v.permissao) then
            TriggerClientEvent('vrp_sound:source', source, 'coins', 0.5)
            TriggerClientEvent('Notify', source, 'importante', 'Obrigado por colaborar com a cidade, seu salario de <b>$' .. vRP.format(parseInt(v.pagamento or 0)) .. ' reais</b> foi depositado.')
            vRP.giveBankMoney(user_id, parseInt(v.pagamento or 0))
        end
    end
end)

RegisterServerEvent('TryDoorsEveryone')
AddEventHandler('TryDoorsEveryone', function(veh, doors, placa)
    if placa and not veiculos[placa] then
        TriggerClientEvent('SyncDoorsEveryone', -1, veh, doors)
        veiculos[placa] = true
    end
end)

RegisterServerEvent('kickAFK')
AddEventHandler('kickAFK', function()
    if not (cfg.afk and cfg.afk.habilitar) then
        return
    end
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then
        return
    end
    local imune = (cfg.afk and cfg.afk.permissao_imune) or ''
    if imune ~= '' and vRP.hasPermission(user_id, imune) then
        return
    end
    DropPlayer(source, 'Voce foi desconectado por ficar ausente.')
end)

RegisterServerEvent('trytow')
AddEventHandler('trytow', function(veh, veh2)
    TriggerClientEvent('synctow', -1, veh, veh2)
end)

RegisterServerEvent('trytrunk')
AddEventHandler('trytrunk', function(veh)
    TriggerClientEvent('synctrunk', -1, veh)
end)

RegisterServerEvent('tryhood')
AddEventHandler('tryhood', function(veh)
    TriggerClientEvent('synchood', -1, veh)
end)

RegisterServerEvent('trywins')
AddEventHandler('trywins', function(veh)
    TriggerClientEvent('syncwins', -1, veh)
end)

RegisterServerEvent('trydoors')
AddEventHandler('trydoors', function(veh, door)
    TriggerClientEvent('syncdoors', -1, veh, door)
end)

RegisterServerEvent('tryreparar')
AddEventHandler('tryreparar', function(veh)
    TriggerClientEvent('syncreparar', -1, veh)
end)

RegisterServerEvent('trymotor')
AddEventHandler('trymotor', function(veh)
    TriggerClientEvent('syncmotor', -1, veh)
end)

RegisterServerEvent('ChatMe')
AddEventHandler('ChatMe', function(text)
    local user_id = vRP.getUserId(source)
    if user_id then
        TriggerClientEvent('DisplayMe', -1, text, source)
    end
end)

RegisterServerEvent('ChatRoll')
AddEventHandler('ChatRoll', function(text)
    local user_id = vRP.getUserId(source)
    if user_id then
        TriggerClientEvent('DisplayRoll', -1, text, source)
    end
end)

RegisterServerEvent('carafazendomerda')
AddEventHandler('carafazendomerda', function()
    local user_id = vRP.getUserId(source)
    if not user_id then
        return
    end
    local name = GetPlayerName(source) or 'n/a'
    local data = os.date('%d-%m-%Y %H:%M:%S')
    local msg = 'Usuario [ID: ' .. user_id .. '] [STEAM: ' .. name .. '] foi pego tentando bugar no banco central. Data: ' .. data
    Player.sendWebhook(Player.getWebhook('bancocentral_bug'), msg)
end)

return VOID

RegisterServerEvent('tryDeleteEntity')
AddEventHandler('tryDeleteEntity', function(netId)
    TriggerClientEvent('deleteEntity', -1, netId)
end)

RegisterServerEvent('trymala')
AddEventHandler('trymala', function(veh)
    TriggerClientEvent('synctrunk', -1, veh)
end)

RegisterServerEvent('cmg2_animations:sync')
AddEventHandler('cmg2_animations:sync', function(target, animationLib, animationLibTarget, animation, animationTarget, distans, distans2, height, targetSrc, length, spin, controlFlagMe, controlFlagTarget, animFlagTarget)
    TriggerClientEvent('cmg2_animations:syncTarget', target, source, animationLibTarget or animationLib, animationTarget, distans, distans2, height, length, spin, controlFlagTarget)
    TriggerClientEvent('cmg2_animations:syncMe', source, animationLib, animation, length, controlFlagMe, animFlagTarget)
end)

RegisterServerEvent('cmg2_animations:stop')
AddEventHandler('cmg2_animations:stop', function(targetSrc)
    TriggerClientEvent('cmg2_animations:cl_stop', targetSrc)
end)
