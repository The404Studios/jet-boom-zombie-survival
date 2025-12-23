# Gameplay Systems Overview

This document provides an overview of all the gameplay systems implemented for the JetBoom-style zombie survival shooter.

## Core JetBoom Mechanics

### 1. Sigil Protection System
**File:** `scripts/systems/sigil_protector.gd`
**Scene:** `scenes/systems/sigil.tscn`

- Primary zombie objective
- Health scales with wave number (10000 + 2000*wave)
- Visual feedback (blue → yellow → red based on health%)
- Emission glow intensifies when critical
- 3D health label display
- Game over when destroyed

**Zombie Priority:** #1 Target

### 2. Prop System
**File:** `scripts/systems/prop_system.gd`
**Scenes:** `scenes/props/prop_crate.tscn`, `scenes/props/prop_barrel.tscn`

- Secondary zombie targets
- Health scales with wave (500 + 100*wave base)
- 3D health bar appears when damaged
- Z-key phasing mechanic (hold Z to walk through props)
- Collision layer switching for phasing
- Destruction effects with debris

**Zombie Priority:** #2 Target (if blocking path to sigil)

### 3. Barricade System
**File:** `scripts/systems/barricade_system.gd`

- JetBoom-style nailing mechanic
- Built by player hammering (6 nails @ 0.5s each)
- Can be repaired when damaged
- Costs 50 points to build
- Audio feedback with each nail

**Zombie Priority:** #3 Target (player-built obstacles)

### 4. Zombie AI Targeting
**File:** `scripts/zombies/zombie_controller.gd`

**Priority System:**
1. **Sigil** - Always primary target
2. **Props** - If within 5 units and blocking path
3. **Barricades** - If within 5 units and blocking path
4. **Players** - Only if within 10 units

This creates authentic JetBoom gameplay where zombies ignore players unless they get too close, focusing on destroying the sigil.

## Movement & Controls

### First-Person Controller
**File:** `scripts/player/fps_controller.gd`

- WASD movement with sprint (Shift)
- Mouse look with sensitivity control
- Jump (Space)
- Weapon switching (1-5 keys)
- Z-key phasing through props
- Raycast shooting with headshot detection

### Viewmodel System
**File:** `scripts/player/viewmodel_controller.gd`

- Visible arms (dual armatures from Free_Character)
- Procedural weapon sway (spring physics)
- Head bob (sine wave)
- Recoil animation
- Weapon switching animations
- 5 weapon slots

### Foot IK System
**File:** `scripts/player/foot_ik_controller.gd`

- Visible feet in first-person
- Procedural stepping animation
- Ground detection with raycasts
- Smooth foot placement
- Walking cycle based on velocity

## Audio Systems

### Audio Manager
**File:** `scripts/systems/audio_manager.gd`

- 20x 2D audio players (UI, music)
- 30x 3D audio players (world sounds)
- Object pooling for performance
- Music system with crossfading
- Network-replicated 3D sounds
- Sound library system

### Gore System
**File:** `scripts/systems/gore_system.gd`

- Blood particle bursts
- Blood decals (max 100, fade over 30s)
- Physics-based gibs (max 50, fade over 10s)
- Dismemberment effects
- Network replicated
- Surface-type specific effects

### VFX Manager
**File:** `scripts/systems/vfx_manager.gd`

- Muzzle flashes (weapon-type specific)
- Impact effects (surface-type specific)
- Explosions with particle systems
- Shell casings with physics
- 50-particle effect pool
- Network replicated

## Wave & Spawning

### Arena Manager
**File:** `scripts/levels/arena_manager.gd`

- Progressive wave difficulty
- Zombie count: 10 + (wave * 5)
- Wave completion bonuses
- Intermission system (30s between waves)
- Automatic health scaling for sigil/props
- Item spawning system

### Zombie Types
- **Shambler** - Base zombie (all waves)
- **Runner** - Fast zombie (wave 4+)
- **Tank** - Heavy zombie (wave 7+)
- **Monster** - Boss zombie (wave 10+)

## Multiplayer Systems

### Network Manager
**File:** `scripts/systems/network_manager.gd`

- ENet multiplayer peer
- Steam P2P integration
- Player connection/disconnection handling
- LAN server support
- Server-authoritative design

### Steam Integration
**File:** `scripts/systems/steam_manager.gd`

- Lobby creation (private/friends/public)
- Lobby search & join
- Friend invites
- Lobby metadata
- Join-in-progress support

### Matchmaking Manager
**File:** `scripts/systems/matchmaking_manager.gd`

- Quick match (find or create)
- Join-in-progress gameplay
- Player spawning near sigil
- Match state management
- Steam lobby integration

**Spawn System:**
- Players spawn in circle around sigil (3 unit radius)
- 4 spawn positions around sigil
- Supports join-in-progress at any time

## Weapon System

### 8 Weapon Scenes
1. M16 Rifle
2. Revolver
3. Sniper Rifle (SVD)
4. Machine Gun
5. RPG-7 (with backblast effect)
6. Pistol
7. Shotgun
8. AK-47

### 20 Weapon Resources
Complete stat system with damage, fire rate, reload, ammo, etc.

## Item Pickups

### Pickup Types
**File:** `scripts/items/pickup_item.gd`

- **Ammo Pickup** - Restores 30 ammo
- **Health Pickup** - Restores 25 health
- **Weapon Pickup** - New weapon

All pickups:
- Network replicated
- 30-second respawn timer
- Automatic collection
- Visual feedback

## PSX Graphics

### PSX Shader
**File:** `shaders/psx_shader.gdshader`

- Vertex snapping
- Affine texture mapping
- Color banding/dithering
- Low-resolution rendering (0.5x scale)
- No MSAA for authentic look

## UI Systems

### HUD
- Health & armor display
- Ammo counter
- Points display
- Wave information
- Crosshair

### Chat System
- Text chat
- System messages
- Wave notifications
- Network replicated

### Voice Chat
- Proximity-based voice
- Push-to-talk
- Voice options UI

## Scene Structure

```
scenes/
├── levels/
│   └── arena_01.tscn          # Main playable arena with NavMesh
├── player/
│   ├── player_fps.tscn        # Complete FPS player
│   └── viewmodel.tscn         # First-person viewmodel
├── zombies/
│   ├── zombie_shambler.tscn
│   ├── zombie_runner.tscn
│   ├── zombie_tank.tscn
│   └── zombie_monster.tscn
├── weapons/
│   ├── weapon_m16.tscn
│   ├── weapon_revolver.tscn
│   ├── weapon_sniper.tscn
│   └── ... (5 more)
├── items/
│   ├── ammo_pickup.tscn
│   ├── health_pickup.tscn
│   └── weapon_pickup.tscn
├── systems/
│   └── sigil.tscn             # Primary objective
└── props/
    ├── prop_crate.tscn
    └── prop_barrel.tscn
```

## Autoload Systems (13 Total)

1. **SteamManager** - Steam integration
2. **NetworkManager** - Multiplayer
3. **ChatSystem** - Text chat
4. **VoiceChatSystem** - Voice comms
5. **DamageCalculator** - Combat math
6. **PointsManager** - Economy
7. **WaveManager** - Wave progression
8. **AsyncPathfinding** - Navigation
9. **AsyncLoader** - Resource loading
10. **ResourceCache** - Resource caching
11. **AudioManager** - Sound system
12. **GoreSystem** - Blood & gibs
13. **VFXManager** - Visual effects
14. **GameManager** - Game state
15. **MatchmakingManager** - Lobby system

## Controls

- **WASD** - Move
- **Shift** - Sprint
- **Space** - Jump
- **Mouse** - Look
- **Left Click** - Shoot
- **R** - Reload
- **1-5** - Switch weapons
- **Z (hold)** - Phase through props
- **Esc** - Menu

## Testing the Game

1. Load `scenes/levels/arena_01.tscn`
2. Press F5 to run
3. Use WASD to move, mouse to look
4. Hold Z to walk through props
5. Shoot zombies as they attack the sigil
6. Build barricades to slow zombies
7. Survive progressive waves

## Network Multiplayer

1. Host creates lobby via Steam or LAN
2. Players search and join via matchmaking
3. Join-in-progress supported
4. All systems network replicated
5. Server-authoritative gameplay

## JetBoom Authenticity Checklist

- ✅ Sigil as primary objective
- ✅ Props with health bars
- ✅ Z-key phasing through props
- ✅ Barricade nailing mechanic
- ✅ Zombie targeting priority (sigil > props > barricades > players)
- ✅ Wave-based spawning
- ✅ Points economy
- ✅ Join-in-progress multiplayer
- ✅ Spawn near sigil
- ✅ Progressive difficulty

All core JetBoom mechanics have been faithfully recreated!
