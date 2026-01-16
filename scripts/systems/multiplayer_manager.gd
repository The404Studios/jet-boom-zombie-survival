extends Node
class_name MultiplayerManager

## Comprehensive multiplayer manager that coordinates networking, lobbies, and player synchronization
## Supports both Steam P2P and dedicated server (162.248.94.149) connections

signal connection_state_changed(state: ConnectionState)
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal game_session_started
signal game_session_ended
signal server_list_updated(servers: Array)
signal matchmaking_progress(status: String, time_elapsed: float)
signal error_occurred(error_code: int, message: String)

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	IN_LOBBY,
	IN_GAME,
	RECONNECTING
}

enum ConnectionType {
	NONE,
	STEAM_P2P,
	DEDICATED_SERVER,
	LAN,
	MATCHMAKING
}

# Server configuration
const DEDICATED_SERVER_IP: String = "162.248.94.149"
const DEDICATED_SERVER_PORT: int = 7777
const BACKEND_API_URL: String = "http://162.248.94.149:5000"

# State
var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var connection_type: ConnectionType = ConnectionType.NONE
var current_server_id: int = -1
var is_host: bool = false

# References
var network_manager: Node = null
var steam_manager: Node = null
var backend_client: Node = null
var matchmaking_system: Node = null

# Player tracking
var local_player_id: int = 0
var players: Dictionary = {}  # peer_id -> PlayerData
var observed_players: Dictionary = {}  # peer_id -> ObservedPlayer node

# Reconnection
var reconnect_attempts: int = 0
var max_reconnect_attempts: int = 3
var reconnect_delay: float = 2.0
var last_server_info: Dictionary = {}

# Network stats
var average_ping: float = 0.0
var packet_loss: float = 0.0

class PlayerData:
	var peer_id: int = 0
	var username: String = ""
	var steam_id: int = 0
	var level: int = 1
	var is_ready: bool = false
	var is_host: bool = false
	var team: int = 0
	var character_class: String = ""
	var ping: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"peer_id": peer_id,
			"username": username,
			"steam_id": steam_id,
			"level": level,
			"is_ready": is_ready,
			"is_host": is_host,
			"team": team,
			"character_class": character_class,
			"ping": ping
		}

	static func from_dict(data: Dictionary) -> PlayerData:
		var player = PlayerData.new()
		player.peer_id = data.get("peer_id", 0)
		player.username = data.get("username", data.get("name", "Player"))
		player.steam_id = data.get("steam_id", 0)
		player.level = data.get("level", 1)
		player.is_ready = data.get("is_ready", data.get("ready", false))
		player.is_host = data.get("is_host", false)
		player.team = data.get("team", 0)
		player.character_class = data.get("character_class", "")
		player.ping = data.get("ping", 0.0)
		return player

func _ready():
	# Get references to other managers
	network_manager = get_node_or_null("/root/NetworkManager")
	steam_manager = get_node_or_null("/root/SteamManager")
	backend_client = get_node_or_null("/root/BackendClient")
	matchmaking_system = get_node_or_null("/root/MatchmakingSystem")

	# Connect signals
	_connect_signals()

	print("MultiplayerManager: Initialized")
	print("  Dedicated Server: %s:%d" % [DEDICATED_SERVER_IP, DEDICATED_SERVER_PORT])
	print("  Backend API: %s" % BACKEND_API_URL)

func _connect_signals():
	if network_manager:
		network_manager.player_connected.connect(_on_player_connected)
		network_manager.player_disconnected.connect(_on_player_disconnected)
		network_manager.connected_to_server.connect(_on_connected_to_server)
		network_manager.connection_failed.connect(_on_connection_failed)
		network_manager.disconnected_from_server.connect(_on_disconnected_from_server)
		network_manager.game_starting.connect(_on_game_starting)
		network_manager.all_players_loaded.connect(_on_all_players_loaded)

		# Connect new dedicated server signals
		if network_manager.has_signal("server_info_received"):
			network_manager.server_info_received.connect(_on_server_info_received)
		if network_manager.has_signal("wave_started"):
			network_manager.wave_started.connect(_on_wave_started)
		if network_manager.has_signal("wave_completed"):
			network_manager.wave_completed.connect(_on_wave_completed)
		if network_manager.has_signal("game_ended"):
			network_manager.game_ended.connect(_on_game_ended)
		if network_manager.has_signal("entity_states_received"):
			network_manager.entity_states_received.connect(_on_entity_states_received)
		if network_manager.has_signal("player_spawned"):
			network_manager.player_spawned.connect(_on_player_spawned)
		if network_manager.has_signal("player_died"):
			network_manager.player_died.connect(_on_player_died)
		if network_manager.has_signal("player_respawned"):
			network_manager.player_respawned.connect(_on_player_respawned)

	if matchmaking_system:
		if matchmaking_system.has_signal("matchmaking_started"):
			matchmaking_system.matchmaking_started.connect(_on_matchmaking_started)
		if matchmaking_system.has_signal("matchmaking_stopped"):
			matchmaking_system.matchmaking_stopped.connect(_on_matchmaking_stopped)
		if matchmaking_system.has_signal("match_found"):
			matchmaking_system.match_found.connect(_on_match_found)
		if matchmaking_system.has_signal("matchmaking_failed"):
			matchmaking_system.matchmaking_failed.connect(_on_matchmaking_failed)

# ============================================
# CONNECTION METHODS
# ============================================

## Connect to the dedicated server (quick play)
func connect_to_dedicated_server() -> bool:
	if connection_state != ConnectionState.DISCONNECTED:
		disconnect_from_server()

	_set_connection_state(ConnectionState.CONNECTING)
	connection_type = ConnectionType.DEDICATED_SERVER

	print("Connecting to dedicated server at %s:%d..." % [DEDICATED_SERVER_IP, DEDICATED_SERVER_PORT])

	if network_manager:
		return network_manager.join_dedicated_server()

	return false

## Quick play - find or create a game
func quick_play() -> bool:
	# Try Steam matchmaking first if available
	if steam_manager and steam_manager.is_initialized():
		return start_matchmaking()

	# Fall back to dedicated server
	return connect_to_dedicated_server()

## Connect to a specific server by address
func connect_to_server(ip: String, port: int = DEDICATED_SERVER_PORT) -> bool:
	if connection_state != ConnectionState.DISCONNECTED:
		disconnect_from_server()

	_set_connection_state(ConnectionState.CONNECTING)
	connection_type = ConnectionType.LAN if ip.begins_with("192.168.") or ip.begins_with("10.") else ConnectionType.DEDICATED_SERVER

	last_server_info = {"ip": ip, "port": port}

	print("Connecting to server at %s:%d..." % [ip, port])

	if network_manager:
		return network_manager.join_server_by_address(ip, port)

	return false

## Host a game (Steam P2P or LAN)
func host_game(use_steam_lobby: bool = true, lobby_type: int = 1) -> bool:
	if connection_state != ConnectionState.DISCONNECTED:
		disconnect_from_server()

	is_host = true

	if use_steam_lobby and steam_manager and steam_manager.is_initialized():
		_set_connection_state(ConnectionState.CONNECTING)
		connection_type = ConnectionType.STEAM_P2P
		return network_manager.host_steam_lobby(lobby_type) if network_manager else false
	else:
		_set_connection_state(ConnectionState.CONNECTING)
		connection_type = ConnectionType.LAN
		if network_manager and network_manager.create_server_lan():
			_set_connection_state(ConnectionState.IN_LOBBY)
			return true

	return false

## Join a Steam lobby
func join_steam_lobby(lobby_id: int) -> bool:
	if connection_state != ConnectionState.DISCONNECTED:
		disconnect_from_server()

	_set_connection_state(ConnectionState.CONNECTING)
	connection_type = ConnectionType.STEAM_P2P

	if network_manager:
		return network_manager.join_steam_lobby(lobby_id)

	return false

## Start matchmaking
func start_matchmaking() -> bool:
	if matchmaking_system:
		_set_connection_state(ConnectionState.CONNECTING)
		connection_type = ConnectionType.MATCHMAKING
		matchmaking_system.start_matchmaking()
		return true
	return false

## Stop matchmaking
func stop_matchmaking():
	if matchmaking_system:
		matchmaking_system.stop_matchmaking()
	_set_connection_state(ConnectionState.DISCONNECTED)
	connection_type = ConnectionType.NONE

## Disconnect from current server
func disconnect_from_server():
	if network_manager:
		network_manager.disconnect_from_server()

	_cleanup()
	_set_connection_state(ConnectionState.DISCONNECTED)
	connection_type = ConnectionType.NONE

# ============================================
# LOBBY METHODS
# ============================================

## Set local player as ready
func set_ready(ready: bool):
	if network_manager and local_player_id > 0:
		network_manager.set_player_ready(local_player_id, ready)

		if players.has(local_player_id):
			players[local_player_id].is_ready = ready

## Start the game (host only)
func start_game() -> bool:
	if not is_host:
		return false

	if network_manager:
		network_manager.start_game()
		return true

	return false

## Check if all players are ready
func are_all_players_ready() -> bool:
	for peer_id in players:
		if not players[peer_id].is_ready:
			return false
	return true

## Get player count
func get_player_count() -> int:
	return players.size()

## Get all players
func get_players() -> Dictionary:
	return players

## Get local player info
func get_local_player() -> PlayerData:
	if players.has(local_player_id):
		return players[local_player_id]
	return null

# ============================================
# SERVER BROWSER
# ============================================

## Request server list from backend
func refresh_server_list():
	if backend_client:
		backend_client.get_servers({}, func(response):
			if response.success:
				var servers = response.get("data", [])
				server_list_updated.emit(servers)
			else:
				error_occurred.emit(1, "Failed to get server list")
		)

## Get server details
func get_server_details(server_id: int, callback: Callable):
	if backend_client:
		backend_client.get_server(server_id, callback)

# ============================================
# OBSERVED PLAYERS (REMOTE PLAYER VISUALIZATION)
# ============================================

## Spawn an observed player for a remote peer
func spawn_observed_player(peer_id: int, player_info: Dictionary) -> Node:
	if observed_players.has(peer_id):
		return observed_players[peer_id]

	var observed_player_scene = load("res://scenes/player/observed_player.tscn")
	if not observed_player_scene:
		push_warning("Could not load observed player scene")
		return null

	var observed_player = observed_player_scene.instantiate()
	observed_player.name = "ObservedPlayer_%d" % peer_id
	observed_player.peer_id = peer_id
	observed_player.player_name = player_info.get("username", player_info.get("name", "Player"))

	var scene = get_tree().current_scene
	if scene:
		scene.add_child(observed_player)
		observed_players[peer_id] = observed_player

		print("Spawned observed player for peer %d" % peer_id)
		return observed_player

	return null

## Remove an observed player
func remove_observed_player(peer_id: int):
	if observed_players.has(peer_id):
		var observed = observed_players[peer_id]
		if is_instance_valid(observed):
			observed.queue_free()
		observed_players.erase(peer_id)

## Update observed player state
func update_observed_player_state(peer_id: int, state: Dictionary):
	if observed_players.has(peer_id):
		var observed = observed_players[peer_id]
		if is_instance_valid(observed) and observed.has_method("receive_state"):
			observed.receive_state(state)

# ============================================
# NETWORK STATE SYNC
# ============================================

## Send local player state to server/peers
func send_player_state(state: Dictionary):
	if not network_manager or connection_state != ConnectionState.IN_GAME:
		return

	_sync_player_state.rpc(state)

@rpc("any_peer", "unreliable")
func _sync_player_state(state: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = local_player_id

	update_observed_player_state(sender_id, state)

## Broadcast event to all players
func broadcast_event(event_name: String, data: Dictionary):
	if not network_manager:
		return

	_receive_event.rpc(event_name, data)

@rpc("any_peer", "reliable")
func _receive_event(event_name: String, data: Dictionary):
	# Handle events - can be overridden or connected via signals
	match event_name:
		"player_died":
			var peer_id = data.get("peer_id", 0)
			if observed_players.has(peer_id):
				var obs = observed_players[peer_id]
				if obs.has_method("die"):
					obs.die()
		"player_respawned":
			var peer_id = data.get("peer_id", 0)
			if observed_players.has(peer_id):
				var obs = observed_players[peer_id]
				if obs.has_method("respawn"):
					obs.respawn()

# ============================================
# CALLBACKS
# ============================================

func _on_player_connected(peer_id: int, player_info: Dictionary):
	var player_data = PlayerData.from_dict(player_info)
	player_data.peer_id = peer_id
	players[peer_id] = player_data

	player_joined.emit(peer_id, player_data.to_dict())

	# Spawn observed player if in game
	if connection_state == ConnectionState.IN_GAME:
		spawn_observed_player(peer_id, player_data.to_dict())

	print("Player connected: %s (peer %d)" % [player_data.username, peer_id])

func _on_player_disconnected(peer_id: int):
	if players.has(peer_id):
		players.erase(peer_id)

	remove_observed_player(peer_id)
	player_left.emit(peer_id)

	print("Player disconnected: peer %d" % peer_id)

func _on_connected_to_server():
	local_player_id = multiplayer.get_unique_id()
	reconnect_attempts = 0

	_set_connection_state(ConnectionState.IN_LOBBY)

	print("Connected to server! Local peer ID: %d" % local_player_id)

func _on_connection_failed():
	print("Connection failed!")

	# Try to reconnect if we have server info
	if reconnect_attempts < max_reconnect_attempts and not last_server_info.is_empty():
		reconnect_attempts += 1
		_set_connection_state(ConnectionState.RECONNECTING)

		await get_tree().create_timer(reconnect_delay * reconnect_attempts).timeout

		if last_server_info.has("ip"):
			connect_to_server(last_server_info.ip, last_server_info.get("port", DEDICATED_SERVER_PORT))
	else:
		_set_connection_state(ConnectionState.DISCONNECTED)
		error_occurred.emit(2, "Connection failed after %d attempts" % reconnect_attempts)

func _on_disconnected_from_server():
	print("Disconnected from server")

	var previous_state = connection_state
	_cleanup()
	_set_connection_state(ConnectionState.DISCONNECTED)

	# Try to reconnect if we were in a game
	if previous_state == ConnectionState.IN_GAME and reconnect_attempts < max_reconnect_attempts:
		reconnect_attempts += 1
		_set_connection_state(ConnectionState.RECONNECTING)

		await get_tree().create_timer(reconnect_delay).timeout

		if last_server_info.has("ip"):
			connect_to_server(last_server_info.ip, last_server_info.get("port", DEDICATED_SERVER_PORT))

func _on_game_starting():
	_set_connection_state(ConnectionState.IN_GAME)
	game_session_started.emit()

	# Spawn observed players for all remote players
	for peer_id in players:
		if peer_id != local_player_id:
			spawn_observed_player(peer_id, players[peer_id].to_dict())

func _on_all_players_loaded():
	print("All players loaded!")

func _on_matchmaking_started():
	matchmaking_progress.emit("Searching for match...", 0.0)

func _on_matchmaking_stopped():
	if connection_state == ConnectionState.CONNECTING:
		_set_connection_state(ConnectionState.DISCONNECTED)

func _on_match_found(lobby_id: int):
	matchmaking_progress.emit("Match found!", 0.0)
	_set_connection_state(ConnectionState.IN_LOBBY)

func _on_matchmaking_failed(reason: String):
	error_occurred.emit(3, "Matchmaking failed: " + reason)
	_set_connection_state(ConnectionState.DISCONNECTED)

# ============================================
# HELPERS
# ============================================

func _set_connection_state(new_state: ConnectionState):
	if connection_state != new_state:
		connection_state = new_state
		connection_state_changed.emit(new_state)

func _cleanup():
	# Remove all observed players
	for peer_id in observed_players.keys():
		remove_observed_player(peer_id)

	players.clear()
	is_host = false
	current_server_id = -1

func get_connection_state_name() -> String:
	match connection_state:
		ConnectionState.DISCONNECTED: return "Disconnected"
		ConnectionState.CONNECTING: return "Connecting"
		ConnectionState.CONNECTED: return "Connected"
		ConnectionState.IN_LOBBY: return "In Lobby"
		ConnectionState.IN_GAME: return "In Game"
		ConnectionState.RECONNECTING: return "Reconnecting"
	return "Unknown"

func get_connection_type_name() -> String:
	match connection_type:
		ConnectionType.NONE: return "None"
		ConnectionType.STEAM_P2P: return "Steam P2P"
		ConnectionType.DEDICATED_SERVER: return "Dedicated Server"
		ConnectionType.LAN: return "LAN"
		ConnectionType.MATCHMAKING: return "Matchmaking"
	return "Unknown"

func is_network_connected() -> bool:
	return connection_state in [ConnectionState.CONNECTED, ConnectionState.IN_LOBBY, ConnectionState.IN_GAME]

func is_in_game() -> bool:
	return connection_state == ConnectionState.IN_GAME

func is_in_lobby() -> bool:
	return connection_state == ConnectionState.IN_LOBBY

func can_start_game() -> bool:
	return is_host and connection_state == ConnectionState.IN_LOBBY and are_all_players_ready()

# ============================================
# DEDICATED SERVER SIGNAL HANDLERS
# ============================================

func _on_server_info_received(info: Dictionary):
	"""Handle server info received from dedicated server"""
	print("Received server info from dedicated server")
	print("  Server: %s" % info.get("server_name", "Unknown"))
	print("  Map: %s" % info.get("map_name", "Unknown"))
	print("  Status: %s" % str(info.get("game_status", "unknown")))

	# Update existing players from server info
	var existing_players = info.get("players", [])
	for player_info in existing_players:
		var peer_id = player_info.get("peer_id", 0)
		if peer_id > 0 and peer_id != local_player_id:
			var player_data = PlayerData.from_dict(player_info)
			player_data.peer_id = peer_id
			players[peer_id] = player_data
			player_joined.emit(peer_id, player_data.to_dict())

func _on_wave_started(wave_number: int):
	"""Handle wave start notification"""
	print("Wave %d starting!" % wave_number)

func _on_wave_completed(wave_number: int):
	"""Handle wave completion notification"""
	print("Wave %d completed!" % wave_number)

func _on_game_ended(victory: bool, wave_reached: int, _stats: Array):
	"""Handle game end notification"""
	_set_connection_state(ConnectionState.IN_LOBBY)
	game_session_ended.emit()
	print("Game ended! Victory: %s, Waves: %d" % [victory, wave_reached])

func _on_entity_states_received(states: Array):
	"""Handle entity state updates from server"""
	# Forward to observed players for interpolation
	for state in states:
		var entity_id = state.get("entity_id", 0)
		var entity_type = state.get("type", "")

		if entity_type == "player" and entity_id != local_player_id:
			update_observed_player_state(entity_id, state)

func _on_player_spawned(position: Vector3):
	"""Handle local player spawn notification"""
	print("Local player spawned at %s" % position)

	# Update local player if exists
	if network_manager:
		var local_player = network_manager._get_local_player()
		if local_player:
			local_player.global_position = position

func _on_player_died(peer_id: int, killer_name: String):
	"""Handle player death notification"""
	print("Player %d killed by %s" % [peer_id, killer_name])

	if peer_id == local_player_id:
		# Local player died - show death screen
		pass
	else:
		# Remote player died - play death animation on observed player
		if observed_players.has(peer_id) and is_instance_valid(observed_players[peer_id]):
			var obs = observed_players[peer_id]
			if obs.has_method("die"):
				obs.die()

func _on_player_respawned(peer_id: int, position: Vector3):
	"""Handle player respawn notification"""
	print("Player %d respawned at %s" % [peer_id, position])

	if peer_id == local_player_id:
		# Local player respawned
		if network_manager:
			var local_player = network_manager._get_local_player()
			if local_player:
				local_player.global_position = position
	else:
		# Remote player respawned
		if observed_players.has(peer_id) and is_instance_valid(observed_players[peer_id]):
			var obs = observed_players[peer_id]
			obs.global_position = position
			if obs.has_method("respawn"):
				obs.respawn()
