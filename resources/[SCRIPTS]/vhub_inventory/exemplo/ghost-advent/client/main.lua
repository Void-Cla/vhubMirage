local Framework = nil
local FrameworkName = nil
local isMenuOpen = false

Citizen.CreateThread(function()
    Wait(1000)
    
    if GetResourceState('es_extended') == 'started' then
        FrameworkName = 'ESX'
        Framework = exports['es_extended']:getSharedObject()
        print('^2[caticus-advent]^7 ESX Framework Detected')
    elseif GetResourceState('qb-core') == 'started' then
        FrameworkName = 'QBCore'
        Framework = exports['qb-core']:GetCoreObject()
        print('^2[caticus-advent]^7 QBCore Framework Detected')
    else
        print('^1[caticus-advent]^7 WARNING: No framework detected! Advent calendar will work standalone.')
    end
end)

function OpenAdventCalendar(testMode)
    if isMenuOpen then
        return
    end
    
    isMenuOpen = true
    SetNuiFocus(true, true)
    
    TriggerServerEvent('caticus-advent:server:getCalendarData', testMode or false)
end

RegisterNetEvent('caticus-advent:client:receiveCalendarData', function(data, testMode)
    SendNUIMessage({
        action = "openCalendar",
        calendarData = data,
        title = Config.CalendarTitle,
        testMode = testMode or false
    })
end)

function CloseAdventCalendar()
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "closeCalendar"
    })
end

RegisterNUICallback("openDay", function(data, cb)
    local day = tonumber(data.day)
    if day then
        TriggerServerEvent('caticus-advent:server:openDay', day)
    end
    cb("ok")
end)

RegisterNUICallback("closeCalendar", function(data, cb)
    CloseAdventCalendar()
    cb("ok")
end)

RegisterNetEvent('caticus-advent:client:dayOpened', function(day, reward)
    SendNUIMessage({
        action = "dayOpened",
        day = day,
        reward = reward
    })
end)

RegisterNetEvent('caticus-advent:client:alreadyOpened', function(day)
    SendNUIMessage({
        action = "alreadyOpened",
        day = day
    })
end)

RegisterNetEvent('caticus-advent:client:calendarUpdated', function(calendarData)
    SendNUIMessage({
        action = "updateCalendar",
        calendarData = calendarData
    })
end)

exports('OpenAdventCalendar', OpenAdventCalendar)

RegisterCommand('advent', function()
    OpenAdventCalendar(false)
end, false)

RegisterCommand('calendar', function()
    OpenAdventCalendar(false)
end, false)

RegisterCommand('testcal', function()
    OpenAdventCalendar(true)
end, false)

