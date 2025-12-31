extends Node

# Matchmaking system for join-in-progress gameplay
# Integrates with Steam lobbies for automatic matchmaking

@warning_ignore("unused_signal")
signal match_found(lobby_id: int)
@warning_ignore("unused_signal")
signal matchmaking_started
@warning_ignore("unused_signal")
signal matchmaking_stopped
@warning_ignore("unused_signal")
signal player_spawned(player: Node)

enum MatchState {
	WAITING_FOR_PLAYERS,
	IN_PROGRESS,
	GAME_OVER
}

var current_match_state: MatchState = MatchState.WAITING_FOR_PLAYERS
var is_searching: bool = false
var spawn_point_index: int = 0
var matchmaking_ticket_id: String = ""

@onready var steam_manager: Node = get_node_or_null("/root/SteamManager")
@onready var network_manager: Node = get_node_or_null("/root/NetworkManager")
var backend: Node = null
var websocket_hub: Node = null

func _ready():
	# Get backend references
	backend = get_node_or_null("/root/Backend")
	websocket_hub = get_node_or_null("/root/WebSocketHub")

	# Connect to network signals
	if network_manager:
		network_manager.player_connected.connect(_on_player_connected)
		network_manager.player_disconnected.connect(_on_player_disconnected)

	# Connect to Steam signals
	if steam_manager:
		steam_manager.lobby_created.connect(_on_lobby_created)
		steam_manager.lobby_joined.connect(_on_lobby_joined)
		steam_manager.lobby_list_received.connect(_on_lobby_list_received)

	# Connect to WebSocket matchmaking signals
	if websocket_hub:
		if websocket_hub.has_signal("matchmaking_update"):
			websocket_hub.matchmaking_update.connect(_on_backend_matchmaking_update)

func _exit_tree():
	# Disconnect signals to prevent memory leaks
	if network_manager:
		if network_manager.player_connected.is_connected(_on_player_connected):
			network_manager.player_connected.disconnect(_on_player_connected)
		if network_manager.player_disconnected.is_connected(_on_player_disconnected):
			network_manager.player_disconnected.disconnect(_on_player_disconnected)

	if steam_manager:
		if steam_manager.lobby_created.is_connected(_on_lobby_created):
			steam_manager.lobby_created.disconnect(_on_lobby_created)
		if steam_manager.lobby_joined.is_connected(_on_lobby_joined):
			steam_manager.lobby_joined.disconnect(_on_lobby_joined)
		if steam_manager.lobby_list_received.is_connected(_on_lobby_list_received):
			steam_manager.lobby_list_received.disconnect(_on_lobby_list_received)

# ============================================
# MATCHMAKING
# ============================================

func start_matchmaking():
	"""Start searching for available matches"""
	if is_searching:
		return

	is_searching = true
	matchmaking_started.emit()

	# Try backend matchmaking first if available
	if backend and backend.is_authenticated and websocket_hub:
		_start_backend_matchmaking()
		return

	# Fall back to Steam matchmaking
	if steam_manager:
		steam_manager.search_lobbies()

		# Wait a bit for results
		await get_tree().create_timer(2.0).timeout

		# If no lobbies found, create our own
		if steam_manager.current_lobby_id == 0:
			create_match()
	else:
		# No Steam, create LAN match
		create_match()

func _start_backend_matchmaking():
	"""Start matchmaking through backend API"""
	var preferences = {
		"gameMode": "survival",
		"region": "",  # Auto-detect
		"skillRange": 500
	}

	backend.join_matchmaking_queue(preferences, func(response):
		if response.success:
			matchmaking_ticket_id = response.get("ticketId", "")
			print("Backend matchmaking started: %s" % matchmaking_ticket_id)
		else:
			# Fallback to Steam or LAN
			if steam_manager:
				steam_manager.search_lobbies()
			else:
				create_match()
	)

func stop_matchmaking():
	"""Stop searching for matches"""
	is_searching = false

	# Cancel backend matchmaking if active
	if not matchmaking_ticket_id.is_empty() and backend:
		backend.leave_matchmaking_queue(func(_response):
			matchmaking_ticket_id = ""
		)

	matchmaking_stopped.emit()

func _on_backend_matchmaking_update(status: Dictionary):
	"""Handle matchmaking updates from backend"""
	var state = status.get("status", "")

	match state:
		"matched":
			# Found a match!
			var server_info = status.get("serverInfo", {})
			is_searching = false
			matchmaking_ticket_id = ""

			# Join the matched server
			if server_info:
				var server_ip = server_info.get("ipAddress", "")
				var server_port = server_info.get("port", 27015)
				if network_manager and not server_ip.is_empty():
					network_manager.join_server_lan(server_ip, server_port)

			match_found.emit(status.get("serverId", 0))
		"searching":
			# Still searching, update UI if needed
			var queue_size = status.get("queueSize", 0)
			var wait_time = status.get("estimatedWaitTime", 0)
			print("Matchmaking: %d in queue, ~%ds wait" % [queue_size, wait_time])
		"cancelled":
			is_searching = false
			matchmaking_ticket_id = ""
			matchmaking_stopped.emit()

func create_match():
	"""Create a new match (host)"""
	# Create network server first
	if network_manager:
		if steam_manager:
			# Will be handled in _on_lobby_created
			steam_manager.create_lobby(2)  # 2 = Public
		else:
			print("Steam not available, creating LAN match")
			network_manager.create_server_lan()
			_register_server_with_backend()
	else:
		print("No network manager available")

func _register_server_with_backend():
	"""Register our server with the backend server browser"""
	if not backend or not backend.is_authenticated:
		return

	var server_info = {
		"name": _get_server_name(),
		"port": 27015,
		"maxPlayers": 8,
		"gameMode": "survival",
		"currentMap": _get_current_map(),
		"hasPassword": false,
		"region": ""
	}

	backend.register_server(server_info, func(response):
		if response.success:
			var server_id = response.get("serverId", 0)
			print("Server registered with backend: %d" % server_id)

			# Start heartbeat
			_start_server_heartbeat(server_id)
	)

func _get_server_name() -> String:
	var username = "Survivor"
	if backend and backend.current_player:
		username = backend.current_player.get("username", "Survivor")
	return "%s's Game" % username

func _get_current_map() -> String:
	var scene = get_tree().current_scene
	if scene:
		var scene_name = scene.scene_file_path.get_file().get_basename()
		return scene_name
	return "warehouse"

var _heartbeat_timer: Timer = null
var _registered_server_id: int = 0

func _start_server_heartbeat(server_id: int):
	_registered_server_id = server_id

	if _heartbeat_timer:
		_heartbeat_timer.queue_free()

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = 30.0  # Every 30 seconds
	_heartbeat_timer.autostart = true
	_heartbeat_timer.timeout.connect(_send_server_heartbeat)
	add_child(_heartbeat_timer)

func _send_server_heartbeat():
	if not backend or _registered_server_id == 0:
		return

	var player_count = 0
	if network_manager and "players" in network_manager:
		player_count = network_manager.players.size()

	var status = {
		"currentPlayers": player_count,
		"currentWave": _get_current_wave(),
		"matchState": MatchState.keys()[current_match_state]
	}

	backend.server_heartbeat(_registered_server_id, status, func(_response):
		pass  # Heartbeat sent
	)

func _get_current_wave() -> int:
	var wave_manager = get_node_or_null("/root/WaveManager")
	if wave_manager and "current_wave" in wave_manager:
		return wave_manager.current_wave
	return 1

func join_match(lobby_id: int):
	"""Join an existing match"""
	if not steam_manager:
		return

	steam_manager.join_lobby(lobby_id)

func quick_match():
	"""Find and join any available match, or create new one"""
	start_matchmaking()

# ============================================
# LOBBY CALLBACKS
# ============================================

func _on_lobby_created(lobby_id: int):
	"""Called when we successfully create a lobby"""
	if not steam_manager:
		return

	# Set lobby metadata
	steam_manager.set_lobby_data("game_mode", "survival")
	steam_manager.set_lobby_data("version", "1.0")
	steam_manager.set_lobby_data("match_state", str(current_match_state))
	steam_manager.set_lobby_joinable(true)  # Allow join-in-progress

	# Start network server
	if network_manager:
		network_manager.create_server_steam(lobby_id)

	current_match_state = MatchState.WAITING_FOR_PLAYERS

	print("Match created! Lobby ID: ", lobby_id)

func _on_lobby_joined(lobby_id: int):
	"""Called when we join a lobby"""
	if not steam_manager:
		return

	# Get match state
	var state_str = steam_manager.get_lobby_data("match_state")
	if state_str and state_str.is_valid_int():
		var state_int = int(state_str)
		if state_int >= 0 and state_int < MatchState.size():
			current_match_state = state_int as MatchState

	# Stop matchmaking since we found a lobby
	is_searching = false

	# Connect to host network session
	if network_manager:
		# Get lobby owner's Steam ID to connect
		var steam = Engine.get_singleton("Steam")
		if steam:
			var _owner_steam_id = steam.getLobbyOwner(lobby_id)

			# Join the network game via Steam P2P or fallback to LAN
			if steam_manager.is_initialized():
				var result = network_manager.join_server_steam(lobby_id)
				if not result:
					# Steam P2P failed, try LAN fallback
					print("Steam P2P join failed, attempting LAN fallback")
					# Get host IP from lobby data if available
					var host_ip = steam_manager.get_lobby_data("host_ip")
					if host_ip and not host_ip.is_empty():
						network_manager.join_server_lan(host_ip)
					else:
						network_manager.join_server_lan("127.0.0.1")

	match_found.emit(lobby_id)
	var state_name = MatchState.keys()[current_match_state] if current_match_state < MatchState.size() else "UNKNOWN"
	print("Joined match! Lobby: %d, State: %s" % [lobby_id, state_name])

func _on_lobby_list_received(lobbies: Array):
	"""Called when lobby search completes"""
	if not is_searching:
		return

	if lobbies.size() > 0:
		# Join first available lobby
		var lobby_id = lobbies[0]
		join_match(lobby_id)
	else:
		# No lobbies found, create new match
		create_match()

# ============================================
# PLAYER SPAWNING
# ============================================

func _on_player_connected(peer_id: int, player_info: Dictionary):
	"""Spawn player when they connect"""
	# Wait for scene to be ready
	await get_tree().create_timer(0.5).timeout

	spawn_player(peer_id, player_info)

func _on_player_disconnected(peer_id: int):
	"""Handle player disconnect"""
	print("Player disconnected: ", peer_id)

func spawn_player(peer_id: int, _player_info: Dictionary):
	"""Spawn a player at the sigil or a spawn point"""
	var spawn_position = _get_spawn_position()

	# Create player instance
	var player_scene = preload("res://scenes/player/player_fps.tscn")
	var player = player_scene.instantiate()

	# Position at spawn
	player.global_position = spawn_position
	player.name = "Player_%d" % peer_id

	# Add to scene
	var root = get_tree().root.get_child(0)
	if root:
		root.add_child(player)

	player_spawned.emit(player)

	# Update network manager
	if network_manager:
		network_manager.player_nodes[peer_id] = player

	print("Spawned player %d at %s" % [peer_id, spawn_position])

func _get_spawn_position() -> Vector3:
	"""Get spawn position (near sigil or at spawn points)"""
	# Try to find sigil
	var sigils = get_tree().get_nodes_in_group("sigil")
	if sigils.size() > 0:
		# Spawn near sigil in a circle pattern
		var sigil = sigils[0]
		var angle = spawn_point_index * (TAU / 4.0)  # 4 spawn points around sigil
		var offset = Vector3(cos(angle) * 3.0, 0, sin(angle) * 3.0)
		spawn_point_index = (spawn_point_index + 1) % 4
		return sigil.global_position + offset

	# Fallback to spawn markers
	var spawn_points = get_tree().get_nodes_in_group("spawn_points")
	if spawn_points.size() > 0:
		var spawn = spawn_points[spawn_point_index % spawn_points.size()]
		spawn_point_index = (spawn_point_index + 1) % spawn_points.size()
		return spawn.global_position

	# Default spawn
	return Vector3(0, 1, 0)

# ============================================
# MATCH STATE MANAGEMENT
# ============================================

func set_match_state(new_state: MatchState):
	"""Update match state"""
	current_match_state = new_state

	# Update lobby metadata
	if steam_manager and steam_manager.current_lobby_id != 0:
		steam_manager.set_lobby_data("match_state", str(new_state))

	# Handle state transitions
	match new_state:
		MatchState.WAITING_FOR_PLAYERS:
			# Allow joins
			if steam_manager:
				steam_manager.set_lobby_joinable(true)
		MatchState.IN_PROGRESS:
			# Still allow join-in-progress
			if steam_manager:
				steam_manager.set_lobby_joinable(true)
		MatchState.GAME_OVER:
			# Prevent new joins
			if steam_manager:
				steam_manager.set_lobby_joinable(false)

func is_initialized() -> bool:
	return steam_manager != null and network_manager != null

func get_current_state() -> MatchState:
	return current_match_state
