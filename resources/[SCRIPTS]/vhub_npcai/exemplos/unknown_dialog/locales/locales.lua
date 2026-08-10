Locales = {
    ['en'] = {
        -- Buttons
        buy_button = "Buy",
        confirm_button = "Confirm",
        
        -- Messages
        shop_question = "What do you want to buy?",
        enter_amount = "Enter amount",
        total_amount = "Total: $",
        select_payment = "Select payment method",
        purchase_complete = "Purchase complete!",
        not_enough_money = "Not enough money!",
        inventory_full = "Inventory is full!",
        no_items_selected = "No items selected!",
        npc_not_found = "Error: NPC not found!",
        error_adding_items = "Error adding items!",
        error = "Error",
        
        -- Target
        talk = "Talk",
        
        -- Payment methods
        cash = "Cash",
        bank = "Bank"
    },
    ['lt'] = {
        -- Mygtukai
        buy_button = "Pirkti",
        confirm_button = "Patvirtinti",
        
        -- Pranešimai
        shop_question = "Ką norėtumėte įsigyti?",
        enter_amount = "Įveskite kiekį",
        total_amount = "Viso: $",
        select_payment = "Pasirinkite mokėjimo būdą",
        purchase_complete = "Pirkimas sėkmingas!",
        not_enough_money = "Neužtenka pinigų!",
        inventory_full = "Inventorius pilnas!",
        no_items_selected = "Nepasirinkti jokie produktai!",
        npc_not_found = "Klaida: NPC nerastas!",
        error_adding_items = "Klaida pridedant prekes!",
        error = "Klaida",
        
        -- Target
        talk = "Kalbėti",
        
        -- Mokėjimo būdai
        cash = "Grynieji",
        bank = "Bankas"
    }
}

function Locale(key)
    local lang = Config.Locale or 'lt'
    if Locales[lang] and Locales[lang][key] then
        return Locales[lang][key]
    end
    if Locales['lt'] and Locales['lt'][key] then
        return Locales['lt'][key]
    end
    return key
end
