local Framework = {}

function Framework:GetCurrent()
    if Config.Framework == 'esx' and GetResourceState('es_extended') == 'started' then
        return 'esx'
    elseif Config.Framework == 'qb' and GetResourceState('qb-core') == 'started' then
        return 'qb'
    elseif Config.Framework == 'qbox' and GetResourceState('qbx_core') == 'started' then
        return 'qbox'
    end
    return nil
end

function Framework:AddItem(source, itemName, amount, metadata)
    return AddItem(source, itemName, amount, metadata)
end

function Framework:CanCarryItem(source, itemName, amount)
    return CanCarryItem(source, itemName, amount)
end

function Framework:AddMoney(source, account, amount, reason)
    local framework = self:GetCurrent()
    
    if framework == 'qb' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            Player.Functions.AddMoney(account, amount, reason)
            return true
        end
    elseif framework == 'qbox' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            Player.Functions.AddMoney(account, amount, reason)
            return true
        end
    elseif framework == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if account == 'cash' or account == 'money' then
                xPlayer.addMoney(amount)
            elseif account == 'bank' then
                xPlayer.addAccountMoney('bank', amount)
            end
            return true
        end
    end
    return false
end

function Framework:RemoveMoney(source, account, amount, reason)
    local framework = self:GetCurrent()
    
    if framework == 'qb' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            return Player.Functions.RemoveMoney(account, amount, reason)
        end
    elseif framework == 'qbox' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            return Player.Functions.RemoveMoney(account, amount, reason)
        end
    elseif framework == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if account == 'cash' or account == 'money' then
                return xPlayer.removeMoney(amount)
            elseif account == 'bank' then
                return xPlayer.removeAccountMoney('bank', amount)
            end
        end
    end
    return false
end

function Framework:HasMoney(source, account, amount)
    local money = self:GetMoney(source, account)
    return money >= amount
end

function Framework:GetMoney(source, account)
    local framework = self:GetCurrent()

    if Config.Inventory == 'ox_inventory' then
        if account == 'cash' or account == 'money' then
            return GetItemCount(source, 'money')
        elseif account == 'black' or account == 'black_money' then
            return GetItemCount(source, 'black_money')
        end
    end
    
    if framework == 'qb' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            return Player.Functions.GetMoney(account)
        end
    elseif framework == 'qbox' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            return Player.PlayerData.money[account]
        end
    elseif framework == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if account == 'cash' or account == 'money' then
                return xPlayer.getMoney()
            elseif account == 'bank' then
                return xPlayer.getAccount('bank').money
            end
        end
    end
    return 0
end

return Framework