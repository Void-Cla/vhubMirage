# Caticus Fuel System

A free fuel system for FiveM with realistic fuel hoses, electric vehicle support, and HUD integration.

**Made by caticus | Powered by www.5Mservers.com**

## Features

- Multi-Framework Support (ESX, QBCore, QBox)
- Realistic fuel hoses with 3D display
- Electric vehicle charging stations
- Jerry can system
- Target system integration (qb-target/ox_target)
- HUD compatible (legacy-fuel export pattern)

## Installation

1. Extract to your `resources` folder
2. Add `ensure caticus-fuelsystem` to `server.cfg`
3. Restart server

### Dependencies

- `oxmysql` (QBCore/QBox only)
- `qb-target` or `ox_target` (optional, auto-detected)

## Configuration

Edit `config.lua` to customize:

```lua
Config.LiterPrice = 1.7          -- Price per liter
Config.KwPrice = 0.3              -- Price per kW (electric)
Config.DefaultTankSize = 70.0     -- Default tank size
Config.JerryCanCost = 100         -- Jerry can price
Config.TargetSystem = 'auto'      -- 'auto', 'qb-target', 'ox_target'
```

Add custom tank sizes and electric vehicles in `config.lua` as needed.

## HUD Integration

This script uses the same export pattern as `legacy-fuel`, making it compatible with most HUD systems.

### Export Functions

```lua
-- Get fuel level (0-100%)
local fuel = exports['caticus-fuelsystem']:GetFuel(vehicle)

-- Set fuel level (0-100%)
exports['caticus-fuelsystem']:SetFuel(vehicle, 50)

-- Apply fuel (alternative method)
exports['caticus-fuelsystem']:ApplyFuel(vehicle, 75)
```

### Adding to Your HUD

If your HUD doesn't auto-detect this script, add this check to your HUD's fuel export function:

**Example for most HUDs:**

```lua
function GetFuelLevel(vehicle)
    -- Check for caticus-fuelsystem first
    if GetResourceState("caticus-fuelsystem") == "started" then
        local fuel = exports["caticus-fuelsystem"]:GetFuel(vehicle)
        if fuel and fuel >= 0 then
            return fuel
        end
    end
    
    -- Fallback to other fuel systems or native
    -- ... your existing code ...
end
```

**Common HUD locations to modify:**
- `client/functions.lua` - Look for fuel export functions
- `client/utils.lua` - Check for custom fuel exports
- `client/main.lua` - Search for fuel-related functions

The export returns fuel as a percentage (0-100), same as legacy-fuel.

## Usage

1. Drive to a gas station (marked on map)
2. Approach fuel pump
3. Use target system or press E → "Pickup Pump"
4. Attach hose to vehicle fuel cap
5. Hold E to fuel, release to stop
6. Return pump when done

**Electric Vehicles:** Use charging stations (blue blips) instead of gas stations.

**Jerry Cans:** Buy at any pump, use to fuel vehicles away from stations.

## Commands

- `/fuel [amount]` - Set fuel level (admin only, QBCore/QBox)

## Troubleshooting

**Fuel not showing in HUD:**
- Ensure `caticus-fuelsystem` is started
- Add manual detection to your HUD (see HUD Integration above)
- Check your HUD supports legacy-fuel exports

**Target system not working:**
- Ensure `qb-target` or `ox_target` is installed
- Set `Config.TargetSystem = 'auto'` in config

**Fuel not decreasing:**
- Check vehicle isn't in `Config.Blacklist`
- Verify engine is running
- Check fuel usage configs

## Support

Visit: **www.5Mservers.com**

## License

Free to use on your server.

---

**Made by caticus | Powered by www.5Mservers.com**
