Config = {}

-- Framework
Config.Framework = 'qbox' -- 'esx', 'qb'

-- Inventory
Config.Inventory = 'ox_inventory' -- 'ox_inventory', 'qb-inventory'

-- Target
Config.Target = 'ox_target' -- 'ox_target', 'qb-target'

Config.Locale = 'en'  -- 'lt', 'en'

-- NPC spawn locations with dialog configs
Config.NPCs = {
    -- ============================================
    -- EXAMPLE 1: Shop NPC (with purchasing)
    -- ============================================
    {
        model = 'a_m_m_business_01',
        coords = vector4(372.9399, 328.1881, 103.5664, 247.5445),
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        
        npcInfo = {
            name = "Mike",
            specifier = "General Store Clerk"
        },
        
        targetLabel = "Talk",
        targetIcon = "fas fa-comments",
        targetDistance = 2.5,
        
        -- Initial dialog
        dialog = {
            question = "Welcome to Mike's General Store! How can I help you?",
            answers = {
                { id = "pos_buy", label = "I want to buy something", icon = "basket-shopping" },
                { id = "neg_leave", label = "Just looking around", icon = "eye" }
            }
        },
        
        -- Shop items
        shopItems = {
            { name = "beer", label = "Beer", price = 5, imageUrl = "nui://ox_inventory/web/images/beer.png" },
            { name = "water", label = "Water", price = 3, imageUrl = "nui://ox_inventory/web/images/water.png" },
            { name = "burger", label = "Burger", price = 10, imageUrl = "nui://ox_inventory/web/images/burger.png" },
            { name = "sandwich", label = "Sandwich", price = 8, imageUrl = "nui://ox_inventory/web/images/sandwich.png" }
        },
        
        paymentMethods = {
            { id = "cash", label = "Cash", icon = "money-bill-wave" },
            { id = "bank", label = "Bank", icon = "credit-card" }
        }
    },

    -- ============================================
    -- EXAMPLE 2: Information NPC (with actions)
    -- ============================================
    {
        model = 'a_f_y_business_01',
        coords = vector4(-506.2957, -199.3562, 34.2152, 302.2597),
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        
        npcInfo = {
            name = "Sarah",
            specifier = "Helper"
        },
        
        targetLabel = "Talk",
        targetIcon = "fas fa-info-circle",
        targetDistance = 2.5,
        
        dialog = {
            question = "Hello! I'm Sarah. How can I help you?",
            answers = {
                { 
                    id = "pos_cityhall", 
                    label = "Open City Hall", 
                    icon = "city",

                    action = {
                        type = "export",           -- Type: event, serverEvent, export, command
                        resource = "qbx_cityhall", -- Resource name
                        name = "openCityhallMenu", -- Export function name
                    }
                },
                { 
                    id = "pos_vip", 
                    label = "Open VIP menu", 
                    icon = "crown",
                    action = {
                        type = "command",
                        name = "vip",
                    }
                },
                { 
                    -- Submenu
                    id = "pos_more", 
                    label = "More", 
                    icon = "circle-info",
                    nextDialog = {
                        question = "What information are you looking for?",
                        answers = {
                            { 
                                id = "rules", 
                                label = "Server rules", 
                                icon = "scale-balanced",
                                action = {
                                    type = "event",
                                    name = "chat:addMessage",
                                    args = { color = {255, 200, 0}, args = {"System", "Rules can be found at: unknown-development.tebex.io/"} }
                                }
                            },
                            { 
                                id = "hud", 
                                label = "Open HUD settings", 
                                icon = "gear",
                                action = {
                                    type = "command",
                                    name = "hud"
                                }
                            },
                            { id = "neg_back", label = "Go back", icon = "arrow-left" }
                        }
                    }
                },
                { id = "neg_leave", label = "Goodbye", icon = "hand-peace" }
            }
        }
    },

    -- ============================================
    -- EXAMPLE 3: Confirmation dialog
    -- ============================================
    {
        model = 'a_m_y_business_02',
        coords = vector4(678.0487, -912.8828, 23.4620, 349.7429),
        scenario = 'WORLD_HUMAN_STAND_MOBILE',
        
        npcInfo = {
            name = "Tom",
            specifier = "Dealer"
        },
        
        targetLabel = "Contact",
        targetIcon = "fas fa-landmark",
        targetDistance = 2.5,
        
        dialog = {
            question = "Hello, how can I help you?",
            answers = {
                { 
                    id = "pos_job", 
                    label = "I want to get some 'job'", 
                    icon = "mask",
                    nextDialog = {
                        question = "Okay, i have some job. Are you sure you want it?",
                        answers = {
                            { 
                                id = "pos_confirm", 
                                label = "Yes", 
                                icon = "check",
                                action = {
                                    type = "command",
                                    name = "giveitem 3 stickynote",
                                    args = { }
                                }
                            },
                            { id = "neg_cancel", label = "No, I changed my mind", icon = "xmark" }
                        }
                    }
                },
                { id = "neg_leave", label = "Nothing needed", icon = "door-open" }
            }
        }
    }
}

Config.Debug = true