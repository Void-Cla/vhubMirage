# Caticus Chairs - Sit on Every Chair

![preview](https://github.com/user-attachments/assets/ec5a98c3-4ff3-44f1-9462-2ee381a1a03e)

**Sit on every chair** - A standalone FiveM script that allows players to seamlessly sit on any chair or seating object in the game. Features a custom NoPixel-style UI prompt and automatic framework detection.

## Features

- ✅ **Standalone** - No dependencies on qb-target or ox_target
- ✅ **Custom UI** - Modern NoPixel-style prompt interface
- ✅ **Framework Support** - Auto-detects ESX, QBCore, and QBox (works standalone too)
- ✅ **177+ Chair Models** - Supports virtually any chair, bench, or seat in the game
- ✅ **Easy Interaction** - Simply walk near a chair and press E to sit
- ✅ **Smooth Animations** - Realistic sitting animations and camera transitions
- ✅ **Performance Optimized** - Efficient detection system with caching

## Framework Compatibility

| Framework | Status |
| --- | --- |
| ESX | ✅ Fully Supported |
| QBCore | ✅ Fully Supported |
| QBox | ✅ Fully Supported |
| Standalone | ✅ Works without framework |

The script automatically detects your framework on startup - no configuration needed!

## Installation

1. Copy the `caticus-chairs` folder to your `resources` directory
2. Add `ensure caticus-chairs` to your `server.cfg`
3. Restart your server

That's it! No database setup or additional dependencies required.

## Usage

### For Players

- **Sit**: Walk near any chair and press `E` when the prompt appears
- **Stand Up**: Press `E`, `X`, or `SPACE` while sitting

### Configuration

Edit `config.lua` to customize:

```lua
Config.PromptKey = "E" -- Key to interact (shown in prompt)
Config.PromptDistance = 2.0 -- Distance to show prompt
Config.PromptText = "Sit" -- Text shown when near chair
Config.PromptTextStandUp = "Stand Up" -- Text shown when sitting
Config.FirstPersonOnSit = true -- Enable first person view when sitting
```

## How It Works

- Uses raycasting and sphere detection to find nearby chairs
- Shows a modern NoPixel-style UI prompt when near a chair
- Automatically handles sitting animations and camera positioning
- Supports all 177+ chair models included in the config

## Commands

- `/caticus:sit:stand_up` - Stand up from chair
- Key mappings: `X` or `SPACE` can also be used to stand up

## Technical Details

- **No Dependencies**: Completely standalone, no qb-target or ox_target required
- **Performance**: Optimized object detection with caching
- **Framework Detection**: Automatically detects ESX, QBCore, or QBox on startup
- **Custom UI**: Clean, modern NoPixel-style prompt interface

## Credits

- Original concept by Nevera Development
- Updated and enhanced by Caticus
- Powered by 5Mservers.com

## Support

For support and updates, visit: www.5Mservers.com

---

**Made by Caticus** | **Powered by 5Mservers.com**
