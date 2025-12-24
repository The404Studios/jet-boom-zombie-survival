extends Node

# Matchmaking system for join-in-progress gameplay
# Integrates with Steam lobbies for automatic matchmaking

signal match_found(lobby_id: int)
signal matchmaking_started
signal matchmaking_stopped
signal player_spawned(player: Node)

enum MatchState {
	WAITING_FOR_PLAYERS,
	IN_PROGRESS,
	GAME_OVER
}

var current_match_state: MatchState = MatchState.WAITING_FOR_PLAYERS
var is_searching: bool = false
var spawn_point_index: int = 0

@onready var steam_manager: Node = get_node("/root/SteamManager") if has_node("/root/SteamManager") else null
@onready var network_manager: Node = get_node("/root/NetworkManager") if has_node("/root/NetworkManager") else null

func _ready():
	# Connect to network signals
	if network_manager:
		network_manager.player_connected.connect(_on_player_connected)
		network_manager.player_disconnected.connect(_on_player_disconnected)

	# Connect to Steam signals
	if steam_manager:
		steam_manager.lobby_created.connect(_on_lobby_created)
		steam_manager.lobby_joined.connect(_on_lobby_joined)
		steam_manager.lobby_list_received.connect(_on_lobby_list_received)

# ============================================
# MATCHMAKING
# ============================================

func start_matchmaking():
	"""Start searching for available matches"""
	if not steam_manager or is_searching:
		return

	is_searching = true
	matchmaking_started.emit()

	# Search for existing lobbies
	steam_manager.search_lobbies()

	# Wait a bit for results
	await get_tree().create_timer(2.0).timeout

	# If no lobbies found, create our own
	if steam_manager.current_lobby_id == 0:
		create_match()

func stop_matchmaking():
	"""Stop searching for matches"""
	is_searching = false
	matchmaking_stopped.emit()

func create_match():
	"""Create a new match (host)"""
	if not steam_manager:
		print("Steam not available, creating LAN match")
		if network_manager:
			network_manager.create_server_lan()
		return

	# Create public lobby that allows join-in-progress
	steam_manager.create_lobby(2)  # 2 = Public

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
		current_match_state = int(state_str) as MatchState

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
	print("Joined match! Lobby: %d, State: %s" % [lobby_id, MatchState.keys()[current_match_state]])

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

func spawn_player(peer_id: int, player_info: Dictionary):
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
