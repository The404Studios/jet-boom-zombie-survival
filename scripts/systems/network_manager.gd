extends Node

# Network manager for multiplayer using Steam P2P networking
# Falls back to ENet for LAN play when Steam is unavailable
# Supports dedicated server mode at 162.248.94.149

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_started
signal server_stopped
signal connected_to_server
signal connection_failed
signal disconnected_from_server
signal game_starting
signal all_players_loaded
signal server_info_received(info: Dictionary)
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal game_ended(victory: bool, wave_reached: int, stats: Array)
signal entity_states_received(states: Array)
signal player_spawned(position: Vector3)
signal player_died(peer_id: int, killer_name: String)
signal player_respawned(peer_id: int, position: Vector3)
signal chat_message_received(peer_id: int, username: String, message: String)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 8

# Dedicated server configuration
const DEDICATED_SERVER_IP: String = "162.248.94.149"
const DEDICATED_SERVER_PORT: int = 7777
const BACKEND_SERVER_URL: String = "http://162.248.94.149:5000"

var is_server: bool = false
var is_client: bool = false
var is_dedicated_server: bool = false
var local_player_id: int = 1
var use_steam: bool = false
var current_server_ip: String = ""
var current_server_port: int = DEFAULT_PORT

# Server info (received when connecting to dedicated server)
var server_info: Dictionary = {}
var current_wave: int = 0
var game_status: String = "waiting"

var players: Dictionary = {}  # peer_id -> player_info
var player_nodes: Dictionary = {}  # peer_id -> Player node
var players_loaded: Dictionary = {}  # peer_id -> bool
var observed_players: Dictionary = {}  # peer_id -> ObservedPlayer node

var steam_manager: Node = null
var steam_p2p_peer: RefCounted = null

# Network quality tracking
var network_latency: float = 0.0
var last_ping_time: float = 0.0
var ping_interval: float = 1.0
var connection_quality: int = 100  # 0-100

# Reconnection settings
var reconnect_attempts: int = 0
var max_reconnect_attempts: int = 3
var reconnect_delay: float = 2.0
var last_server_address: String = ""
var last_server_port: int = 0

func _ready():
	# Get Steam manager reference
	steam_manager = get_node_or_null("/root/SteamManager")

	# Check if Steam is available
	if steam_manager and steam_manager.is_initialized():
		use_steam = true
		print("NetworkManager: Using Steam P2P networking")
	else:
		use_steam = false
		print("NetworkManager: Using ENet (LAN) networking")

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Connect to Steam lobby signals if available
	if steam_manager:
		if steam_manager.has_signal("lobby_joined"):
			steam_manager.lobby_joined.connect(_on_steam_lobby_joined)
		if steam_manager.has_signal("lobby_member_joined"):
			steam_manager.lobby_member_joined.connect(_on_steam_lobby_member_joined)
		if steam_manager.has_signal("lobby_member_left"):
			steam_manager.lobby_member_left.connect(_on_steam_lobby_member_left)

func _exit_tree():
	# Disconnect multiplayer signals to prevent memory leaks
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

	# Disconnect Steam signals
	if steam_manager:
		if steam_manager.has_signal("lobby_joined") and steam_manager.lobby_joined.is_connected(_on_steam_lobby_joined):
			steam_manager.lobby_joined.disconnect(_on_steam_lobby_joined)
		if steam_manager.has_signal("lobby_member_joined") and steam_manager.lobby_member_joined.is_connected(_on_steam_lobby_member_joined):
			steam_manager.lobby_member_joined.disconnect(_on_steam_lobby_member_joined)
		if steam_manager.has_signal("lobby_member_left") and steam_manager.lobby_member_left.is_connected(_on_steam_lobby_member_left):
			steam_manager.lobby_member_left.disconnect(_on_steam_lobby_member_left)

# ============================================
# STEAM P2P HOSTING
# ============================================

func host_steam_lobby(lobby_type: int = 1) -> bool:
	"""Host a game using Steam lobbies. lobby_type: 0=private, 1=friends, 2=public"""
	if not steam_manager or not steam_manager.is_initialized():
		print("Steam not available, falling back to LAN")
		return create_server_lan()

	# Create Steam lobby first
	steam_manager.create_lobby(lobby_type)

	# Wait for lobby creation callback - it will call _setup_steam_host
	return true

func _on_steam_lobby_joined(lobby_id: int):
	"""Called when we join or create a lobby"""
	if steam_manager.is_lobby_owner:
		# We created the lobby, set up as host
		_setup_steam_host(lobby_id)
	else:
		# We joined someone else's lobby
		_setup_steam_client(lobby_id)

func _setup_steam_host(lobby_id: int):
	"""Set up Steam P2P hosting after lobby is created"""
	# Create Steam P2P peer
	var SteamP2PPeerClass = load("res://scripts/systems/steam_p2p_peer.gd")
	if not SteamP2PPeerClass:
		push_error("Failed to load steam_p2p_peer.gd")
		return

	steam_p2p_peer = SteamP2PPeerClass.new()
	if not steam_p2p_peer:
		push_error("Failed to instantiate SteamP2PPeer")
		return

	var result = steam_p2p_peer.create_host(MAX_PLAYERS)
	if result != OK:
		print("Failed to create Steam P2P host")
		return

	multiplayer.multiplayer_peer = steam_p2p_peer
	is_server = true
	use_steam = true
	local_player_id = multiplayer.get_unique_id()

	# Set lobby data
	steam_manager.set_lobby_data("host_steam_id", str(steam_manager.get_steam_id()))
	steam_manager.set_lobby_data("game_version", "1.0.0")
	steam_manager.set_lobby_data("status", "waiting")

	# Register local player
	register_player(local_player_id, get_local_player_info())

	server_started.emit()
	print("Steam P2P host created. Lobby ID: %d" % lobby_id)

func _setup_steam_client(lobby_id: int):
	"""Set up Steam P2P client after joining a lobby"""
	# Get host Steam ID from lobby data
	var host_steam_id_str = steam_manager.get_lobby_data("host_steam_id")
	if host_steam_id_str.is_empty():
		print("Failed to get host Steam ID from lobby")
		connection_failed.emit()
		return

	var host_steam_id = int(host_steam_id_str)

	# Create Steam P2P peer as client
	var SteamP2PPeerClass = load("res://scripts/systems/steam_p2p_peer.gd")
	if not SteamP2PPeerClass:
		push_error("Failed to load steam_p2p_peer.gd")
		connection_failed.emit()
		return

	steam_p2p_peer = SteamP2PPeerClass.new()
	if not steam_p2p_peer:
		push_error("Failed to instantiate SteamP2PPeer")
		connection_failed.emit()
		return

	var result = steam_p2p_peer.create_client(host_steam_id)
	if result != OK:
		print("Failed to connect to Steam P2P host")
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = steam_p2p_peer
	is_client = true
	use_steam = true

	print("Connecting to Steam P2P host. Lobby ID: %d" % lobby_id)

func _on_steam_lobby_member_joined(member_id: int, member_name: String):
	"""Called when a player joins the Steam lobby"""
	print("Steam lobby member joined: %s (%d)" % [member_name, member_id])

func _on_steam_lobby_member_left(member_id: int):
	"""Called when a player leaves the Steam lobby"""
	print("Steam lobby member left: %d" % member_id)

# ============================================
# LAN/ENET SERVER
# ============================================

func create_server_steam(_lobby_id: int) -> bool:
	"""Legacy function - use host_steam_lobby instead"""
	return host_steam_lobby(1)

func create_server_lan() -> bool:
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)

	if result != OK:
		print("Failed to create LAN server: ", result)
		return false

	multiplayer.multiplayer_peer = peer
	is_server = true
	use_steam = false
	local_player_id = multiplayer.get_unique_id()

	register_player(local_player_id, get_local_player_info())

	server_started.emit()
	print("LAN server started on port %d" % DEFAULT_PORT)

	return true

func stop_server():
	# Leave Steam lobby if in one
	if use_steam and steam_manager:
		steam_manager.leave_lobby()

	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	is_server = false
	is_client = false
	use_steam = false
	players.clear()
	player_nodes.clear()
	players_loaded.clear()
	steam_p2p_peer = null

	server_stopped.emit()

# ============================================
# CLIENT
# ============================================

func join_steam_lobby(lobby_id: int) -> bool:
	"""Join a Steam lobby"""
	if not steam_manager or not steam_manager.is_initialized():
		print("Steam not available")
		return false

	steam_manager.join_lobby(lobby_id)
	# Connection setup happens in _on_steam_lobby_joined
	return true

func join_server_steam(lobby_id: int) -> bool:
	"""Legacy function - use join_steam_lobby instead"""
	return join_steam_lobby(lobby_id)

func join_server_lan(ip: String, port: int = DEFAULT_PORT) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_client(ip, port)

	if result != OK:
		print("Failed to connect to server: ", result)
		connection_failed.emit()
		return false

	multiplayer.multiplayer_peer = peer
	is_client = true
	use_steam = false
	current_server_ip = ip
	current_server_port = port

	return true

## Connect to the dedicated game server at 162.248.94.149
func join_dedicated_server() -> bool:
	print("Connecting to dedicated server at %s:%d" % [DEDICATED_SERVER_IP, DEDICATED_SERVER_PORT])
	return join_server_lan(DEDICATED_SERVER_IP, DEDICATED_SERVER_PORT)

## Connect to a specific server from the server browser
func join_server_by_address(ip: String, port: int = DEFAULT_PORT) -> bool:
	print("Connecting to server at %s:%d" % [ip, port])
	return join_server_lan(ip, port)

## Quick play - connect to the dedicated server
func quick_play() -> bool:
	return join_dedicated_server()

func disconnect_from_server():
	# Leave Steam lobby if in one
	if use_steam and steam_manager:
		steam_manager.leave_lobby()

	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	is_client = false
	is_server = false
	use_steam = false
	players.clear()
	player_nodes.clear()
	players_loaded.clear()
	steam_p2p_peer = null

	disconnected_from_server.emit()

# ============================================
# GAME START
# ============================================

func start_game():
	"""Host starts the game - all players load into the level"""
	if not is_server:
		return

	# Mark lobby as in-game
	if use_steam and steam_manager:
		steam_manager.set_lobby_data("status", "in_game")
		steam_manager.set_lobby_joinable(false)

	# Tell all clients to start
	game_starting.emit()
	_start_game_rpc.rpc()

	# Load game scene
	_load_game_scene()

@rpc("authority", "call_local", "reliable")
func _start_game_rpc():
	"""RPC to start game on all clients"""
	game_starting.emit()
	_load_game_scene()

func _load_game_scene():
	"""Load the game scene"""
	get_tree().change_scene_to_file("res://scenes/levels/arena_01.tscn")

func on_game_starting():
	"""Called when the game is starting from the lobby"""
	# Mark players as not loaded yet for the new scene
	players_loaded.clear()
	game_starting.emit()

@rpc("any_peer", "reliable")
func notify_player_loaded():
	"""Called by clients when they finish loading"""
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = local_player_id

	players_loaded[peer_id] = true

	# Check if all players loaded
	if is_server and players_loaded.size() == players.size():
		all_players_loaded.emit()
		_all_players_loaded_rpc.rpc()

@rpc("authority", "call_local", "reliable")
func _all_players_loaded_rpc():
	"""Notify all clients that everyone is loaded"""
	all_players_loaded.emit()

# ============================================
# PLAYER MANAGEMENT
# ============================================

func register_player(peer_id: int, player_info: Dictionary):
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)

	print("Player registered: %s (ID: %d)" % [player_info.name, peer_id])

@rpc("any_peer", "reliable")
func sync_player_info(player_info: Dictionary):
	var peer_id = multiplayer.get_remote_sender_id()
	register_player(peer_id, player_info)

	# Send our info back if we're server
	if is_server:
		receive_all_players.rpc_id(peer_id, players)

@rpc("authority", "reliable")
func receive_all_players(all_players: Dictionary):
	for peer_id in all_players:
		if peer_id != local_player_id and not players.has(peer_id):
			register_player(peer_id, all_players[peer_id])

func spawn_player(peer_id: int, _player_info: Dictionary):
	# Don't spawn if already exists
	if player_nodes.has(peer_id):
		return

	# Spawn player node
	var player_scene = preload("res://scenes/player/player_fps.tscn")
	var player = player_scene.instantiate()

	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)

	# Set spawn position
	var spawn_points = get_tree().get_nodes_in_group("player_spawn")
	if spawn_points.size() > 0:
		var spawn = spawn_points[randi() % spawn_points.size()]
		player.global_position = spawn.global_position

	var scene = get_tree().current_scene
	if not scene:
		player.queue_free()
		return
	scene.add_child(player)
	player_nodes[peer_id] = player

	print("Spawned player node for peer %d" % peer_id)

func spawn_all_players():
	"""Spawn player nodes for all connected players"""
	for peer_id in players:
		spawn_player(peer_id, players[peer_id])

func despawn_player(peer_id: int):
	if player_nodes.has(peer_id):
		player_nodes[peer_id].queue_free()
		player_nodes.erase(peer_id)

func despawn_all_players():
	for peer_id in player_nodes.keys():
		despawn_player(peer_id)

# ============================================
# GAME STATE SYNC
# ============================================

@rpc("authority", "reliable")
func sync_wave_state(wave: int, zombies_alive: int, is_intermission: bool):
	var wave_manager = get_node_or_null("/root/Main/WaveManager")
	if wave_manager:
		wave_manager.current_wave = wave
		wave_manager.zombies_alive = zombies_alive
		wave_manager.is_intermission = is_intermission

@rpc("authority", "call_local")
func spawn_zombie_networked(zombie_class_name: String, position: Vector3, zombie_id: int):
	var zombie_scene_path = "res://scenes/zombies/zombie_%s.tscn" % zombie_class_name
	if not ResourceLoader.exists(zombie_scene_path):
		zombie_scene_path = "res://scenes/zombies/zombie_shambler.tscn"

	var zombie_scene = load(zombie_scene_path)
	var zombie = zombie_scene.instantiate()

	zombie.name = "Zombie_%d" % zombie_id
	zombie.global_position = position

	var scene = get_tree().current_scene
	if not scene:
		zombie.queue_free()
		return
	scene.add_child(zombie)

@rpc("any_peer", "call_local")
func damage_zombie(zombie_path: NodePath, damage: float, _is_headshot: bool):
	var zombie = get_node_or_null(zombie_path)
	if zombie and zombie.has_method("take_damage"):
		zombie.take_damage(damage, Vector3.ZERO)

@rpc("any_peer", "call_local")
func player_shoot(_player_id: int, origin: Vector3, direction: Vector3, weapon_type: String = "rifle"):
	var vfx_manager = get_node_or_null("/root/VFXManager")
	if vfx_manager:
		if vfx_manager.has_method("spawn_muzzle_flash"):
			vfx_manager.spawn_muzzle_flash(origin, direction, weapon_type)
		if vfx_manager.has_method("spawn_tracer"):
			var end_point = origin + direction * 100.0
			vfx_manager.spawn_tracer(origin, end_point)

	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		if audio_manager.has_method("play_sound_3d"):
			audio_manager.play_sound_3d(weapon_type + "_shot", origin)
		elif audio_manager.has_method("play_sfx_3d"):
			audio_manager.play_sfx_3d("gunshot", origin)

@rpc("any_peer", "call_local")
func player_hit_effect(hit_position: Vector3, hit_normal: Vector3, surface_type: String = "default"):
	var vfx_manager = get_node_or_null("/root/VFXManager")
	if vfx_manager and vfx_manager.has_method("spawn_impact_effect"):
		vfx_manager.spawn_impact_effect(hit_position, hit_normal, surface_type)

	if surface_type == "flesh":
		var gore_system = get_node_or_null("/root/GoreSystem")
		if gore_system and gore_system.has_method("spawn_blood_splatter"):
			gore_system.spawn_blood_splatter(hit_position, hit_normal)

@rpc("any_peer", "call_local")
func player_reload(player_id: int, weapon_type: String):
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		if player_nodes.has(player_id):
			var player = player_nodes[player_id]
			if audio_manager.has_method("play_sound_3d"):
				audio_manager.play_sound_3d(weapon_type + "_reload", player.global_position)

@rpc("authority", "call_local")
func sync_player_health(player_id: int, health: float, max_health: float):
	if player_nodes.has(player_id):
		var player = player_nodes[player_id]
		if player.has_method("set_health"):
			player.set_health(health, max_health)
		elif "current_health" in player:
			player.current_health = health
			player.max_health = max_health

@rpc("authority", "call_local")
func on_player_died_rpc(player_id: int, _killer_id: int = -1):
	if player_nodes.has(player_id):
		var player = player_nodes[player_id]
		if player.has_method("die"):
			player.die()

		var gore_system = get_node_or_null("/root/GoreSystem")
		if gore_system and gore_system.has_method("spawn_death_effect"):
			gore_system.spawn_death_effect(player.global_position)

@rpc("any_peer", "reliable")
func player_use_item(_player_id: int, item_name: String, target_position: Vector3):
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_sound_3d"):
		audio_manager.play_sound_3d("item_use", target_position)

	var vfx_manager = get_node_or_null("/root/VFXManager")
	if vfx_manager and vfx_manager.has_method("spawn_item_effect"):
		vfx_manager.spawn_item_effect(item_name, target_position)

# ============================================
# CALLBACKS
# ============================================

func _on_peer_connected(peer_id: int):
	print("Peer connected: %d" % peer_id)

	if is_server:
		await get_tree().process_frame

		if players.size() > 0:
			receive_all_players.rpc_id(peer_id, players)

		var wave_manager = get_node_or_null("/root/Main/WaveManager")
		if wave_manager:
			var wave = wave_manager.current_wave if "current_wave" in wave_manager else 1
			var zombies = wave_manager.zombies_alive if "zombies_alive" in wave_manager else 0
			var intermission = wave_manager.is_intermission if "is_intermission" in wave_manager else false
			sync_wave_state.rpc_id(peer_id, wave, zombies, intermission)
	else:
		sync_player_info.rpc_id(1, get_local_player_info())

func _on_peer_disconnected(peer_id: int):
	print("Peer disconnected: %d" % peer_id)

	if players.has(peer_id):
		players.erase(peer_id)

	if players_loaded.has(peer_id):
		players_loaded.erase(peer_id)

	despawn_player(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server():
	print("Connected to server!")
	local_player_id = multiplayer.get_unique_id()

	sync_player_info.rpc_id(1, get_local_player_info())

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

	# Try to get info from AccountSystem
	var account_system = get_node_or_null("/root/AccountSystem")
	if account_system:
		if account_system.has_method("get_username"):
			info.name = account_system.get_username()
		if account_system.has_method("get_rank"):
			info.level = account_system.get_rank()

	return info

func get_player_info(peer_id: int) -> Dictionary:
	if players.has(peer_id):
		return players[peer_id]
	return {}

func get_player_count() -> int:
	return players.size()

func is_host() -> bool:
	return is_server

func is_using_steam() -> bool:
	return use_steam

func get_local_peer_id() -> int:
	return local_player_id

func set_player_ready(peer_id: int, is_ready: bool):
	if players.has(peer_id):
		players[peer_id].ready = is_ready

		if is_server:
			_sync_player_ready.rpc(peer_id, is_ready)

@rpc("authority", "call_local", "reliable")
func _sync_player_ready(peer_id: int, is_ready: bool):
	if players.has(peer_id):
		players[peer_id].ready = is_ready

func are_all_players_ready() -> bool:
	for peer_id in players:
		if not players[peer_id].ready:
			return false
	return true

func get_players() -> Dictionary:
	return players

# ============================================
# DEDICATED SERVER RPC HANDLERS (Client receives these)
# ============================================

@rpc("authority", "reliable")
func _send_server_info(info: Dictionary):
	"""Receive server info when connecting to dedicated server"""
	server_info = info
	current_wave = info.get("current_wave", 0)
	game_status = info.get("game_status", "waiting")

	# Process existing players
	var existing_players = info.get("players", [])
	for player_info in existing_players:
		var peer_id = player_info.get("peer_id", 0)
		if peer_id > 0 and peer_id != local_player_id:
			register_player(peer_id, player_info)

	server_info_received.emit(info)
	print("Received server info: %s" % info.get("server_name", "Unknown Server"))

@rpc("authority", "call_remote", "reliable")
func _notify_player_joined(peer_id: int, player_info: Dictionary):
	"""Receive notification that a player joined"""
	if peer_id != local_player_id:
		register_player(peer_id, player_info)

@rpc("authority", "call_remote", "reliable")
func _notify_player_left(peer_id: int):
	"""Receive notification that a player left"""
	if players.has(peer_id):
		players.erase(peer_id)
	if players_loaded.has(peer_id):
		players_loaded.erase(peer_id)
	despawn_player(peer_id)
	player_disconnected.emit(peer_id)

@rpc("authority", "call_remote", "reliable")
func _notify_all_players(event: String, data: Dictionary):
	"""Receive server-wide notification"""
	match event:
		"server_shutdown":
			print("Server shutting down: %s" % data.get("reason", ""))
			disconnect_from_server()
		_:
			print("Server event: %s - %s" % [event, data])

@rpc("authority", "call_remote", "reliable")
func _notify_game_starting():
	"""Receive notification that game is starting"""
	game_status = "starting"
	game_starting.emit()
	print("Game starting!")

@rpc("authority", "call_remote", "reliable")
func _notify_wave_start(wave_number: int):
	"""Receive wave start notification"""
	current_wave = wave_number
	wave_started.emit(wave_number)
	print("Wave %d started!" % wave_number)

	# Update wave manager if exists
	var wave_manager = get_node_or_null("/root/Main/WaveManager")
	if wave_manager and "current_wave" in wave_manager:
		wave_manager.current_wave = wave_number

@rpc("authority", "call_remote", "reliable")
func _notify_wave_complete(wave_number: int):
	"""Receive wave complete notification"""
	wave_completed.emit(wave_number)
	print("Wave %d complete!" % wave_number)

@rpc("authority", "call_remote", "reliable")
func _notify_game_end(victory: bool, wave_reached: int, stats: Array):
	"""Receive game end notification"""
	game_status = "ended"
	game_ended.emit(victory, wave_reached, stats)
	print("Game ended! Victory: %s, Wave reached: %d" % [victory, wave_reached])

@rpc("authority", "call_remote", "reliable")
func _notify_player_spawned(position: Vector3):
	"""Receive notification that local player was spawned"""
	player_spawned.emit(position)
	print("Player spawned at %s" % position)

@rpc("authority", "call_remote", "reliable")
func _notify_player_respawned(peer_id: int, position: Vector3):
	"""Receive notification that a player respawned"""
	player_respawned.emit(peer_id, position)

	# Spawn or update observed player
	if peer_id != local_player_id:
		if observed_players.has(peer_id) and is_instance_valid(observed_players[peer_id]):
			observed_players[peer_id].global_position = position
		else:
			_spawn_observed_player(peer_id, position)

@rpc("authority", "call_remote", "unreliable_ordered")
func broadcast_entity_states(states: Array):
	"""Receive entity states from server"""
	entity_states_received.emit(states)

	# Update observed players and zombies
	for state in states:
		var entity_id = state.get("entity_id", 0)
		var entity_type = state.get("type", "")
		var pos = _array_to_vec3(state.get("pos", [0, 0, 0]))
		var rot = _array_to_vec3(state.get("rot", [0, 0, 0]))

		if entity_type == "player" and entity_id != local_player_id:
			_update_observed_player(entity_id, pos, rot, state.get("data", {}))
		elif entity_type == "zombie":
			_update_zombie(entity_id, pos, rot, state.get("data", {}))

@rpc("authority", "call_remote", "reliable")
func broadcast_game_event(event_name: String, event_data: Dictionary):
	"""Receive game event from server"""
	match event_name:
		"zombie_spawned":
			_handle_zombie_spawn(event_data)
		"zombie_died":
			_handle_zombie_death(event_data)
		"item_spawned":
			_handle_item_spawn(event_data)
		"item_picked_up":
			_handle_item_pickup(event_data)
		_:
			print("Game event: %s" % event_name)

@rpc("authority", "call_remote", "reliable")
func _receive_player_ready_state(peer_id: int, is_ready: bool):
	"""Receive player ready state update from server"""
	if players.has(peer_id):
		players[peer_id].ready = is_ready

@rpc("authority", "call_remote", "reliable")
func _notify_player_damage(peer_id: int, damage: float, new_health: float):
	"""Receive player damage notification"""
	if peer_id == local_player_id:
		# Apply to local player
		var local_player = get_local_player()
		if local_player and local_player.has_method("apply_damage"):
			local_player.apply_damage(damage)
		elif local_player and "current_health" in local_player:
			local_player.current_health = new_health
	else:
		# Update observed player health
		if observed_players.has(peer_id) and is_instance_valid(observed_players[peer_id]):
			var obs = observed_players[peer_id]
			if "health" in obs:
				obs.health = new_health

@rpc("authority", "call_remote", "reliable")
func _notify_player_death(peer_id: int, killer_name: String):
	"""Receive player death notification"""
	player_died.emit(peer_id, killer_name)

	if peer_id == local_player_id:
		var local_player = get_local_player()
		if local_player and local_player.has_method("die"):
			local_player.die()
	else:
		if observed_players.has(peer_id) and is_instance_valid(observed_players[peer_id]):
			var obs = observed_players[peer_id]
			if obs.has_method("die"):
				obs.die()

@rpc("authority", "call_remote", "unreliable_ordered")
func _broadcast_shot(peer_id: int, origin: Vector3, direction: Vector3, weapon: String):
	"""Receive shot broadcast from server"""
	if peer_id == local_player_id:
		return  # Skip own shots

	# Spawn effects
	var vfx_manager = get_node_or_null("/root/VFXManager")
	if vfx_manager:
		if vfx_manager.has_method("spawn_muzzle_flash"):
			vfx_manager.spawn_muzzle_flash(origin, direction, weapon)
		if vfx_manager.has_method("spawn_tracer"):
			vfx_manager.spawn_tracer(origin, origin + direction * 100.0)

	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_sound_3d"):
		audio_manager.play_sound_3d(weapon + "_shot", origin)

@rpc("authority", "call_remote", "reliable")
func _broadcast_reload(peer_id: int, weapon: String):
	"""Receive reload broadcast from server"""
	if peer_id == local_player_id:
		return

	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and observed_players.has(peer_id):
		var obs = observed_players[peer_id]
		if is_instance_valid(obs) and audio_manager.has_method("play_sound_3d"):
			audio_manager.play_sound_3d(weapon + "_reload", obs.global_position)

@rpc("authority", "call_remote", "reliable")
func _notify_zombie_killed(zombie_id: int, killer_peer_id: int, drop_data: Dictionary):
	"""Receive zombie kill notification"""
	# Find and kill the zombie
	var zombies = get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if zombie.get_instance_id() == zombie_id:
			if zombie.has_method("die"):
				zombie.die()
			else:
				zombie.queue_free()
			break

	# Spawn drop if any
	if not drop_data.is_empty():
		_spawn_drop(drop_data)

	# Award points to killer (UI update)
	if killer_peer_id == local_player_id:
		var hud = get_node_or_null("/root/HUD")
		if hud and hud.has_method("show_points"):
			hud.show_points(10)

@rpc("authority", "call_local", "reliable")
func _broadcast_chat_message(peer_id: int, username: String, message: String):
	"""Receive chat message"""
	chat_message_received.emit(peer_id, username, message)

	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui and chat_ui.has_method("add_message"):
		chat_ui.add_message(username, message)

@rpc("authority", "reliable")
func _notify_kicked(reason: String):
	"""Receive kick notification"""
	print("Kicked from server: %s" % reason)
	disconnect_from_server()

# ============================================
# CLIENT TO SERVER RPC
# ============================================

func send_player_state(state: Dictionary):
	"""Send local player state to server"""
	if is_client and multiplayer.has_multiplayer_peer():
		receive_player_state.rpc_id(1, state)

@rpc("any_peer", "unreliable_ordered")
func receive_player_state(_state: Dictionary):
	# Server handles this
	pass

func send_player_action(action_type: String, action_data: Dictionary):
	"""Send player action to server"""
	if is_client and multiplayer.has_multiplayer_peer():
		player_action.rpc_id(1, action_type, action_data)

@rpc("any_peer", "reliable")
func player_action(_action_type: String, _action_data: Dictionary):
	# Server handles this
	pass

func send_chat_message(message: String):
	"""Send chat message to server"""
	if multiplayer.has_multiplayer_peer():
		_client_chat_message.rpc_id(1, message)

@rpc("any_peer", "reliable")
func _client_chat_message(message: String):
	# Server handles this - broadcasts to all
	var peer_id = multiplayer.get_remote_sender_id()
	var username = "Unknown"
	if players.has(peer_id):
		username = players[peer_id].get("name", "Player")

	_broadcast_chat_message.rpc(peer_id, username, message)

# ============================================
# HELPER FUNCTIONS
# ============================================

func _array_to_vec3(arr: Array) -> Vector3:
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(arr[0], arr[1], arr[2])

func get_local_player() -> Node:
	"""Get the local player node (public API)"""
	var players_group = get_tree().get_nodes_in_group("player")
	for player in players_group:
		if player is Node3D:
			var authority = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 1
			if authority == local_player_id:
				return player
	return null

func _spawn_observed_player(peer_id: int, position: Vector3):
	"""Spawn an observed player for a remote peer"""
	if observed_players.has(peer_id):
		return

	var observed_scene = load("res://scenes/player/observed_player.tscn")
	if not observed_scene:
		return

	var observed = observed_scene.instantiate()
	observed.name = "ObservedPlayer_%d" % peer_id

	if "peer_id" in observed:
		observed.peer_id = peer_id
	if "player_name" in observed and players.has(peer_id):
		observed.player_name = players[peer_id].get("name", "Player")

	observed.global_position = position

	var scene = get_tree().current_scene
	if scene:
		scene.add_child(observed)
		observed_players[peer_id] = observed

func _update_observed_player(peer_id: int, position: Vector3, rotation: Vector3, data: Dictionary):
	"""Update observed player position"""
	if not observed_players.has(peer_id):
		_spawn_observed_player(peer_id, position)
		return

	var obs = observed_players[peer_id]
	if not is_instance_valid(obs):
		observed_players.erase(peer_id)
		_spawn_observed_player(peer_id, position)
		return

	# Interpolate position
	if obs.has_method("receive_state"):
		obs.receive_state({
			"position": position,
			"rotation": rotation,
			"data": data
		})
	else:
		obs.global_position = position
		obs.rotation = rotation

		if "health" in obs and data.has("health"):
			obs.health = data.health

func _update_zombie(entity_id: int, position: Vector3, rotation: Vector3, _data: Dictionary):
	"""Update zombie position (for non-authoritative zombies)"""
	var zombies = get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if zombie.get_instance_id() == entity_id:
			zombie.global_position = position
			zombie.rotation = rotation
			break

func _handle_zombie_spawn(data: Dictionary):
	"""Handle zombie spawn event"""
	var zombie_type = data.get("zombie_type", "shambler")
	var position = _array_to_vec3(data.get("position", [0, 0, 0]))
	var zombie_id = data.get("zombie_id", 0)

	var scene_path = "res://scenes/zombies/zombie_%s.tscn" % zombie_type
	if not ResourceLoader.exists(scene_path):
		scene_path = "res://scenes/zombies/zombie_shambler.tscn"

	var zombie_scene = load(scene_path)
	if zombie_scene:
		var zombie = zombie_scene.instantiate()
		zombie.name = "Zombie_%d" % zombie_id
		zombie.global_position = position

		var scene = get_tree().current_scene
		if scene:
			scene.add_child(zombie)

func _handle_zombie_death(data: Dictionary):
	"""Handle zombie death event"""
	var zombie_id = data.get("zombie_id", 0)
	var zombies = get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if zombie.get_instance_id() == zombie_id:
			if zombie.has_method("die"):
				zombie.die()
			else:
				zombie.queue_free()
			break

func _handle_item_spawn(data: Dictionary):
	"""Handle item spawn event - spawn item on all clients"""
	var item_id = data.get("item_id", "")
	var position = data.get("position", Vector3.ZERO)
	var network_id = data.get("network_id", 0)

	if item_id.is_empty():
		return

	# Try survival system first for consumables
	var survival_system = get_node_or_null("/root/SurvivalSystem")
	if survival_system and survival_system.has_method("spawn_item_at"):
		var item = survival_system.spawn_item_at(item_id, position)
		if item and network_id > 0:
			item.set_meta("network_id", network_id)
		return

	# Try loot spawner for other items
	var loot_spawner = get_tree().get_first_node_in_group("loot_spawner")
	if loot_spawner and loot_spawner.has_method("spawn_loot_at"):
		var item = loot_spawner.spawn_loot_at(item_id, position)
		if item and network_id > 0:
			item.set_meta("network_id", network_id)

func _handle_item_pickup(data: Dictionary):
	"""Handle item pickup event - sync pickup to all clients"""
	var network_id = data.get("network_id", 0)
	var player_peer_id = data.get("player_id", 0)

	if network_id <= 0:
		return

	# Find the item by network_id
	var items = get_tree().get_nodes_in_group("pickups")
	for item in items:
		if item.has_meta("network_id") and item.get_meta("network_id") == network_id:
			# Remove item from world
			if item.has_method("on_picked_up"):
				item.on_picked_up()
			else:
				item.queue_free()
			break

	# Also check consumables group
	var consumables = get_tree().get_nodes_in_group("consumables")
	for item in consumables:
		if item.has_meta("network_id") and item.get_meta("network_id") == network_id:
			if item.has_method("on_picked_up"):
				item.on_picked_up()
			else:
				item.queue_free()
			break

func _spawn_drop(drop_data: Dictionary):
	"""Spawn a loot drop (from zombie death, etc.)"""
	var item_id = drop_data.get("item_id", "")
	var position = drop_data.get("position", Vector3.ZERO)
	var rarity = drop_data.get("rarity", "common")

	if item_id.is_empty():
		return

	# Generate network ID for sync
	var network_id = randi()

	# Spawn locally
	var spawn_data = {
		"item_id": item_id,
		"position": position,
		"network_id": network_id
	}
	_handle_item_spawn(spawn_data)

	# Broadcast to other clients if server
	if multiplayer.is_server():
		broadcast_game_event.rpc("item_spawned", spawn_data)
