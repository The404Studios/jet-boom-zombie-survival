# 🎮 Quick Start Guide - JetBoom Zombie Survival

## 🚀 Run the Game (Out-of-Box)

### **Option 1: Godot Editor** (Recommended)
```bash
1. Open project in Godot 4.5.1
2. Press F5 (or click Play button)
3. Start playing immediately!
```

The game will automatically:
- Load arena_01.tscn
- Spawn player near sigil
- Start wave 1 after 1 second
- Work in singleplayer mode (no Steam required)

### **Option 2: Export Build**
```bash
1. Project → Export
2. Choose platform (Windows/Linux/Mac)
3. Export and run executable
```

## 🎮 Controls

| Key | Action |
|-----|--------|
| **WASD** | Move |
| **Mouse** | Look around |
| **Left Click** | Shoot |
| **Space** | Jump |
| **Shift** | Sprint |
| **R** | Reload |
| **1-5** | Switch weapons (Pistol/M16/Shotgun/Sniper/RPG) |
| **Z (hold)** | Phase through rocks |
| **Esc** | Pause/Menu |

## 🎯 Objective

**Protect the Sigil!** (Glowing blue cylinder at center)

1. Zombies will spawn and attack the **Sigil**
2. Kill zombies to earn points
3. Survive progressive waves
4. Use rocks for cover (hold Z to phase through)
5. Collect chicken for health
6. Collect ammo boxes when low

## 🧟 Zombie Types

| Type | Speed | Health | Special |
|------|-------|--------|---------|
| **Shambler** | Slow | Low | Basic zombie |
| **Runner** | Fast | Medium | Unlocks wave 4+ |
| **Tank** | Slow | High | Heavy armor, wave 7+ |
| **Monster** | Medium | Very High | Acid spit, wave 10+ |

## 💡 Tips

1. **Headshots = 2x Damage** - Aim for the head!
2. **Hold Z near rocks** - Walk through props when needed
3. **Watch the Sigil health** - It's in the glowing label above
4. **Collect drops** - Zombies drop ammo/health/items
5. **Use cover** - Rocks block zombie paths
6. **Don't run out of ammo** - Pick up ammo boxes regularly

## 🌊 Wave Progression

- **Wave 1**: 15 shamblers
- **Wave 2**: 20 zombies (mostly shamblers)
- **Wave 3**: 25 zombies (mix)
- **Wave 4+**: Runners unlock
- **Wave 7+**: Tanks unlock
- **Wave 10+**: Monster bosses unlock

Each wave:
- More zombies spawn
- Zombies get stronger (health/damage)
- Sigil gains more health
- Rocks gain more health

## 🎨 What You'll See

**Environment:**
- 50x50 arena with walls
- Glowing sigil at center (primary objective)
- 8 destructible rocks (4 large, 4 small)
- 4 dead trees and plants for atmosphere
- PSX-style graphics with vertex snapping

**Effects:**
- Blood splatter and gibs when killing zombies
- Muzzle flashes and shell casings
- Health bars on damaged props
- 3D positional audio
- Camera shake on shooting

## 🔧 Singleplayer Mode

The game runs in **singleplayer mode by default**:
- No network connection required
- Steam API optional (gracefully disabled if not available)
- Starts immediately when you hit F5
- All systems work offline

## 🌐 Multiplayer (Optional)

To enable multiplayer:
```gdscript
# In-game console or attached script:
get_node("/root/MatchmakingManager").create_match()

# Or for joining:
get_node("/root/MatchmakingManager").quick_match()
```

**Requirements for multiplayer:**
- GodotSteam addon installed
- Steam running
- Proper Steam App ID configured

**Multiplayer features:**
- Join-in-progress support
- Server-authoritative gameplay
- All systems network replicated
- Spawn near sigil when joining

## 📂 Project Structure

```
jet-boom-zombie-survival/
├── scenes/
│   ├── levels/arena_01.tscn ← MAIN SCENE (loads automatically)
│   ├── player/player_fps.tscn
│   ├── zombies/ (shambler, runner, tank, monster)
│   ├── weapons/ (8 weapons)
│   ├── items/ (ammo, health, weapon pickups)
│   └── props/ (rocks with health bars)
├── scripts/
│   ├── systems/ (15 autoload managers)
│   ├── player/ (FPS controller, viewmodel, foot IK)
│   ├── zombies/ (AI, controller)
│   └── items/ (pickup system)
├── resources/
│   ├── weapons/ (20 weapon configs)
│   └── zombies/ (4 zombie types)
└── Assets/ (All from real asset packs)
    ├── Characters_psx/ ← Zombie models
    ├── LP_WeaponsPack/ ← All weapons
    ├── KloWorks_Food_Kit/ ← Health pickups
    └── PSX+ Forest Pack/ ← Props & environment
```

## ✅ Verification Checklist

**Press F5 and verify:**
- [ ] Player spawns near center
- [ ] Blue glowing sigil visible
- [ ] Zombies start spawning after ~1 second
- [ ] Crosshair visible in center
- [ ] HUD shows health/ammo/wave info
- [ ] Can move with WASD
- [ ] Can shoot with left click
- [ ] Zombies attack the sigil
- [ ] Rocks show health when shot
- [ ] Can phase through rocks with Z

If all ✅ then game is working perfectly!

## 🐛 Troubleshooting

**Issue: Game doesn't start**
- Check Godot version is 4.5.1+
- Verify main scene is arena_01.tscn
- Check console for errors

**Issue: No zombies spawn**
- Check arena has spawn points
- Verify zombie scenes exist in scenes/zombies/

**Issue: Can't move/shoot**
- Check input map in Project Settings
- Verify player has CharacterBody3D

**Issue: Models missing**
- Ensure all asset folders are in project root
- Check .import folder exists

**Issue: Steam errors**
- Ignore Steam errors in singleplayer
- GodotSteam is optional for singleplayer

## 🎮 Ready to Play!

Just press **F5** and start defending the Sigil!

The game is **fully functional out-of-the-box** with:
- ✅ Singleplayer mode (no setup needed)
- ✅ All real assets loaded
- ✅ Complete wave system
- ✅ Full zombie AI
- ✅ Weapon switching
- ✅ Gore & VFX
- ✅ Pickup system
- ✅ JetBoom mechanics

**Have fun surviving!** 🧟‍♂️🔫
