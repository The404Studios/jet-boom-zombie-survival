extends Node

# Network manager for multiplayer using Godot's high-level multiplayer API
# Integrates with Steam P2P networking

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_started
signal server_stopped
signal connected_to_server
signal connection_failed
signal disconnected_from_server

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

var is_server: bool = false
var is_client: bool = false
var local_player_id: int = 1

var players: Dictionary = {}  # peer_id -> player_info
var player_nodes: Dictionary = {}  # peer_id -> Player node

@onready var steam_manager: Node = get_node("/root/SteamManager") if has_node("/root/SteamManager") else null

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ============================================
# SERVER / HOST
# ============================================

func create_server_steam(lobby_id: int) -> bool:
	if not steam_manager or not steam_manager.is_initialized():
		print("Steam not initialized!")
		return false

	# Use Steam P2P networking
	var peer = ENetMultiplayerPeer.new()

	# For Steam, we use Steam's P2P instead of ENet
	# This requires GodotSteam's network implementation
	# For now, using ENet as fallback

	var result = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)

	if result != OK:
		print("Failed to create server: ", result)
		return false

	multiplayer.multiplayer_peer = peer
	is_server = true
	local_player_id = multiplayer.get_unique_id()

	# Register local player
	register_player(local_player_id, get_local_player_info())

	server_started.emit()
	print("Server started on port %d" % DEFAULT_PORT)

	return true

func create_server_lan() -> bool:
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)

	if result != OK:
		print("Failed to create LAN server: ", result)
		return false

	multiplayer.multiplayer_peer = peer
	is_server = true
	local_player_id = multiplayer.get_unique_id()

	register_player(local_player_id, get_local_player_info())

	server_started.emit()
	print("LAN server started")

	return true

func stop_server():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	is_server = false
	is_client = false
	players.clear()
	player_nodes.clear()

	server_stopped.emit()

# ============================================
# CLIENT
# ============================================

func join_server_steam(lobby_id: int) -> bool:
	if not steam_manager or not steam_manager.is_initialized():
		return false

	# Get lobby owner's Steam ID to connect to
	var steam = Engine.get_singleton("Steam")
	var owner_id = steam.getLobbyOwner(lobby_id)

	# For Steam P2P, we'd use Steam's networking here
	# Fallback to LAN for now
	return join_server_lan("127.0.0.1")

func join_server_lan(ip: String) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_client(ip, DEFAULT_PORT)

	if result != OK:
		print("Failed to connect to server: ", result)
		connection_failed.emit()
		return false

	multiplayer.multiplayer_peer = peer
	is_client = true

	return true

func disconnect_from_server():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	is_client = false
	is_server = false
	players.clear()
	player_nodes.clear()

	disconnected_from_server.emit()

# ============================================
# PLAYER MANAGEMENT
# ============================================

func register_player(peer_id: int, player_info: Dictionary):
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)

	print("Player registered: %s (ID: %d)" % [player_info.name, peer_id])

	# Spawn player node
	spawn_player(peer_id, player_info)

@rpc("any_peer", "reliable")
func sync_player_info(player_info: Dictionary):
	var peer_id = multiplayer.get_remote_sender_id()
	register_player(peer_id, player_info)

	# Send our info back if we're server
	if is_server:
		rpc_id(peer_id, "receive_all_players", players)

@rpc("authority", "reliable")
func receive_all_players(all_players: Dictionary):
	for peer_id in all_players:
		if peer_id != local_player_id and not players.has(peer_id):
			register_player(peer_id, all_players[peer_id])

func spawn_player(peer_id: int, player_info: Dictionary):
	# Spawn player node
	var player_scene = preload("res://scenes/player/player.tscn")
	var player = player_scene.instantiate()

	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)

	# Set spawn position
	var spawn_points = get_tree().get_nodes_in_group("player_spawn")
	if spawn_points.size() > 0:
		var spawn = spawn_points[randi() % spawn_points.size()]
		player.global_position = spawn.global_position

	get_tree().current_scene.add_child(player)
	player_nodes[peer_id] = player

	print("Spawned player node for peer %d" % peer_id)

func despawn_player(peer_id: int):
	if player_nodes.has(peer_id):
		player_nodes[peer_id].queue_free()
		player_nodes.erase(peer_id)

# ============================================
# GAME STATE SYNC
# ============================================

@rpc("authority", "reliable")
func sync_wave_state(wave: int, zombies_alive: int, is_intermission: bool):
	# Sync wave state to clients
	var wave_manager = get_node_or_null("/root/Main/WaveManager")
	if wave_manager:
		wave_manager.current_wave = wave
		wave_manager.zombies_alive = zombies_alive
		wave_manager.is_intermission = is_intermission

@rpc("authority", "call_local")
func spawn_zombie_networked(zombie_class_name: String, position: Vector3, zombie_id: int):
	# Spawn zombie on all clients
	var zombie_scene = preload("res://scenes/zombies/zombie.tscn")
	var zombie = zombie_scene.instantiate()

	zombie.name = "Zombie_%d" % zombie_id
	zombie.global_position = position

	get_tree().current_scene.add_child(zombie)

@rpc("any_peer", "call_local")
func damage_zombie(zombie_path: NodePath, damage: float, is_headshot: bool):
	var zombie = get_node_or_null(zombie_path)
	if zombie and zombie.has_method("take_damage"):
		zombie.take_damage(damage, Vector3.ZERO)

@rpc("any_peer", "call_local")
func player_shoot(player_id: int, origin: Vector3, direction: Vector3):
	# Handle player shooting on all clients for visual effects
	pass

# ============================================
# CALLBACKS
# ============================================

func _on_peer_connected(peer_id: int):
	print("Peer connected: %d" % peer_id)

	if is_server:
		# Server: Wait for client to send their info
		pass
	else:
		# Client: Send our info to server
		rpc_id(1, "sync_player_info", get_local_player_info())

func _on_peer_disconnected(peer_id: int):
	print("Peer disconnected: %d" % peer_id)

	if players.has(peer_id):
		players.erase(peer_id)

	despawn_player(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server():
	print("Connected to server!")
	local_player_id = multiplayer.get_unique_id()

	# Send our player info
	rpc_id(1, "sync_player_info", get_local_player_info())

	connected_to_server.emit()

func _on_connection_failed():
	print("Connection to server failed!")
	connection_failed.emit()

func _on_server_disconnected():
	print("Server disconnected!")
	disconnected_from_server.emit()

	disconnect_from_server()

# ============================================
# UTILITY
# ============================================

func get_local_player_info() -> Dictionary:
	var info = {
		"name": "Player",
		"steam_id": 0,
		"level": 1,
		"ready": false
	}

	if steam_manager and steam_manager.is_initialized():
		info.name = steam_manager.get_username()
		info.steam_id = steam_manager.get_steam_id()

	return info

func get_player_info(peer_id: int) -> Dictionary:
	if players.has(peer_id):
		return players[peer_id]
	return {}

func get_player_count() -> int:
	return players.size()

func is_host() -> bool:
	return is_server

func get_local_peer_id() -> int:
	return local_player_id

func set_player_ready(peer_id: int, ready: bool):
	if players.has(peer_id):
		players[peer_id].ready = ready

func are_all_players_ready() -> bool:
	for peer_id in players:
		if not players[peer_id].ready:
			return false
	return true
