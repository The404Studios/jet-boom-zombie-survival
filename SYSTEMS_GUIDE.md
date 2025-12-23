# Systems Integration Guide

This document explains how all the game systems work together and how to use them.

## Core Systems (Autoloads)

All core systems are autoloaded and accessible globally via `/root/SystemName`.

### 1. SteamManager
Handles Steam integration and authentication.
- Location: `scripts/systems/steam_manager.gd`
- Access: `get_node("/root/SteamManager")`

### 2. NetworkManager
Manages multiplayer connections and player synchronization.
- Location: `scripts/systems/network_manager.gd`
- Access: `NetworkManager`
- Signals: `player_connected(peer_id, player_data)`, `player_disconnected(peer_id)`

### 3. MatchmakingSystem
Handles finding and joining multiplayer lobbies.
- Location: `scripts/systems/matchmaking_system.gd`
- Access: `get_node("/root/MatchmakingSystem")`

### 4. ChatSystem
Text chat with spam prevention and team/global modes.
- Location: `scripts/systems/chat_system.gd`
- Access: `get_node("/root/ChatSystem")`
- Usage: `ChatSystem.send_message("Hello!", false)`
- Signals: `message_received(sender, message, is_team)`, `system_message(message)`

### 5. VoiceChatSystem
Proximity voice chat using Steam Voice API.
- Location: `scripts/systems/voice_chat_system.gd`
- Access: `get_node("/root/VoiceChatSystem")`
- Features: Push-to-talk (V key), proximity mode, 3D audio
- Settings: Configurable via VoiceOptionsUI

### 6. ThreadPool
Manages worker threads for async operations.
- Location: `scripts/systems/thread_pool.gd`
- Access: `get_node("/root/ThreadPool")`
- Usage: `ThreadPool.submit_task(callable, callback, priority)`
- Threads: 4 worker threads by default

### 7. AsyncPathfinding
Non-blocking pathfinding for AI.
- Location: `scripts/systems/async_pathfinding.gd`
- Access: `get_node("/root/AsyncPathfinding")`
- Usage: `AsyncPathfinding.request_path(start, end, callback)`

### 8. AsyncLoader
Async resource loading without freezing.
- Location: `scripts/systems/async_loader.gd`
- Access: `get_node("/root/AsyncLoader")`
- Usage: `AsyncLoader.load_resource_async(path, callback)`

### 9. ResourceCache
Smart resource caching with LRU eviction.
- Location: `scripts/systems/resource_cache.gd`
- Access: `get_node("/root/ResourceCache")`
- Usage: `ResourceCache.get_cached_resource(path)`
- Cache Size: 256MB default

## Input Mappings

- **Movement**: WASD
- **Sprint**: Shift
- **Jump**: Space
- **Shoot**: Left Mouse Button
- **Reload**: R
- **Interact**: E
- **Inventory**: I
- **Extract**: X
- **Chat**: T (text chat)
- **Voice**: V (push-to-talk)

## Zombie System

### Zombie Class Data
All zombies are defined using `ZombieClassData` resources.

Location: `resources/zombies/*.tres`

Available Types:
- Basic: Shambler, Runner, Tank
- Special: Poison, Exploder, Spitter, Screamer, Berserker, Boomer
- Bosses: Behemoth, Nightmare, Abomination

### Spawning Zombies

```gdscript
# Via GameManager
var zombie = GameManager.spawn_zombie("shambler", position)

# Manual spawning
var zombie_data = ResourceCache.get_cached_resource("res://resources/zombies/runner.tres")
var zombie_scene = preload("res://scenes/zombies/zombie.tscn")
var zombie = zombie_scene.instantiate()
zombie.setup_from_class(zombie_data, current_wave)
zombie.global_position = spawn_position
get_tree().current_scene.add_child(zombie)
```

### Zombie Abilities

Zombies can have multiple special abilities:
- **Poison**: Applies DoT on hit
- **Explosion**: Explodes on death
- **Ranged Attack**: Shoots projectiles
- **Buff Aura**: Buffs nearby zombies
- **Rage Mode**: Gets stronger at low health
- **Gas Cloud**: Creates damaging gas on death
- **Teleport**: Short-range teleportation
- **Summoning**: Spawns additional zombies
- **Regeneration**: Heals over time
- **AOE Attack**: Area damage ability

## Weapon System

### Weapon Resources
Weapons use `ItemDataExtended` for stats and properties.

Location: `resources/weapons/*.tres`

Categories:
- Pistols (Common-Legendary)
- SMGs (Uncommon-Legendary)
- Rifles (Rare-Epic)
- Shotguns (Rare-Epic)
- Heavy Weapons (Epic-Legendary)
- Melee (Common-Epic)
- Special (Epic-Mythic)

### Weapon Properties
- Base Damage
- Fire Rate
- Magazine Size
- Reload Time
- Range
- Stat Bonuses (STR, DEX, INT, AGI, VIT)
- Crit Chance/Damage
- Armor Penetration
- Status Effects (Bleed, Poison)
- Socket Slots for augments

## Multiplayer Integration

### Starting a Server
```gdscript
# Via Steam
NetworkManager.create_server_steam(lobby_id)

# Direct
NetworkManager.create_server()
```

### Joining a Game
```gdscript
# Find and join via matchmaking
MatchmakingSystem.start_matchmaking()

# Join specific lobby
NetworkManager.join_server_steam(lobby_id)
```

### Network Replication
The NetworkManager handles:
- Player synchronization
- Zombie spawning and damage
- Item pickups
- Wave progression
- Points and kills

Use `@rpc` annotations for custom network functions:
```gdscript
@rpc("any_peer", "call_remote")
func my_network_function(data):
    # Handle network call
    pass
```

## Chat and Voice

### Text Chat
```gdscript
# Send message
ChatSystem.send_message("Hello world!", false)  # Global
ChatSystem.send_message("Team message", true)   # Team

# System messages
ChatSystem.emit_system_message("Wave completed!")
```

### Voice Chat
Voice chat is automatic based on settings:
- **Push-to-Talk**: Hold V to talk
- **Voice Activity**: Talks when sound detected
- **Proximity**: Only nearby players hear you (5-50m)
- **Global**: Everyone hears you

Configure via Voice Options UI (pause menu).

## Threading Best Practices

### Submitting Tasks
```gdscript
# High priority task
var task_id = ThreadPool.submit_task(
    func(): return expensive_calculation(),
    func(result): handle_result(result),
    priority = 10
)

# Cancel if needed
ThreadPool.cancel_task(task_id)
```

### Async Pathfinding
```gdscript
AsyncPathfinding.request_path(
    zombie.global_position,
    target.global_position,
    func(path): zombie.set_path(path)
)
```

### Async Loading
```gdscript
AsyncLoader.load_resource_async(
    "res://scenes/weapons/big_weapon.tscn",
    func(resource): equip_weapon(resource)
)
```

## Resource Caching

### Preloading
```gdscript
# Preload single resource
ResourceCache.preload_resource("res://resources/zombies/tank.tres")

# Preload batch
ResourceCache.preload_resources([
    "res://resources/weapons/ak47.tres",
    "res://resources/weapons/shotgun.tres"
])
```

### Priority Resources
Resources marked as priority won't be evicted from cache:
```gdscript
ResourceCache.add_priority_resource("res://resources/weapons/pistol.tres")
```

### Cache Stats
```gdscript
var stats = ResourceCache.get_cache_stats()
print("Cache usage: %.1f MB / %d MB" % [stats.size_mb, stats.max_size_mb])
print("Entries: %d" % stats.entry_count)
```

## UI System

### HUD
The HUD automatically updates when a player exists in the scene.
- Health/Stamina bars
- Wave information
- Points display
- Ammo counter
- Interact prompts

### Chat UI
- Press T to open chat
- Type message and press Enter
- Toggle Team checkbox for team chat

### Voice Options
Access via pause menu to configure:
- Enable/disable voice chat
- Push-to-talk vs voice activity
- Proximity vs global voice
- Volume levels (master, voice, mic)
- Test microphone

## Performance Tips

1. **Use Caching**: Cache frequently-used resources
2. **Use Threading**: Offload expensive operations to threads
3. **Async Pathfinding**: Use for all AI pathfinding
4. **Batch Operations**: Group network calls when possible
5. **Resource Limits**: Keep cache size reasonable (256MB default)

## Common Patterns

### Zombie Spawning in Waves
```gdscript
# Wave manager handles this automatically
wave_manager.start_wave()
```

### Player Damage Calculation
```gdscript
var damage_instance = DamageCalculator.calculate_damage(
    weapon.damage,
    player.character_stats,
    weapon,
    is_headshot,
    target_armor
)
```

### Awarding Points
```gdscript
GameManager.award_points(100)
```

### System Notifications
```gdscript
GameManager.show_notification("Wave 5 Complete!")
```

## Troubleshooting

### Chat not working
- Check NetworkManager is initialized
- Verify ChatSystem autoload is enabled
- Check multiplayer connection

### Voice chat silent
- Verify Steam is initialized
- Check microphone permissions
- Test microphone in Voice Options
- Verify voice volume settings

### Zombies not spawning
- Check zombie resource files exist
- Verify WaveManager is in scene
- Check NavigationRegion3D is set up

### Performance issues
- Check ThreadPool task queue: `ThreadPool.get_queued_task_count()`
- Monitor cache usage: `ResourceCache.get_cache_stats()`
- Profile with Godot's built-in profiler

## Next Steps

1. Create 3D models for zombies and weapons
2. Add animations to all characters
3. Create map with navigation mesh
4. Set up spawn points
5. Create main menu flow
6. Add sound effects and music
7. Implement save/load system
8. Add more zombie types and weapons
