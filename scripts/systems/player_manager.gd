extends Node
class_name PlayerManager

# Manages all players in the game (local and remote)
# Handles spawning, respawning, tracking, and player state

signal player_spawned(peer_id: int, player: Node)
signal player_despawned(peer_id: int)
signal player_died(peer_id: int, killer_id: int)
signal player_respawned(peer_id: int)
signal all_players_dead
signal local_player_ready(player: Node)

# Player scenes
@export var local_player_scene: PackedScene
@export var observed_player_scene: PackedScene

# Respawn settings
@export var respawn_enabled: bool = true
@export var respawn_delay: float = 5.0
@export var respawn_waves_only: bool = false  # Only respawn between waves
@export var max_respawns: int = -1  # -1 = unlimited

# Player tracking
var players: Dictionary = {}  # peer_id -> player node
var player_data: Dictionary = {}  # peer_id -> PlayerData
var local_player: Node = null
var local_peer_id: int = 1

# Respawn tracking
var respawn_queue: Array = []  # Array of {peer_id, time_remaining}
var respawn_counts: Dictionary = {}  # peer_id -> respawn count

# State sync
var sync_interval: float = 0.05  # 20Hz state sync
var sync_timer: float = 0.0

# References
var network_manager: Node = null
var spawn_manager: Node = null

class PlayerData:
	var peer_id: int = 0
	var player_name: String = "Player"
	var team_id: int = 0
	var kills: int = 0
	var deaths: int = 0
	var score: int = 0
	var is_alive: bool = true
	var is_ready: bool = false
	var class_type: String = "survivor"
	var loadout: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"peer_id": peer_id,
			"player_name": player_name,
			"team_id": team_id,
			"kills": kills,
			"deaths": deaths,
			"score": score,
			"is_alive": is_alive,
			"class_type": class_type
		}

func _ready():
	# Get references
	network_manager = get_node_or_null("/root/NetworkManager")
	spawn_manager = get_node_or_null("/root/SpawnManager")

	# Connect network signals
	if network_manager:
		if network_manager.has_signal("player_connected"):
			network_manager.player_connected.connect(_on_player_connected)
		if network_manager.has_signal("player_disconnected"):
			network_manager.player_disconnected.connect(_on_player_disconnected)
		if network_manager.has_signal("all_players_loaded"):
			network_manager.all_players_loaded.connect(_on_all_players_loaded)

	# Load default scenes if not set
	if not local_player_scene:
		local_player_scene = load("res://scenes/player/player_fps.tscn")
	if not observed_player_scene:
		observed_player_scene = load("res://scenes/player/observed_player.tscn")

func _process(delta):
	# Process respawn queue
	_process_respawn_queue(delta)

	# Sync local player state to network
	_sync_local_player_state(delta)

# ============================================
# PLAYER SPAWNING
# ============================================

func spawn_local_player(spawn_position: Vector3 = Vector3.ZERO) -> Node:
	"""Spawn the local player"""
	if local_player and is_instance_valid(local_player):
		push_warning("Local player already exists")
		return local_player

	if not local_player_scene:
		push_error("No local player scene set")
		return null

	local_player = local_player_scene.instantiate()

	# Set multiplayer authority
	local_peer_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	local_player.set_multiplayer_authority(local_peer_id)
	local_player.name = "Player_%d" % local_peer_id

	# Get spawn position
	if spawn_position == Vector3.ZERO and spawn_manager:
		spawn_position = spawn_manager.get_spawn_position()

	# Add to scene
	var scene = get_tree().current_scene
	if scene:
		scene.add_child(local_player)
		local_player.global_position = spawn_position

	# Track player
	players[local_peer_id] = local_player
	_init_player_data(local_peer_id)

	# Connect signals
	_connect_player_signals(local_player, local_peer_id)

	player_spawned.emit(local_peer_id, local_player)
	local_player_ready.emit(local_player)

	return local_player

func spawn_observed_player(peer_id: int, player_info: Dictionary, spawn_position: Vector3 = Vector3.ZERO) -> Node:
	"""Spawn a remote player representation"""
	if players.has(peer_id):
		push_warning("Player %d already exists" % peer_id)
		return players[peer_id]

	if not observed_player_scene:
		push_error("No observed player scene set")
		return null

	var player = observed_player_scene.instantiate()

	# Configure observed player
	if player.has_method("set_player_info"):
		player.set_player_info({
			"peer_id": peer_id,
			"name": player_info.get("name", "Player %d" % peer_id),
			"team": player_info.get("team", 0)
		})

	player.set_multiplayer_authority(peer_id)
	player.name = "ObservedPlayer_%d" % peer_id

	# Get spawn position
	if spawn_position == Vector3.ZERO and spawn_manager:
		spawn_position = spawn_manager.get_spawn_position()

	# Add to scene
	var scene = get_tree().current_scene
	if scene:
		scene.add_child(player)
		player.global_position = spawn_position

	# Track player
	players[peer_id] = player
	_init_player_data(peer_id, player_info)

	# Connect signals
	_connect_observed_player_signals(player, peer_id)

	player_spawned.emit(peer_id, player)

	return player

func despawn_player(peer_id: int):
	"""Remove a player from the game"""
	if not players.has(peer_id):
		return

	var player = players[peer_id]
	if is_instance_valid(player):
		player.queue_free()

	players.erase(peer_id)

	# Remove from respawn queue
	respawn_queue = respawn_queue.filter(func(r): return r.peer_id != peer_id)

	player_despawned.emit(peer_id)

	if peer_id == local_peer_id:
		local_player = null

func despawn_all_players():
	"""Remove all players"""
	for peer_id in players.keys():
		despawn_player(peer_id)

func spawn_all_players():
	"""Spawn all connected players"""
	# Spawn local player first
	spawn_local_player()

	# Spawn observed players for other peers
	if network_manager:
		var all_players = network_manager.get_players() if network_manager.has_method("get_players") else {}
		for peer_id in all_players:
			if peer_id != local_peer_id:
				spawn_observed_player(peer_id, all_players[peer_id])

# ============================================
# RESPAWNING
# ============================================

func queue_respawn(peer_id: int, delay: float = -1.0):
	"""Add a player to the respawn queue"""
	if not respawn_enabled:
		return

	# Check respawn limit
	if max_respawns >= 0:
		var count = respawn_counts.get(peer_id, 0)
		if count >= max_respawns:
			return

	if delay < 0:
		delay = respawn_delay

	# Add to queue
	respawn_queue.append({
		"peer_id": peer_id,
		"time_remaining": delay
	})

func _process_respawn_queue(delta: float):
	var to_respawn = []

	for i in range(respawn_queue.size() - 1, -1, -1):
		respawn_queue[i].time_remaining -= delta

		if respawn_queue[i].time_remaining <= 0:
			to_respawn.append(respawn_queue[i].peer_id)
			respawn_queue.remove_at(i)

	for peer_id in to_respawn:
		respawn_player(peer_id)

func respawn_player(peer_id: int):
	"""Respawn a dead player"""
	if not players.has(peer_id):
		return

	var player = players[peer_id]
	if not is_instance_valid(player):
		return

	# Get spawn position
	var spawn_pos = Vector3.ZERO
	if spawn_manager:
		spawn_pos = spawn_manager.get_spawn_position()

	# Respawn logic differs for local vs observed
	if peer_id == local_peer_id:
		_respawn_local_player(player, spawn_pos)
	else:
		_respawn_observed_player(player, spawn_pos)

	# Update tracking
	if player_data.has(peer_id):
		player_data[peer_id].is_alive = true

	respawn_counts[peer_id] = respawn_counts.get(peer_id, 0) + 1

	# Notify network
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_respawn.rpc(peer_id, spawn_pos)

	player_respawned.emit(peer_id)

func _respawn_local_player(player: Node, spawn_pos: Vector3):
	"""Respawn the local player"""
	player.global_position = spawn_pos

	if player.has_method("respawn"):
		player.respawn()
	else:
		# Manual respawn
		if "current_health" in player:
			player.current_health = player.max_health if "max_health" in player else 100.0
		if "is_dead" in player:
			player.is_dead = false

func _respawn_observed_player(player: Node, spawn_pos: Vector3):
	"""Respawn an observed player"""
	if player.has_method("respawn"):
		player.respawn()

	if player.has_method("receive_state"):
		player.receive_state({"position": spawn_pos})

@rpc("authority", "call_remote", "reliable")
func _sync_respawn(peer_id: int, spawn_pos: Vector3):
	"""Sync respawn to clients"""
	if players.has(peer_id):
		var player = players[peer_id]
		if peer_id == local_peer_id:
			_respawn_local_player(player, spawn_pos)
		else:
			_respawn_observed_player(player, spawn_pos)

		player_respawned.emit(peer_id)

# ============================================
# PLAYER DEATH
# ============================================

func on_player_died(peer_id: int, killer_id: int = -1):
	"""Handle player death"""
	if player_data.has(peer_id):
		player_data[peer_id].is_alive = false
		player_data[peer_id].deaths += 1

	# Track kill
	if killer_id > 0 and player_data.has(killer_id):
		player_data[killer_id].kills += 1

	player_died.emit(peer_id, killer_id)

	# Check if all players are dead
	var any_alive = false
	for data in player_data.values():
		if data.is_alive:
			any_alive = true
			break

	if not any_alive:
		all_players_dead.emit()

	# Queue respawn
	queue_respawn(peer_id)

# ============================================
# STATE SYNCHRONIZATION
# ============================================

func _sync_local_player_state(delta: float):
	"""Periodically sync local player state to network"""
	if not local_player or not is_instance_valid(local_player):
		return

	if not multiplayer.has_multiplayer_peer():
		return

	sync_timer += delta
	if sync_timer < sync_interval:
		return

	sync_timer = 0.0

	# Build state packet
	var state = _build_player_state(local_player)

	# Send to all peers
	_broadcast_player_state.rpc(state)

func _build_player_state(player: Node) -> Dictionary:
	"""Build a state dictionary from player"""
	var state = {
		"position": player.global_position,
		"rotation": player.rotation.y,
		"head_rotation": 0.0,
		"health": 100.0,
		"max_health": 100.0,
		"is_sprinting": false,
		"is_crouching": false,
		"is_aiming": false,
		"weapon": "",
		"is_reloading": false
	}

	# Get head rotation from camera
	var camera = player.get_node_or_null("Camera3D")
	if camera:
		state.head_rotation = camera.rotation.x

	# Get health
	if "current_health" in player:
		state.health = player.current_health
	if "max_health" in player:
		state.max_health = player.max_health

	# Get movement state
	if "is_sprinting" in player:
		state.is_sprinting = player.is_sprinting
	if "is_crouching" in player:
		state.is_crouching = player.is_crouching
	if "is_aiming" in player:
		state.is_aiming = player.is_aiming

	# Get weapon
	if "current_weapon_data" in player and player.current_weapon_data:
		state.weapon = player.current_weapon_data.resource_name if player.current_weapon_data else ""

	return state

@rpc("any_peer", "unreliable_ordered")
func _broadcast_player_state(state: Dictionary):
	"""Receive state from a remote player"""
	var sender_id = multiplayer.get_remote_sender_id()

	if sender_id == local_peer_id:
		return

	if players.has(sender_id):
		var observed = players[sender_id]
		if observed.has_method("receive_state"):
			observed.receive_state(state)

# ============================================
# PLAYER DATA
# ============================================

func _init_player_data(peer_id: int, info: Dictionary = {}):
	"""Initialize player data tracking"""
	var data = PlayerData.new()
	data.peer_id = peer_id
	data.player_name = info.get("name", "Player %d" % peer_id)
	data.team_id = info.get("team", 0)
	data.class_type = info.get("class", "survivor")
	data.is_alive = true

	player_data[peer_id] = data
	respawn_counts[peer_id] = 0

func get_player(peer_id: int) -> Node:
	"""Get a player node by peer ID"""
	return players.get(peer_id, null)

func get_local_player() -> Node:
	"""Get the local player"""
	return local_player

func get_all_players() -> Array:
	"""Get all player nodes"""
	return players.values()

func get_alive_players() -> Array:
	"""Get all living player nodes"""
	var alive = []
	for peer_id in players:
		if player_data.has(peer_id) and player_data[peer_id].is_alive:
			alive.append(players[peer_id])
	return alive

func get_player_data(peer_id: int) -> PlayerData:
	"""Get player data by peer ID"""
	return player_data.get(peer_id, null)

func get_player_count() -> int:
	"""Get total number of players"""
	return players.size()

func get_alive_count() -> int:
	"""Get number of living players"""
	var count = 0
	for data in player_data.values():
		if data.is_alive:
			count += 1
	return count

# ============================================
# SIGNALS
# ============================================

func _connect_player_signals(player: Node, peer_id: int):
	"""Connect to local player signals"""
	if player.has_signal("died"):
		player.died.connect(_on_local_player_died.bind(peer_id))
	elif player.has_signal("player_died"):
		player.player_died.connect(_on_local_player_died.bind(peer_id))

func _connect_observed_player_signals(player: Node, peer_id: int):
	"""Connect to observed player signals"""
	if player.has_signal("player_died"):
		player.player_died.connect(_on_observed_player_died)

func _on_local_player_died(peer_id: int):
	on_player_died(peer_id)

func _on_observed_player_died(id: int):
	on_player_died(id)

func _on_player_connected(peer_id: int, player_info: Dictionary):
	"""Handle new player connection"""
	spawn_observed_player(peer_id, player_info)

func _on_player_disconnected(peer_id: int):
	"""Handle player disconnection"""
	despawn_player(peer_id)
	player_data.erase(peer_id)
	respawn_counts.erase(peer_id)

func _on_all_players_loaded():
	"""Handle all players loaded"""
	spawn_all_players()
