local VOID = VOID or {}
local Config = VOID.cfg
local Const = VOID.const
local Utils = VOID.utils

if not (Config and Config.compat and Config.compat.habilitar) then
    return VOID
end

VOID.compat = VOID.compat or {}
VOID.compat.original = {
    giveInventoryItem = vRP.giveInventoryItem,
    tryGetInventoryItem = vRP.tryGetInventoryItem,
    removeInventoryItem = vRP.removeInventoryItem,
    itemNameList = vRP.itemNameList,
    itemIndexList = vRP.itemIndexList,
    itemTypeList = vRP.itemTypeList,
    getItemWeight = vRP.getItemWeight,
}

function VOID.syncVrpGiveInventoryItem(user_id, item, amount, slot)
    local original = VOID.compat.original and VOID.compat.original.giveInventoryItem
    if original then
        return original(user_id, item, amount, slot)
    end
    if vRP.giveInventoryItem then
        return vRP.giveInventoryItem(user_id, item, amount, slot)
    end
    return false
end

function VOID.syncVrpTryGetInventoryItem(user_id, item, amount, slot)
    local original = VOID.compat.original and VOID.compat.original.tryGetInventoryItem
    if original then
        return original(user_id, item, amount, slot)
    end
    if vRP.tryGetInventoryItem then
        return vRP.tryGetInventoryItem(user_id, item, amount, slot)
    end
    return false
end

function VOID.syncVrpInventory(user_id)
    local data = vRP.getUserDataTable(user_id)
    if not data then return end

    data.inventory = {}
    local rows = vRP.query('inventario/obter_itens_mochila_agregado', { user_id = user_id })
    local slot = 1
    for _, row in ipairs(rows or {}) do
        local qtd = Utils.safeNumber(row.quantidade, 0)
        if qtd > 0 then
            data.inventory[tostring(slot)] = { item = row.item_name, amount = qtd }
            slot = slot + 1
        end
    end
end

function vRP.giveInventoryItem(user_id, item, amount, slot)
    if not user_id or not item then return false end
    local ok = VOID.adicionarItemSeguro(user_id, item, amount, 'vrp_compat', Const.TIPO_ARMAZENAMENTO.MOCHILA)
    if ok then
        local src = vRP.getUserSource(user_id)
        if src then
            TriggerClientEvent('Inventory:Update', src)
        end
    end
    return ok == true
end

function vRP.tryGetInventoryItem(user_id, item, amount, slot)
    if not user_id or not item then return false end
    local ok = VOID.removerItemSeguro(user_id, item, amount, Const.TIPO_ARMAZENAMENTO.MOCHILA)
    if ok then
        local src = vRP.getUserSource(user_id)
        if src then
            TriggerClientEvent('Inventory:Update', src)
        end
    end
    return ok == true
end

function vRP.removeInventoryItem(user_id, item, amount, notify)
    if not user_id or not item then return false end
    local ok = VOID.removerItemSeguro(user_id, item, amount, Const.TIPO_ARMAZENAMENTO.MOCHILA)
    if ok and notify and vRP.itemBodyList and vRP.itemBodyList(item) then
        local src = vRP.getUserSource(user_id)
        if src then
            TriggerClientEvent("itensNotify", src, {
                "-",
                vRP.itemIndexList(item),
                vRP.format(Utils.safeNumber(amount, 0)),
                vRP.itemNameList(item)
            })
        end
    end
    if ok then
        local src = vRP.getUserSource(user_id)
        if src then
            TriggerClientEvent('Inventory:Update', src)
        end
    end
    return ok == true
end

if Config.compat.sincronizar_spawn then
    AddEventHandler('vRP:playerSpawn', function(user_id, source, first_spawn)
        VOID.syncVrpInventory(user_id)
    end)
end

if Config.compat.sincronizar_online then
    CreateThread(function()
        Wait(2000)
        for _, src in ipairs(GetPlayers()) do
            local user_id = vRP.getUserId(tonumber(src))
            if user_id then
                VOID.syncVrpInventory(user_id)
            end
        end
    end)
end

return VOID
