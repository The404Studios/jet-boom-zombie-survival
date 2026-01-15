extends Node
class_name DedicatedServer

## Dedicated Server Controller
## This script runs when the game is launched in dedicated server mode
## It creates the authoritative game server that clients connect to

signal server_started(server_id: int)
signal server_stopped
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal game_started
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal game_ended(victory: bool)

# Server configuration
@export var server_name: String = "Zombie Survival Server"
@export var server_port: int = 7777
@export var max_players: int = 8
@export var region: String = "us-east"
@export var map_name: String = "arena_01"
@export var game_mode: String = "survival"
@export var difficulty: String = "Normal"
@export var auto_start_delay: float = 30.0
@export var min_players_to_start: int = 1

# Backend configuration
const BACKEND_URL: String = "http://162.248.94.149:5000"
const SIGNALR_HUB_URL: String = "ws://162.248.94.149:5000/hubs/dedicated"

# Server state
var is_running: bool = false
var server_id: int = -1
var server_token: String = ""
var current_wave: int = 0
var game_status: GameStatus = GameStatus.WAITING

# Player tracking
var connected_players: Dictionary = {}  # peer_id -> PlayerData
var player_entities: Dictionary = {}  # peer_id -> Player node

# Network
var enet_peer: ENetMultiplayerPeer = null
var signalr_client: Node = null
var http_client: HTTPRequest = null

# Timing
var heartbeat_timer: float = 0.0
var heartbeat_interval: float = 30.0
var auto_start_timer: float = 0.0

enum GameStatus {
	WAITING,
	STARTING,
	IN_PROGRESS,
	INTERMISSION,
	GAME_OVER
}

class PlayerData:
	var peer_id: int = 0
	var player_id: int = 0
	var username: String = ""
	var steam_id: int = 0
	var level: int = 1
	var character_class: String = ""
	var is_ready: bool = false
	var is_alive: bool = true
	var score: int = 0
	var kills: int = 0
	var deaths: int = 0
	var position: Vector3 = Vector3.ZERO
	var rotation: Vector3 = Vector3.ZERO
	var health: float = 100.0
	var max_health: float = 100.0

	func to_dict() -> Dictionary:
		return {
			"peer_id": peer_id,
			"player_id": player_id,
			"username": username,
			"steam_id": steam_id,
			"level": level,
			"character_class": character_class,
			"is_ready": is_ready,
			"is_alive": is_alive,
			"score": score,
			"kills": kills,
			"deaths": deaths
		}

func _ready():
	print("===========================================")
	print("  Zombie Survival Dedicated Server")
	print("  Version: 1.0.0")
	print("===========================================")

	# Parse command line arguments
	_parse_command_line_args()

	# Check if we're running in dedicated server mode
	if _is_dedicated_server_mode():
		# Disable rendering for headless mode
		if DisplayServer.get_name() == "headless":
			print("Running in headless mode")

		# Auto-start the server
		call_deferred("start_server")

func _parse_command_line_args():
	var args = OS.get_cmdline_args()

	for i in range(args.size()):
		var arg = args[i]

		if arg == "--server-name" and i + 1 < args.size():
			server_name = args[i + 1]
		elif arg == "--port" and i + 1 < args.size():
			server_port = int(args[i + 1])
		elif arg == "--max-players" and i + 1 < args.size():
			max_players = int(args[i + 1])
		elif arg == "--region" and i + 1 < args.size():
			region = args[i + 1]
		elif arg == "--map" and i + 1 < args.size():
			map_name = args[i + 1]
		elif arg == "--difficulty" and i + 1 < args.size():
			difficulty = args[i + 1]
		elif arg == "--game-mode" and i + 1 < args.size():
			game_mode = args[i + 1]

func _is_dedicated_server_mode() -> bool:
	return "--dedicated" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_args()

func _process(delta):
	if not is_running:
		return

	# Heartbeat to backend
	heartbeat_timer += delta
	if heartbeat_timer >= heartbeat_interval:
		heartbeat_timer = 0.0
		_send_heartbeat()

	# Auto-start game when enough players
	if game_status == GameStatus.WAITING and connected_players.size() >= min_players_to_start:
		auto_start_timer += delta
		if auto_start_timer >= auto_start_delay:
			_start_game()

# ============================================
# SERVER LIFECYCLE
# ============================================

func start_server() -> bool:
	if is_running:
		return false

	print("Starting dedicated server on port %d..." % server_port)

	# Create ENet server
	enet_peer = ENetMultiplayerPeer.new()
	var result = enet_peer.create_server(server_port, max_players)

	if result != OK:
		push_error("Failed to create server: %d" % result)
		return false

	multiplayer.multiplayer_peer = enet_peer

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	is_running = true

	# Register with backend
	_register_with_backend()

	# Load the game map
	_load_map(map_name)

	print("Server started successfully!")
	print("  Name: %s" % server_name)
	print("  Port: %d" % server_port)
	print("  Max Players: %d" % max_players)
	print("  Map: %s" % map_name)
	print("  Difficulty: %s" % difficulty)
	print("Waiting for players...")

	server_started.emit(server_id)
	return true

func stop_server():
	if not is_running:
		return

	print("Stopping server...")

	# Notify all players
	_notify_all_players.rpc("server_shutdown", {"reason": "Server shutting down"})

	# Deregister from backend
	_deregister_from_backend()

	# Close connections
	if enet_peer:
		enet_peer.close()
		enet_peer = null

	multiplayer.multiplayer_peer = null

	# Cleanup
	connected_players.clear()
	player_entities.clear()
	is_running = false
	server_id = -1
	server_token = ""

	server_stopped.emit()
	print("Server stopped")

func _load_map(map: String):
	var map_path = "res://scenes/levels/%s.tscn" % map

	if ResourceLoader.exists(map_path):
		get_tree().change_scene_to_file(map_path)
		print("Loaded map: %s" % map)
	else:
		push_error("Map not found: %s" % map_path)
		# Load default map
		get_tree().change_scene_to_file("res://scenes/levels/arena_01.tscn")

# ============================================
# BACKEND REGISTRATION
# ============================================

func _register_with_backend():
	print("Registering with backend at %s..." % BACKEND_URL)

	http_client = HTTPRequest.new()
	add_child(http_client)

	var url = BACKEND_URL + "/api/servers/register"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({
		"name": server_name,
		"port": server_port,
		"region": region,
		"mapName": map_name,
		"gameMode": game_mode,
		"maxPlayers": max_players,
		"difficulty": difficulty
	})

	http_client.request_completed.connect(_on_registration_completed)
	http_client.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_registration_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	http_client.request_completed.disconnect(_on_registration_completed)

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_error("Failed to register with backend: %d, %d" % [result, response_code])
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		push_error("Failed to parse registration response")
		return

	var response = json.data
	server_id = response.get("id", -1)
	server_token = response.get("serverToken", "")

	print("Registered with backend! Server ID: %d" % server_id)

func _deregister_from_backend():
	if server_id <= 0 or server_token.is_empty():
		return

	var url = BACKEND_URL + "/api/servers/%d" % server_id
	var headers = [
		"Content-Type: application/json",
		"X-Server-Token: %s" % server_token
	]

	http_client.request(url, headers, HTTPClient.METHOD_DELETE)

func _send_heartbeat():
	if server_id <= 0 or server_token.is_empty():
		return

	var url = BACKEND_URL + "/api/servers/%d/heartbeat" % server_id
	var headers = [
		"Content-Type: application/json",
		"X-Server-Token: %s" % server_token
	]
	var body = JSON.stringify({
		"currentPlayers": connected_players.size(),
		"currentWave": current_wave,
		"status": _get_status_string()
	})

	# Use a separate HTTPRequest for heartbeat
	var heartbeat_http = HTTPRequest.new()
	add_child(heartbeat_http)
	heartbeat_http.request_completed.connect(func(_r, _c, _h, _b): heartbeat_http.queue_free())
	heartbeat_http.request(url, headers, HTTPClient.METHOD_POST, body)

func _get_status_string() -> String:
	match game_status:
		GameStatus.WAITING: return "waiting"
		GameStatus.STARTING: return "starting"
		GameStatus.IN_PROGRESS: return "in_progress"
		GameStatus.INTERMISSION: return "intermission"
		GameStatus.GAME_OVER: return "ended"
	return "unknown"

# ============================================
# PLAYER MANAGEMENT
# ============================================

func _on_peer_connected(peer_id: int):
	print("Peer connected: %d" % peer_id)

	# Create placeholder player data
	var player = PlayerData.new()
	player.peer_id = peer_id
	connected_players[peer_id] = player

	# Send server info to new player
	_send_server_info.rpc_id(peer_id, {
		"server_id": server_id,
		"server_name": server_name,
		"map_name": map_name,
		"game_mode": game_mode,
		"difficulty": difficulty,
		"current_wave": current_wave,
		"game_status": game_status,
		"players": _get_all_player_info()
	})

	# Notify other players
	_notify_player_joined.rpc(peer_id, player.to_dict())

func _on_peer_disconnected(peer_id: int):
	print("Peer disconnected: %d" % peer_id)

	if connected_players.has(peer_id):
		var player = connected_players[peer_id]
		connected_players.erase(peer_id)

		# Remove player entity
		if player_entities.has(peer_id):
			player_entities[peer_id].queue_free()
			player_entities.erase(peer_id)

		# Notify other players
		_notify_player_left.rpc(peer_id)

		player_left.emit(peer_id)

	# Reset auto-start timer if not enough players
	if connected_players.size() < min_players_to_start:
		auto_start_timer = 0.0

func _get_all_player_info() -> Array:
	var info = []
	for peer_id in connected_players:
		info.append(connected_players[peer_id].to_dict())
	return info

# ============================================
# GAME FLOW
# ============================================

func _start_game():
	if game_status != GameStatus.WAITING:
		return

	print("Starting game...")
	game_status = GameStatus.STARTING
	auto_start_timer = 0.0

	# Notify all players
	_notify_game_starting.rpc()

	# Spawn all players
	for peer_id in connected_players:
		_spawn_player(peer_id)

	# Start first wave after a short delay
	await get_tree().create_timer(3.0).timeout

	game_status = GameStatus.IN_PROGRESS
	_start_wave(1)

	game_started.emit()

func _start_wave(wave_number: int):
	current_wave = wave_number
	print("Starting wave %d" % wave_number)

	# Notify all players
	_notify_wave_start.rpc(wave_number)
	wave_started.emit(wave_number)

	# Spawn zombies (this would integrate with your wave manager)
	var wave_manager = get_node_or_null("/root/Main/WaveManager")
	if wave_manager and wave_manager.has_method("start_wave"):
		wave_manager.start_wave(wave_number)

func _end_wave(wave_number: int):
	print("Wave %d completed" % wave_number)
	game_status = GameStatus.INTERMISSION

	# Notify all players
	_notify_wave_complete.rpc(wave_number)
	wave_completed.emit(wave_number)

	# Start next wave after intermission
	await get_tree().create_timer(10.0).timeout

	game_status = GameStatus.IN_PROGRESS
	_start_wave(wave_number + 1)

func end_game(victory: bool):
	print("Game ended. Victory: %s" % str(victory))
	game_status = GameStatus.GAME_OVER

	# Collect stats
	var stats = []
	for peer_id in connected_players:
		stats.append(connected_players[peer_id].to_dict())

	# Notify all players
	_notify_game_end.rpc(victory, current_wave, stats)
	game_ended.emit(victory)

	# Reset after delay
	await get_tree().create_timer(15.0).timeout
	_reset_game()

func _reset_game():
	print("Resetting game...")
	game_status = GameStatus.WAITING
	current_wave = 0
	auto_start_timer = 0.0

	# Reset player stats
	for peer_id in connected_players:
		var player = connected_players[peer_id]
		player.score = 0
		player.kills = 0
		player.deaths = 0
		player.is_alive = true
		player.health = player.max_health

	# Despawn all player entities
	for peer_id in player_entities.keys():
		if is_instance_valid(player_entities[peer_id]):
			player_entities[peer_id].queue_free()
	player_entities.clear()

	# Reload map
	_load_map(map_name)

	print("Waiting for players...")

# ============================================
# PLAYER SPAWNING
# ============================================

func _spawn_player(peer_id: int):
	if not connected_players.has(peer_id):
		return

	var player_scene = preload("res://scenes/player/player_fps.tscn")
	var player_node = player_scene.instantiate()

	player_node.name = "Player_%d" % peer_id
	player_node.set_multiplayer_authority(peer_id)

	# Get spawn point
	var spawn_pos = _get_spawn_position()
	player_node.global_position = spawn_pos

	# Add to scene
	var scene = get_tree().current_scene
	if scene:
		scene.add_child(player_node)
		player_entities[peer_id] = player_node
		connected_players[peer_id].position = spawn_pos
		connected_players[peer_id].is_alive = true

		# Notify the client about spawn
		_notify_player_spawned.rpc_id(peer_id, spawn_pos)

		print("Spawned player %d at %s" % [peer_id, spawn_pos])

func _get_spawn_position() -> Vector3:
	var spawn_points = get_tree().get_nodes_in_group("player_spawn")
	if spawn_points.size() > 0:
		return spawn_points[randi() % spawn_points.size()].global_position
	return Vector3(0, 1, 0)

func respawn_player(peer_id: int):
	if not connected_players.has(peer_id):
		return

	# Remove old entity
	if player_entities.has(peer_id) and is_instance_valid(player_entities[peer_id]):
		player_entities[peer_id].queue_free()
		player_entities.erase(peer_id)

	# Spawn new entity
	_spawn_player(peer_id)

	# Notify all players
	var pos = connected_players[peer_id].position
	_notify_player_respawned.rpc(peer_id, pos)

# ============================================
# RPC - SERVER TO CLIENTS
# ============================================

@rpc("authority", "reliable")
func _send_server_info(_info: Dictionary):
	# Client receives this
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_player_joined(_peer_id: int, _player_info: Dictionary):
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_player_left(_peer_id: int):
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_all_players(_event: String, _data: Dictionary):
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_game_starting():
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_wave_start(_wave_number: int):
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_wave_complete(_wave_number: int):
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_game_end(_victory: bool, _wave_reached: int, _stats: Array):
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_player_spawned(_position: Vector3):
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_player_respawned(_peer_id: int, _position: Vector3):
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func broadcast_entity_states(_states: Array):
	pass

@rpc("authority", "call_remote", "reliable")
func broadcast_game_event(_event_name: String, _event_data: Dictionary):
	pass

# ============================================
# RPC - CLIENTS TO SERVER
# ============================================

@rpc("any_peer", "reliable")
func register_player(player_info: Dictionary):
	var peer_id = multiplayer.get_remote_sender_id()

	if connected_players.has(peer_id):
		var player = connected_players[peer_id]
		player.username = player_info.get("name", player_info.get("username", "Player"))
		player.player_id = player_info.get("player_id", 0)
		player.steam_id = player_info.get("steam_id", 0)
		player.level = player_info.get("level", 1)
		player.character_class = player_info.get("character_class", "")

		print("Player registered: %s (peer %d)" % [player.username, peer_id])

		player_joined.emit(peer_id, player.to_dict())

		# Broadcast updated player info to all
		_notify_player_joined.rpc(peer_id, player.to_dict())

@rpc("any_peer", "reliable")
func set_player_ready(is_ready: bool):
	var peer_id = multiplayer.get_remote_sender_id()

	if connected_players.has(peer_id):
		connected_players[peer_id].is_ready = is_ready

		# Broadcast ready state
		_sync_player_ready.rpc(peer_id, is_ready)

		# Check if all players ready
		if _are_all_players_ready() and game_status == GameStatus.WAITING:
			_start_game()

@rpc("authority", "call_remote", "reliable")
func _sync_player_ready(_peer_id: int, _is_ready: bool):
	pass

func _are_all_players_ready() -> bool:
	if connected_players.is_empty():
		return false
	for peer_id in connected_players:
		if not connected_players[peer_id].is_ready:
			return false
	return true

@rpc("any_peer", "unreliable_ordered")
func receive_player_state(state: Dictionary):
	var peer_id = multiplayer.get_remote_sender_id()

	if connected_players.has(peer_id):
		var player = connected_players[peer_id]

		if state.has("position"):
			player.position = state.position
		if state.has("rotation"):
			player.rotation = state.rotation
		if state.has("health"):
			player.health = state.health

@rpc("any_peer", "reliable")
func player_action(action_type: String, action_data: Dictionary):
	var peer_id = multiplayer.get_remote_sender_id()

	match action_type:
		"shoot":
			_handle_shoot(peer_id, action_data)
		"reload":
			_handle_reload(peer_id, action_data)
		"use_item":
			_handle_use_item(peer_id, action_data)
		"interact":
			_handle_interact(peer_id, action_data)

func _handle_shoot(peer_id: int, data: Dictionary):
	# Validate and process shot
	var origin = data.get("origin", Vector3.ZERO)
	var direction = data.get("direction", Vector3.FORWARD)
	var weapon = data.get("weapon", "rifle")

	# Broadcast to all players
	_broadcast_shot.rpc(peer_id, origin, direction, weapon)

@rpc("authority", "call_remote", "unreliable_ordered")
func _broadcast_shot(_peer_id: int, _origin: Vector3, _direction: Vector3, _weapon: String):
	pass

func _handle_reload(peer_id: int, data: Dictionary):
	var weapon = data.get("weapon", "rifle")
	_broadcast_reload.rpc(peer_id, weapon)

@rpc("authority", "call_remote", "reliable")
func _broadcast_reload(_peer_id: int, _weapon: String):
	pass

func _handle_use_item(_peer_id: int, _data: Dictionary):
	pass

func _handle_interact(_peer_id: int, _data: Dictionary):
	pass

# ============================================
# DAMAGE SYSTEM
# ============================================

func apply_damage_to_player(peer_id: int, damage: float, attacker_name: String = ""):
	if not connected_players.has(peer_id):
		return

	var player = connected_players[peer_id]
	player.health = max(0, player.health - damage)

	# Broadcast damage
	_notify_player_damage.rpc(peer_id, damage, player.health)

	# Check for death
	if player.health <= 0:
		_handle_player_death(peer_id, attacker_name)

@rpc("authority", "call_remote", "reliable")
func _notify_player_damage(_peer_id: int, _damage: float, _new_health: float):
	pass

func _handle_player_death(peer_id: int, killer_name: String):
	if not connected_players.has(peer_id):
		return

	var player = connected_players[peer_id]
	player.is_alive = false
	player.deaths += 1

	print("Player %s died. Killed by: %s" % [player.username, killer_name])

	# Broadcast death
	_notify_player_death.rpc(peer_id, killer_name)

	# Check if all players dead
	if _are_all_players_dead():
		end_game(false)

	# Auto-respawn after delay
	await get_tree().create_timer(5.0).timeout
	if is_running and game_status == GameStatus.IN_PROGRESS:
		respawn_player(peer_id)

@rpc("authority", "call_remote", "reliable")
func _notify_player_death(_peer_id: int, _killer_name: String):
	pass

func _are_all_players_dead() -> bool:
	for peer_id in connected_players:
		if connected_players[peer_id].is_alive:
			return false
	return true

# ============================================
# ZOMBIE EVENTS
# ============================================

func on_zombie_killed(zombie_id: int, killer_peer_id: int, drop_data: Dictionary = {}):
	# Award kill to player
	if connected_players.has(killer_peer_id):
		connected_players[killer_peer_id].kills += 1
		connected_players[killer_peer_id].score += 10

	# Broadcast to all
	_notify_zombie_killed.rpc(zombie_id, killer_peer_id, drop_data)

@rpc("authority", "call_remote", "reliable")
func _notify_zombie_killed(_zombie_id: int, _killer_peer_id: int, _drop_data: Dictionary):
	pass

func on_all_zombies_killed():
	_end_wave(current_wave)

# ============================================
# STATE SYNC
# ============================================

var sync_timer: float = 0.0
var sync_interval: float = 0.05  # 20 Hz

func _physics_process(delta):
	if not is_running or game_status != GameStatus.IN_PROGRESS:
		return

	sync_timer += delta
	if sync_timer >= sync_interval:
		sync_timer = 0.0
		_sync_game_state()

func _sync_game_state():
	# Collect entity states
	var states = []

	# Player states
	for peer_id in player_entities:
		if not is_instance_valid(player_entities[peer_id]):
			continue

		var entity = player_entities[peer_id]
		states.append({
			"entity_id": peer_id,
			"type": "player",
			"pos": _vec3_to_array(entity.global_position),
			"rot": _vec3_to_array(entity.rotation),
			"data": {
				"health": connected_players[peer_id].health if connected_players.has(peer_id) else 100.0
			}
		})

	# Zombie states (would integrate with zombie manager)
	var zombies = get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if not is_instance_valid(zombie):
			continue
		states.append({
			"entity_id": zombie.get_instance_id(),
			"type": "zombie",
			"pos": _vec3_to_array(zombie.global_position),
			"rot": _vec3_to_array(zombie.rotation),
			"data": {
				"health": zombie.health if "health" in zombie else 100.0
			}
		})

	# Broadcast
	if states.size() > 0:
		broadcast_entity_states.rpc(states)

func _vec3_to_array(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

# ============================================
# UTILITY
# ============================================

func get_player_count() -> int:
	return connected_players.size()

func get_player(peer_id: int) -> PlayerData:
	return connected_players.get(peer_id, null)

func kick_player(peer_id: int, reason: String = ""):
	if not connected_players.has(peer_id):
		return

	print("Kicking player %d: %s" % [peer_id, reason])

	# Notify the player
	_notify_kicked.rpc_id(peer_id, reason)

	# Disconnect after short delay
	await get_tree().create_timer(0.5).timeout
	if enet_peer:
		enet_peer.disconnect_peer(peer_id)

@rpc("authority", "reliable")
func _notify_kicked(_reason: String):
	pass

func broadcast_chat(sender_peer: int, message: String):
	var username = "Server"
	if connected_players.has(sender_peer):
		username = connected_players[sender_peer].username

	_broadcast_chat_message.rpc(sender_peer, username, message)

@rpc("authority", "call_local", "reliable")
func _broadcast_chat_message(_peer_id: int, _username: String, _message: String):
	pass
