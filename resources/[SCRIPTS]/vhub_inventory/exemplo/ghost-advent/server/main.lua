local Framework = nil
local FrameworkName = nil

Citizen.CreateThread(function()
    Wait(1000)
    
    if GetResourceState('es_extended') == 'started' then
        FrameworkName = 'ESX'
        Framework = exports['es_extended']:getSharedObject()
        print('^2[caticus-advent]^7 ESX Framework Detected (Server)')
    elseif GetResourceState('qb-core') == 'started' then
        FrameworkName = 'QBCore'
        Framework = exports['qb-core']:GetCoreObject()
        print('^2[caticus-advent]^7 QBCore Framework Detected (Server)')
    else
        print('^1[caticus-advent]^7 WARNING: No framework detected! Server-side features disabled.')
    end
end)

RegisterNetEvent('caticus-advent:server:getCalendarData', function(testMode)
    local src = source
    local xPlayer = nil
    local citizenid = nil
    
    if FrameworkName == 'ESX' then
        xPlayer = Framework.GetPlayerFromId(src)
        if xPlayer then
            citizenid = xPlayer.identifier
        end
    elseif FrameworkName == 'QBCore' then
        local Player = Framework.Functions.GetPlayer(src)
        if Player then
            citizenid = Player.PlayerData.citizenid
        end
    end
    
    if not citizenid then
        TriggerClientEvent('caticus-advent:client:receiveCalendarData', src, {}, testMode or false)
        return
    end
    
    local result = MySQL.query.await('SELECT * FROM advent_calendar WHERE citizenid = ?', {citizenid})
    local openedDays = {}
    
    if result and #result > 0 then
        for _, row in ipairs(result) do
            openedDays[tostring(row.day)] = true
        end
    end
    
    TriggerClientEvent('caticus-advent:client:receiveCalendarData', src, openedDays, testMode or false)
end)

RegisterNetEvent('caticus-advent:server:openDay', function(day)
    local src = source
    local xPlayer = nil
    local citizenid = nil
    
    if FrameworkName == 'ESX' then
        xPlayer = Framework.GetPlayerFromId(src)
        if not xPlayer then return end
        citizenid = xPlayer.identifier
    elseif FrameworkName == 'QBCore' then
        local Player = Framework.Functions.GetPlayer(src)
        if not Player then return end
        citizenid = Player.PlayerData.citizenid
        xPlayer = Player
    else
        return
    end
    
    if not Config.Days[day] then
        return
    end
    
    local check = MySQL.query.await('SELECT * FROM advent_calendar WHERE citizenid = ? AND day = ?', {citizenid, day})
    
    if check and #check > 0 then
        TriggerClientEvent('caticus-advent:client:alreadyOpened', src, day)
        return
    end
    
    local reward = Config.Days[day]
    local rewardText = ""
    
    if reward.item then
        if FrameworkName == 'ESX' then
            xPlayer.addInventoryItem(reward.item, reward.amount)
        elseif FrameworkName == 'QBCore' then
            xPlayer.Functions.AddItem(reward.item, reward.amount)
        end
        rewardText = rewardText .. reward.amount .. "x " .. reward.item
    end
    
    if reward.cash > 0 then
        if FrameworkName == 'ESX' then
            xPlayer.addMoney(reward.cash)
        elseif FrameworkName == 'QBCore' then
            xPlayer.Functions.AddMoney('cash', reward.cash)
        end
        if rewardText ~= "" then rewardText = rewardText .. ", " end
        rewardText = rewardText .. "$" .. reward.cash .. " cash"
    end
    
    if reward.bank > 0 then
        if FrameworkName == 'ESX' then
            xPlayer.addAccountMoney('bank', reward.bank)
        elseif FrameworkName == 'QBCore' then
            xPlayer.Functions.AddMoney('bank', reward.bank)
        end
        if rewardText ~= "" then rewardText = rewardText .. ", " end
        rewardText = rewardText .. "$" .. reward.bank .. " bank"
    end
    
    MySQL.insert('INSERT INTO advent_calendar (citizenid, day, opened_date) VALUES (?, ?, NOW())', {
        citizenid,
        day
    })
    
    local calendarData = MySQL.query.await('SELECT day FROM advent_calendar WHERE citizenid = ?', {citizenid})
    local openedDays = {}
    if calendarData then
        for _, row in ipairs(calendarData) do
            openedDays[tostring(row.day)] = true
        end
    end
    
    TriggerClientEvent('caticus-advent:client:dayOpened', src, day, rewardText)
    TriggerClientEvent('caticus-advent:client:calendarUpdated', src, openedDays)
    
    if FrameworkName == 'ESX' then
        TriggerClientEvent('esx:showNotification', src, 'Day ' .. day .. ' opened! You received: ' .. rewardText, 'success')
    elseif FrameworkName == 'QBCore' then
        TriggerClientEvent('QBCore:Notify', src, 'Day ' .. day .. ' opened! You received: ' .. rewardText, 'success')
    end
end)

