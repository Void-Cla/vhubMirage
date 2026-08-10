function AddItem(source, itemName, amount, metadata)
    if Config.Inventory == 'ox_inventory' then
        return exports.ox_inventory:AddItem(source, itemName, amount, metadata)
    elseif Config.Inventory == 'qb-inventory' then
        local Player = exports['qb-core']:GetCoreObject().Functions.GetPlayer(source)
        if Player then
            return Player.Functions.AddItem(itemName, amount, nil, metadata)
        end
    end
    return false
end

function RemoveItem(source, itemName, amount, metadata, slot)
    if Config.Inventory == 'ox_inventory' then
        return exports.ox_inventory:RemoveItem(source, itemName, amount, metadata, slot)
    elseif Config.Inventory == 'qb-inventory' then
        local Player = exports['qb-core']:GetCoreObject().Functions.GetPlayer(source)
        if Player then
            return Player.Functions.RemoveItem(itemName, amount, slot)
        end
    end
    return false
end

function GetItemCount(source, itemName, metadata)
    if Config.Inventory == 'ox_inventory' then
        return exports.ox_inventory:GetItemCount(source, itemName, metadata) or 0
    elseif Config.Inventory == 'qb-inventory' then
        local Player = exports['qb-core']:GetCoreObject().Functions.GetPlayer(source)
        if Player then
            local item = Player.Functions.GetItemByName(itemName)
            return item and item.amount or 0
        end
    end
    return 0
end

function CanCarryItem(source, itemName, amount)
    if Config.Inventory == 'ox_inventory' then
        return exports.ox_inventory:CanCarryItem(source, itemName, amount)
    elseif Config.Inventory == 'qb-inventory' then
        -- QB doesn't have a direct check, assume true
        return true
    end
    return true
end

function HasItem(source, itemName, amount)
    amount = amount or 1
    return GetItemCount(source, itemName) >= amount
end
