# Ghost Fuel Script

A comprehensive fuel management system for FiveM servers, supporting both ESX and QBCore frameworks. This script provides realistic fuel management with visual rope attachments when refueling vehicles.

## Features

- 🔄 Free Open Source Script Created by 5M Servers
- ⛽ Realistic fuel management system
- 🎮 Visual rope attachment when refueling
- 💰 Configurable fuel prices
- 🗺️ Customizable fuel station locations
- 📱 Clean notification system
- 🔧 Easy configuration
- 🌐 Multi-language support

## Dependencies

- ESX or QBCore framework
- oxmysql

## ⚠️ Important Prerequisites

Before installing ghost-fuel, you MUST:

1. Remove any existing fuel scripts from your server:
   - LegacyFuel
   - ps-fuel
   - cd_fuel
   - or any other fuel management scripts

2. Update your HUD configuration:
   - Most HUDs use exports to display fuel levels
   - You will need to update your HUD's fuel export to use ghost-fuel's export
   - Common export format: `exports['ghost-fuel']:GetFuel(vehicle)`

Failure to remove conflicting scripts or update HUD exports may result in:
- Multiple fuel systems running simultaneously
- Incorrect fuel level display
- Script conflicts
- Server performance issues

## Installation

1. Download the latest version of ghost-fuel
2. Extract the files to your resources folder
3. Remove any existing fuel scripts from your server.cfg
4. Import the `database.sql` to your database
5. Add `ensure ghost-fuel` to your server.cfg
6. Configure the `config.lua` to your preferences
7. Update your HUD's fuel export (see HUD Configuration below)
8. Restart your server

## HUD Configuration

### Export Usage
To integrate with your HUD, use the following export:
```lua
-- In your HUD script, replace the existing fuel export with:
local fuel = exports['ghost-fuel']:GetFuel(vehicle)
```

### Common HUD Examples
1. ps-hud:
```lua
local function UpdateFuel(vehicle)
    local fuel = exports['ghost-fuel']:GetFuel(vehicle)
    SendNUIMessage({
        action = "update",
        fuel = fuel,
    })
end
```

2. qb-hud:
```lua
local function UpdateVehicleHud(vehicle)
    local fuel = exports['ghost-fuel']:GetFuel(vehicle)
    SendNUIMessage({
        action = "updateVehicle",
        fuel = fuel,
    })
end
```

## Configuration

### Framework Selection
Open `config.lua` and set your preferred framework:
```lua
Config.Framework = "ESX" -- or "QBCORE"
```

### Fuel Settings
```lua
Config.FuelDecor = "_FUEL_LEVEL" -- Don't change unless you know what you're doing
Config.FuelUsage = 1.0 -- Adjust fuel consumption rate
Config.RefuelTime = 1000 -- Time in ms for refueling
```

### Price Configuration
```lua
Config.PricePerLiter = 1.0 -- Adjust the price per liter of fuel
```

## Usage

### For Players
1. Drive to any fuel station
2. Exit your vehicle
3. Approach the fuel pump
4. Press [E] to start refueling
5. Wait for the refueling process to complete
6. Pay the calculated amount

### For Administrators
- All fuel stations are configurable in the `config.lua` file
- Prices and usage rates can be adjusted in real-time
- Multiple language support available in the `locales` folder

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Credits

Created by 5M Servers
Special thanks to the FiveM community for their contributions and support.

## Changelog

### v1.0.0
- Initial release
- Dual framework support
- Basic fuel management system

### v1.1.0
- Added rope attachment visuals
- Improved performance
- Bug fixes 