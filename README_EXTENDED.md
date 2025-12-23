# Zombie Survival Shooter - Extended Edition

A retro PSX-style zombie survival shooter with deep RPG mechanics made in Godot 4.3+

## 🎮 Core Features

### PSX Retro Aesthetics
- **Authentic PlayStation 1 Graphics**: Vertex snapping, affine texture mapping, vertex jitter
- **Post-Processing Effects**: Color depth reduction (16 colors), dithering, optional scanlines
- **Optimized Performance**: Locked at 144 FPS with no V-Sync
- **Low-poly Style**: True to PS1 era visuals

### Combat System
- **Advanced Damage Types**:
  - Physical Damage (affected by armor)
  - True Damage (ignores armor)
  - Bleed Damage (damage over time)
  - Poison Damage (stacking DoT)
  - Fire/Elemental Damage
  - Additional Flat Damage

- **Headshot System**: Precision shooting with headshot detection and bonus damage
- **Critical Hits**: Chance-based crits with damage multipliers
- **Status Effects**: Bleed, poison, and other DoT effects that stack

### Character Progression

#### Stat System
- **Strength**: Increases melee damage and carry weight
- **Dexterity**: Improves accuracy, crit chance, and reload speed
- **Intelligence**: Reduces skill cooldowns and increases item find
- **Agility**: Boosts movement speed and dodge chance
- **Vitality**: Increases health, stamina, and regeneration rates

#### Leveling
- Gain experience by killing zombies
- Level up to earn stat points
- Allocate points to customize your build
- Unlock new perks and abilities

### Equipment System

#### Gear Slots
- **Helmet**: Head protection and stat bonuses
- **Chest Armor**: Main armor piece with high defense
- **Gloves**: Dexterity and precision bonuses
- **Boots**: Movement and agility bonuses
- **Ring 1 & 2**: Powerful accessory bonuses
- **Amulet**: Unique effects and bonuses
- **Primary Weapon**: Main weapon slot
- **Secondary Weapon**: Backup weapon slot

#### Item Rarity System
- **Common** (Gray): Basic items
- **Uncommon** (Green): Enhanced items
- **Rare** (Blue): Strong items with good bonuses
- **Epic** (Purple): Powerful items with multiple bonuses
- **Legendary** (Orange): Extremely rare with unique effects
- **Mythic** (Red): Ultimate tier items

#### Augment/Socket System
- Items can have sockets for augments
- Socket gems to add bonuses:
  - Damage Gems (+ flat damage)
  - Critical Gems (+ crit chance)
  - Blood Gems (+ bleed damage)
  - Poison Gems (+ poison damage)
  - Stat Gems (+ specific stats)

### Inventory & Storage

#### Inventory
- 20 slot backpack for carried items
- Weight system based on Strength
- Quick item access and management
- Drag and drop functionality

#### Stash
- 64 slot permanent storage
- Items persist between runs
- Organized by rarity and type
- Transfer items between inventory and stash

#### Marketplace
- Buy weapons, armor, and consumables
- Multiple currency types:
  - 💰 Coins (basic currency)
  - 🎫 Tokens (premium currency)
  - 🔧 Scrap (crafting materials)
- Shop refresh system
- Rarity-based pricing
- Limited stock items

### Persistence System
- **Auto-Save**: Progress saves automatically
- **Character Data**: Stats, level, and experience persist
- **Equipment**: All equipped gear is saved
- **Stash**: Your storage is permanent
- **Statistics Tracking**:
  - Zombies killed
  - Waves survived
  - Items looted
  - Successful extractions
  - Deaths

## 🎯 Controls

### Movement
- **W/A/S/D** - Move (speed affected by Agility)
- **Shift** - Sprint (drains stamina)
- **Space** - Jump
- **Mouse** - Look around

### Combat
- **Left Click** - Shoot
- **R** - Reload (speed affected by Dexterity)
- **1-9** - Quick weapon swap

### Interaction
- **E** - Interact (pickup, shop, barricades)
- **I** - Toggle Inventory
- **C** - Open Character Sheet
- **V** - Open Stash (at safe zone)
- **B** - Open Marketplace (at Sigil)
- **X** - Extract (save and return)
- **ESC** - Pause/Options

## 📊 Gameplay Systems

### Wave Survival
Defend the Sigil against endless zombie waves:
- Waves scale in difficulty
- More zombies per wave
- Tougher zombie variants
- Better loot at higher waves

### Extraction System
Safe extraction mechanics:
1. Fight through waves
2. Collect loot
3. Return to Sigil
4. Press X to extract
5. All items transfer to stash
6. Gain experience and currency

### Loot System
Dynamic loot with quality tiers:
- Rarity affects drop chance
- Better loot from tougher zombies
- Boss zombies drop guaranteed loot
- Augments can modify drop rates (Intelligence stat)

### Barricade Defense
Strategic fortification:
- Place barricades at marked spots
- Barricades block zombie paths
- Repair damaged barricades
- Upgrade barricades with materials

## 🛡️ Damage Calculations

### Physical Damage
```
Final Damage = Base Damage × Damage Multiplier × (1 - Armor Reduction)
Armor Reduction = Target Armor / (Target Armor + 100)
Maximum Reduction = 75%
```

### Critical Hits
```
Crit Damage = Base Damage × Crit Multiplier
Base Crit Chance = 5%
Crit Chance = Base + (Dexterity × 0.5%)
Crit Multiplier = 1.5 + (Dexterity × 2%)
```

### Headshots
```
Headshot Damage = Base Damage × Headshot Multiplier
Base Headshot Bonus = 1.5x
Additional from gear and stats
```

### Status Effects
- **Bleed**: Deals damage per second for 5 seconds, stacks up to 10 times
- **Poison**: Deals damage per second for 10 seconds, stacks up to 10 times
- **True Damage**: Bypasses all armor and resistances

## 📦 Item Categories

### Weapons
- Pistols (fast, low damage)
- Rifles (balanced)
- Shotguns (high damage, short range)
- Sniper Rifles (extreme damage, headshot bonus)
- SMGs (very fast, poison/bleed builds)

### Armor
- Light Armor (low defense, high mobility)
- Medium Armor (balanced)
- Heavy Armor (high defense, reduced mobility)

### Accessories
- Rings (offensive bonuses)
- Amulets (defensive or utility)

### Consumables
- Health Packs (restore HP)
- Stamina Boosters (restore stamina)
- Buff Potions (temporary stat boosts)

### Materials
- Scrap (crafting and upgrades)
- Gems (socketing augments)
- Repair Kits (fix durability)

## 🏗️ Project Structure

```
├── scenes/
│   ├── main.tscn                    # Main game scene
│   ├── player/                      # Player with all systems
│   ├── zombies/                     # Extended zombie AI
│   ├── weapons/                     # Weapon models
│   ├── items/                       # Loot items
│   ├── environment/                 # Props and structures
│   └── ui/                          # All UI systems
├── scripts/
│   ├── player/                      # Player controller extended
│   ├── zombies/                     # Zombie AI extended
│   ├── systems/
│   │   ├── character_stats.gd       # Stat system
│   │   ├── equipment_system.gd      # Gear management
│   │   ├── damage_calculator.gd     # Damage calculations
│   │   ├── status_effect_system.gd  # DoT effects
│   │   ├── player_persistence.gd    # Save/load
│   │   ├── merchant_system.gd       # Shop logic
│   │   └── inventory_system.gd      # Inventory
│   ├── items/
│   │   └── item_data_extended.gd    # Extended item data
│   ├── ui/
│   │   ├── animated_inventory_ui.gd # Animated inventory
│   │   ├── stash_ui.gd              # Stash interface
│   │   ├── marketplace_ui.gd        # Shop interface
│   │   └── character_sheet_ui.gd    # Character stats
├── resources/
│   ├── weapons/                     # Weapon resources
│   ├── armor/                       # Armor pieces
│   ├── accessories/                 # Rings and amulets
│   ├── augments/                    # Socket gems
│   └── items/                       # Consumables
└── shaders/
    ├── psx_shader.gdshader          # PSX material
    └── psx_post_process.gdshader    # Post effects
```

## 🎨 Customization

### Graphics Settings
- Dither intensity
- Color depth (4-32 colors)
- Vertex snapping amount
- Scanlines (on/off)
- Resolution scaling

### Gameplay Settings
- Mouse sensitivity
- FPS limit (60-240)
- Auto-save frequency
- Difficulty scaling

## 🏆 Achievement System

Track your progress:
- Kill X zombies
- Survive X waves
- Extract with X value of loot
- Reach level X
- Collect all legendary items
- Max out a stat
- Complete a perfect run

## 💡 Pro Tips

1. **Build Synergy**: Match your gear to your stat build
2. **Socket Wisely**: Augments are expensive to remove
3. **Extract Often**: Don't risk losing valuable loot
4. **Upgrade Barricades**: They save your life in late waves
5. **Headshots Matter**: Practice aim for massive damage
6. **Stack DoTs**: Bleed and poison can melt bosses
7. **Balance Stats**: Don't min-max too hard early on
8. **Shop Smart**: Refresh costs increase, choose wisely
9. **Save Tokens**: Premium currency is rare
10. **Experiment**: Try different builds and playstyles

## 🔧 Technical Details

- **Engine**: Godot 4.3+ (compatible with 4.5.1)
- **Target FPS**: 144 (configurable)
- **Rendering**: Forward+ with PSX effects
- **Physics**: 3D with proper collision layers
- **Save Format**: Binary with compression
- **Netcode Ready**: Architecture supports multiplayer

## 📜 License

See LICENSE file for details.

## 🙏 Credits

Built as a complete zombie survival shooter with deep RPG mechanics inspired by JetBoom's Zombie Survival.

Assets:
- PSX Nature Volume 1
- Free Character Pack
- LP Weapons Pack
- KloWorks Food Kit
