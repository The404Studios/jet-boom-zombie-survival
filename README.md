# Zombie Survival Shooter

A retro PSX-style zombie survival shooter made in Godot 4.3+

## Features

- **PSX-Style Graphics**: Authentic PlayStation 1 era visuals with vertex snapping, affine texture mapping, and dithering
- **Wave-based Zombie Combat**: Defend the Sigil against increasingly difficult waves of zombies
- **Full Inventory System**: Collect, manage, and equip weapons and items
- **Looting & Extraction**: Find items in the world and extract with your loot at the Sigil
- **Stash System**: Store items between raids
- **Barricade Building**: Fortify positions by placing and repairing barricades
- **Weapon Shop**: Purchase weapons and supplies at the Sigil
- **Optimized Performance**: Locked at 144 FPS for smooth gameplay

## Controls

### Movement
- **W/A/S/D** - Move
- **Shift** - Sprint
- **Space** - Jump
- **Mouse** - Look around

### Combat
- **Left Click** - Shoot
- **R** - Reload

### Interaction
- **E** - Interact (pickup items, repair barricades, access shop)
- **I** - Open/Close Inventory
- **X** - Extract (when at Sigil)

## Gameplay

### Objective
Protect the Sigil in the center of the map from zombie hordes. The Sigil is your safe zone, extraction point, and shop.

### Waves
Zombies spawn in waves with increasing difficulty. Between waves, use the time to:
- Repair barricades
- Buy new weapons
- Transfer loot to your stash

### The Sigil
The glowing blue crystal in the center of the map provides:
- **Protection Zone**: Safe area with 15m radius
- **Shop**: Purchase weapons and supplies
- **Extraction Point**: Press X to extract and save your loot to the stash

### Barricades
Yellow markers around the map indicate barricade spots. Press E to:
- Place a barricade (first time)
- Repair a damaged barricade (subsequent times)

Barricades block zombie movement and can take damage.

### Looting
Items dropped by zombies or found in the world can be picked up by walking over them or pressing E.

## Technical Details

### PSX Shader Features
- Vertex snapping for that authentic jittery look
- Affine texture mapping (no perspective correction)
- Color depth reduction (16 colors)
- Dithering for smooth gradients
- Optional scanlines

### Performance
- Target: 144 FPS locked
- V-Sync disabled for precise frame timing
- Optimized rendering with low-poly models
- Efficient collision detection with proper layer masking

### Collision Layers
1. Environment (walls, floor, props)
2. Player
3. Zombies
4. Items/Loot
5. Barricades
6. Projectiles

## Project Structure

```
├── scenes/
│   ├── main.tscn              # Main game scene
│   ├── player/                # Player character
│   ├── zombies/               # Zombie AI
│   ├── weapons/               # Weapon models
│   ├── items/                 # Loot items
│   ├── environment/           # Props, barricades, sigil
│   └── ui/                    # User interface
├── scripts/
│   ├── player/                # Player controller
│   ├── zombies/               # Zombie AI
│   ├── systems/               # Game systems (inventory, shop, etc.)
│   ├── items/                 # Item data
│   └── weapons/               # Weapon logic
├── resources/
│   ├── items/                 # Item resources
│   └── weapons/               # Weapon resources
└── shaders/
    ├── psx_shader.gdshader    # Main PSX material shader
    └── psx_post_process.gdshader  # Post-processing effects
```

## Assets Used

- PSX Nature Volume 1 - Environment props
- Free Character Pack - Zombie models
- LP Weapons Pack - Weapon models
- KloWorks Food Kit - Loot items

## Development

Built with Godot 4.3+ for maximum compatibility with version 4.5.1

### Requirements
- Godot Engine 4.3 or higher
- Supports Windows, Linux, and macOS

## Credits

Created as a complete zombie survival shooter experience with full systems integration.

## License

See LICENSE file for details.
