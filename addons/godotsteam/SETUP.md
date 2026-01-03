# GodotSteam Setup Guide

## Option 1: Use Pre-compiled GodotSteam Editor Build (Recommended)

1. Download the GodotSteam editor from: https://github.com/GodotSteam/GodotSteam/releases
2. Download the version matching your Godot version (4.3+)
3. Extract and use this editor instead of the standard Godot editor
4. The Steam singleton will be automatically available

## Option 2: GDExtension Plugin

1. Download GodotSteam GDExtension from: https://github.com/GodotSteam/GodotSteam/releases
2. Extract the `addons/godotsteam` folder into your project's `addons/` directory
3. Copy the following files to your project root (next to project.godot):
   - `steam_api64.dll` (Windows)
   - `libsteam_api.so` (Linux)
   - `libsteam_api.dylib` (macOS)

## Steam SDK Files

The Steam API library files can be obtained from:
- Steamworks SDK: https://partner.steamgames.com/downloads/steamworks_sdk.zip
- Extract and copy from `sdk/redistributable_bin/`

## Required Files in Project Root

```
project_root/
├── project.godot
├── steam_appid.txt          (Contains: 480 for Spacewar testing)
├── steam_api64.dll          (Windows)
├── libsteam_api.so          (Linux)
└── libsteam_api.dylib       (macOS)
```

## steam_appid.txt

This file should contain your Steam App ID:
- For testing: `480` (Spacewar - Valve's test app)
- For production: Your actual Steam App ID

## Testing

1. Make sure Steam client is running
2. Launch the game from the Godot editor or exported build
3. Check console for "[SteamManager] STEAM INITIALIZED SUCCESSFULLY!"

## Troubleshooting

### "Steam singleton not found"
- You're not using the GodotSteam editor build
- GDExtension not properly installed

### "Steam initialization failed"
- Steam client is not running
- steam_appid.txt is missing or has wrong content
- steam_api64.dll is missing

### Offline Mode
The game will automatically fall back to offline/LAN mode if Steam is unavailable.
