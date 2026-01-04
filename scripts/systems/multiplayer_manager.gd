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

	if matchmaking_system:
		matchmaking_system.matchmaking_started.connect(_on_matchmaking_started)
		matchmaking_system.matchmaking_stopped.connect(_on_matchmaking_stopped)
		matchmaking_system.match_found.connect(_on_match_found)
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
		# Try alternate path
		observed_player_scene = load("res://scenes/player/player_observed.tscn")

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
				observed_players[peer_id].die()
		"player_respawned":
			var peer_id = data.get("peer_id", 0)
			if observed_players.has(peer_id):
				observed_players[peer_id].respawn()

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

func is_connected() -> bool:
	return connection_state in [ConnectionState.CONNECTED, ConnectionState.IN_LOBBY, ConnectionState.IN_GAME]

func is_in_game() -> bool:
	return connection_state == ConnectionState.IN_GAME

func is_in_lobby() -> bool:
	return connection_state == ConnectionState.IN_LOBBY

func can_start_game() -> bool:
	return is_host and connection_state == ConnectionState.IN_LOBBY and are_all_players_ready()
