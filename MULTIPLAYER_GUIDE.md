# Multiplayer & Steam Integration Guide

Complete guide for the multiplayer zombie survival game with Steam integration.

## 🎮 Overview

This game features full multiplayer support with Steam integration, including:
- **Steam P2P Networking**: Direct peer-to-peer connections via Steam
- **Lobby System**: Create, join, and manage multiplayer lobbies
- **Friend Invites**: Invite Steam friends to your lobby
- **Matchmaking**: Automatic matchmaking with skill-based lobby selection
- **Dedicated Server Support**: Can run as dedicated server
- **Network Replication**: All game state synced across clients

## 🔧 Setup Requirements

### GodotSteam Installation

1. **Download GodotSteam**:
   - Visit: https://github.com/GodotSteam/GodotSteam
   - Download the appropriate build for Godot 4.3+

2. **Steam App ID**:
   - Register your game on Steam partner portal
   - Update `steam_app_id` in `scripts/systems/steam_manager.gd`
   - Create `steam_appid.txt` in game root with your App ID

3. **Steam SDK**:
   - GodotSteam comes bundled with Steam SDK
   - Ensure `steam_api64.dll` (Windows) or equivalent is in game directory

## 🌐 Network Architecture

### Peer-to-Peer Model
```
Host (Server + Client)
├── Client 1
├── Client 2
└── Client 3
```

- **Host** acts as authoritative server
- All game logic runs on host
- Clients send inputs, receive state updates
- Steam handles NAT traversal and relay

### Network Roles

**Server/Host**:
- Spawns zombies
- Manages wave progression
- Handles combat calculations
- Validates all actions
- Syncs state to clients

**Client**:
- Sends player inputs
- Receives world state
- Renders game locally
- Predicts movement (client-side prediction)

## 🎯 Core Systems

### 1. Steam Manager (`steam_manager.gd`)

**Global Singleton** - Manages all Steam API interactions

**Key Features**:
- Steam initialization and authentication
- Lobby creation and joining
- Friend list management
- Steam invites
- Lobby data synchronization

**Example Usage**:
```gdscript
# Create a friends-only lobby
SteamManager.create_lobby(1)  # 0=Private, 1=Friends, 2=Public

# Join a lobby
SteamManager.join_lobby(lobby_id)

# Invite friend
SteamManager.invite_friend_to_lobby(friend_steam_id)

# Set lobby metadata
SteamManager.set_lobby_data("wave", "5")
```

### 2. Network Manager (`network_manager.gd`)

**Global Singleton** - Handles multiplayer networking

**Key Features**:
- Server/client creation
- Player synchronization
- RPC calls for game events
- Zombie spawning across network
- Damage replication

**Example Usage**:
```gdscript
# Start hosting
NetworkManager.create_server_steam(lobby_id)

# Connect to host
NetworkManager.join_server_steam(lobby_id)

# Spawn networked zombie
NetworkManager.rpc("spawn_zombie_networked", zombie_class, position, id)
```

### 3. Matchmaking System (`matchmaking_system.gd`)

**Global Singleton** - Automatic matchmaking

**Key Features**:
- Lobby searching with filters
- Skill-based matching
- Auto-create lobby if none found
- Region preferences
- Wave range preferences

**Example Usage**:
```gdscript
# Start matchmaking
MatchmakingSystem.start_matchmaking()

# Set preferences
MatchmakingSystem.preferred_wave_range = Vector2i(1, 10)
MatchmakingSystem.preferred_region = MatchmakingRegion.US_EAST
```

## 🏠 Lobby System

### Lobby Flow

1. **Main Menu** → Player chooses:
   - Create Lobby
   - Find Match
   - Browse Lobbies
   - Join Friend

2. **Lobby Screen**:
   - Shows all players
   - Ready check system
   - Host can start game
   - Chat functionality
   - Friend invite system

3. **Game Start** (requires 2+ players):
   - All players ready
   - Host clicks "Start Game"
   - Loads into game world

### Lobby Types

**Private (0)**:
- Invite-only
- Not visible in browser
- Perfect for testing

**Friends Only (1)**:
- Visible to friends
- Friends can join directly
- Recommended for casual play

**Public (2)**:
- Visible in matchmaking
- Anyone can join
- Used for public matchmaking

### Lobby Data Structure

```gdscript
{
	"game_mode": "survival",
	"version": "1.0.0",
	"map": "default",
	"wave": "1",
	"max_players": "4",
	"difficulty": "normal",
	"started": "false"
}
```

## 🔍 Matchmaking

### How It Works

1. **Player clicks "Find Match"**
2. **System searches for lobbies**:
   - Must have open slots
   - Same game version
   - Similar wave range
   - Not already started

3. **Lobby Scoring**:
   ```
   Score = PlayerCount * 20 +
           NearFullBonus(50) +
           WaveSimilarity(-2 * diff) +
           CanStartBonus(30)
   ```

4. **Best lobby selected** or **new lobby created**

5. **Minimum 2 players to start**

### Matchmaking Preferences

```gdscript
# Set wave range (will join lobbies in this range)
preferred_wave_range = Vector2i(1, 15)

# Set region
preferred_region = MatchmakingRegion.US_EAST

# Maximum search time
MAX_SEARCH_TIME = 60.0  # 60 seconds
```

## 🎮 In-Game Multiplayer

### Player Synchronization

Each player has:
- **Unique Peer ID**: Assigned by multiplayer system
- **Steam ID**: From Steam authentication
- **Authority**: Controlled by owning client

**Position Sync**:
- Clients send inputs to server
- Server validates and broadcasts positions
- Smooth interpolation for network jitter

**Combat Sync**:
- Clients send shoot commands
- Server performs raycasts
- Broadcasts damage to all clients
- Shows damage numbers locally

### Zombie Synchronization

**Server Authority**:
- Only server spawns zombies
- Only server processes AI
- Clients receive position updates

**Networked Events**:
```gdscript
@rpc("authority", "call_local")
func spawn_zombie_networked(class_name, position, id)

@rpc("any_peer", "call_local")
func damage_zombie(zombie_path, damage, is_headshot)
```

### Wave Synchronization

**Server Manages**:
- Wave progression
- Zombie spawn timing
- Intermission timers
- Boss spawns

**Clients Receive**:
```gdscript
@rpc("authority", "reliable")
func sync_wave_state(wave, zombies_alive, is_intermission)
```

## 💰 Points System (Networked)

### Point Distribution

**Server Authority**:
- Server calculates points for kills
- Broadcasts to all players
- Each player tracks their own points

**Shared Pool Option**:
- Team shares points
- Any player can spend
- Encourages cooperation

**Individual Points**:
- Each player has separate pool
- Rewards individual performance
- More competitive

### Synchronized Purchases

```gdscript
@rpc("any_peer", "call_remote")
func purchase_item(item_name, cost):
	if not is_server:
		return

	# Validate on server
	if can_afford(cost):
		spend_points(cost)
		# Give item to client
		rpc_id(sender_id, "receive_item", item_name)
```

## 🛠️ Barricade Nailing (Networked)

### Synchronized Nailing

**Client Initiates**:
```gdscript
# Client starts nailing
start_nailing(barricade, player)
```

**Server Validates**:
```gdscript
@rpc("any_peer")
func request_nail_barricade(barricade_path):
	if can_nail(barricade_path):
		rpc("nail_placed_confirmed", barricade_path)
```

**All Clients See Progress**:
- Visual nail indicators
- Repair progress bar
- Completion effects

## 📡 Network Optimization

### Bandwidth Optimization

**Update Rates**:
- Player position: 20 Hz
- Zombie position: 10 Hz
- Wave state: On change
- Chat: On send

**Compression**:
- Use unreliable for position (UDP-like)
- Use reliable for critical events
- Batch updates when possible

### Lag Compensation

**Client-Side Prediction**:
- Predict own movement locally
- Server corrects if needed
- Smooth interpolation

**Hit Registration**:
- Server-authoritative
- Raycasts on server
- Clients show visual feedback

## 🔐 Security

### Validation

**Server Always Validates**:
- All damage calculations
- Item purchases
- Barricade placements
- Wave progression

**Anti-Cheat Measures**:
- Server authority for all game state
- Input validation
- Speed hack detection (movement bounds)
- Inventory verification

## 🚀 Deployment

### Building for Steam

1. **Export Settings**:
   ```
   Export → Windows Desktop
   Include GodotSteam DLLs
   ```

2. **Required Files**:
   ```
   game.exe
   steam_api64.dll
   steam_appid.txt
   ```

3. **Upload to Steam**:
   ```
   steamcmd +login username +app_build appid +quit
   ```

### Dedicated Server

**Run as Dedicated**:
```bash
./game.exe --headless --server
```

**Server Configuration**:
```gdscript
func _ready():
	if OS.has_feature("server"):
		NetworkManager.create_server_lan()
		# Don't load graphics
		# Start wave system
```

## 📊 Debug Commands

### Testing Multiplayer Locally

**Start 2 Instances**:
```bash
# Instance 1 (Host)
./game.exe --host

# Instance 2 (Client)
./game.exe --client
```

**Debug Panel**:
- F1: Show network stats
- F2: Show player list
- F3: Force next wave
- F4: Spawn debug zombie

## 🐛 Troubleshooting

### Common Issues

**Steam Not Initialized**:
- Check GodotSteam installation
- Verify steam_appid.txt
- Ensure Steam client is running

**Can't Join Lobby**:
- Check firewall settings
- Verify same game version
- Ensure lobby not full

**Desync Issues**:
- Server authority enabled?
- Check network interpolation
- Validate RPC calls

**High Latency**:
- Use Steam relay servers
- Check player regions
- Enable compression

## 📝 Best Practices

### Code Patterns

**Always Use RPCs for State Changes**:
```gdscript
# DON'T: Change state directly
zombie.health -= damage

# DO: Call RPC
rpc("damage_zombie", zombie.get_path(), damage)
```

**Validate on Server**:
```gdscript
@rpc("any_peer")
func buy_item(item_name):
	if not is_server:
		return  # Ignore on clients

	# Validate
	if can_afford(item_cost):
		# Process
		pass
```

**Use Proper RPC Modes**:
- `"reliable"`: Critical events (death, spawns)
- `"unreliable"`: Frequent updates (position)
- `"authority"`: Server → Clients only
- `"any_peer"`: Any player can call

## 🎯 Performance Targets

- **Tick Rate**: 20 Hz
- **Max Players**: 4
- **Max Zombies**: 50
- **Network Bandwidth**: < 100 KB/s per client
- **Latency Tolerance**: Up to 200ms

## 📚 Additional Resources

- **GodotSteam Docs**: https://godotsteam.com
- **Godot Multiplayer**: https://docs.godotengine.org/en/stable/tutorials/networking/
- **Steam Partner**: https://partner.steamgames.com

---

**Ready for Multiplayer Zombie Survival!** 🧟‍♂️🔫👥
