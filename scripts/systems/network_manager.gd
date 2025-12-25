extends Node

# Network manager for multiplayer using Steam P2P networking
# Falls back to ENet for LAN play when Steam is unavailable

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_started
signal server_stopped
signal connected_to_server
signal connection_failed
signal disconnected_from_server
signal game_starting
signal all_players_loaded

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

var is_server: bool = false
var is_client: bool = false
var local_player_id: int = 1
var use_steam: bool = false

var players: Dictionary = {}  # peer_id -> player_info
var player_nodes: Dictionary = {}  # peer_id -> Player node
var players_loaded: Dictionary = {}  # peer_id -> bool

var steam_manager: Node = null
var steam_p2p_peer: RefCounted = null

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
	steam_p2p_peer = SteamP2PPeerClass.new()

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
	steam_p2p_peer = SteamP2PPeerClass.new()

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

func join_server_lan(ip: String) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_client(ip, DEFAULT_PORT)

	if result != OK:
		print("Failed to connect to server: ", result)
		connection_failed.emit()
		return false

	multiplayer.multiplayer_peer = peer
	is_client = true
	use_steam = false

	return true

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
func player_died(player_id: int, _killer_id: int = -1):
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
