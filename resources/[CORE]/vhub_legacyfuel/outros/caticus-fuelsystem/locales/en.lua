local Translations = {
    info = {
        pickup_pump = "Pickup/Replace Pump",
        buy_jerrican = "Buy/Refill Jerrican",
        mount_pump = "[~g~E~w~] Mount",
        dismount_pump = "[~r~E~w~] Dismount",
        blip_fuel = "Gas Station",
        blip_electric = "Electric Charger",
    },
    message = {
        jerrican_refilled = "Jerrican refilled",
        jerrican_full = "Jerrican full",
        jerrican_bought = "Jerrican bought",
        no_money = "You have not enough money",
        must_be_driver = "You must be driver to do that",
        to_far_away = "You are to far away, the hose snapped"
    }
}

-- Update Lang with translations
if Lang then
    Lang.phrases = Translations
else
    Lang = Locale:new({
        phrases = Translations,
        warnOnMissing = true
    })
end
