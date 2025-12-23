extends Node
class_name MatchmakingSystem

signal matchmaking_started
signal matchmaking_stopped
signal match_found(lobby_id: int)
signal matchmaking_failed(reason: String)

@export var steam_manager: Node
@export var network_manager: Node

const MIN_PLAYERS: int = 2
const MAX_SEARCH_TIME: float = 60.0
const SEARCH_INTERVAL: float = 5.0

var is_searching: bool = false
var search_timer: float = 0.0
var total_search_time: float = 0.0
var search_attempt: int = 0

enum MatchmakingRegion {
	ANY,
	US_EAST,
	US_WEST,
	EUROPE,
	ASIA,
	AUSTRALIA
}

var preferred_region: MatchmakingRegion = MatchmakingRegion.ANY
var preferred_wave_range: Vector2i = Vector2i(1, 99)  # Min and max wave

func _ready():
	if steam_manager:
		steam_manager.lobby_list_received.connect(_on_lobbies_found)
		steam_manager.lobby_joined.connect(_on_lobby_joined)
		steam_manager.lobby_join_failed.connect(_on_lobby_join_failed)

func _process(delta):
	if not is_searching:
		return

	search_timer -= delta
	total_search_time += delta

	# Timeout
	if total_search_time >= MAX_SEARCH_TIME:
		stop_matchmaking()
		matchmaking_failed.emit("Search timeout - no matches found")
		return

	# Search periodically
	if search_timer <= 0:
		search_timer = SEARCH_INTERVAL
		search_for_match()

func start_matchmaking():
	if is_searching:
		return

	if not steam_manager or not steam_manager.is_initialized():
		matchmaking_failed.emit("Steam not initialized")
		return

	is_searching = true
	search_timer = 0.0
	total_search_time = 0.0
	search_attempt = 0

	matchmaking_started.emit()
	print("Matchmaking started...")

	# Immediate first search
	search_for_match()

func stop_matchmaking():
	is_searching = false
	search_timer = 0.0
	total_search_time = 0.0

	matchmaking_stopped.emit()
	print("Matchmaking stopped")

func search_for_match():
	if not steam_manager:
		return

	search_attempt += 1
	print("Searching for match (attempt %d)..." % search_attempt)

	# Apply filters
	var steam = Engine.get_singleton("Steam")

	# Distance filter based on region
	match preferred_region:
		MatchmakingRegion.ANY:
			steam.addRequestLobbyListDistanceFilter(3)  # Worldwide
		_:
			steam.addRequestLobbyListDistanceFilter(2)  # Close

	# Result count
	steam.addRequestLobbyListResultCountFilter(50)

	# Filter for public lobbies only
	steam.addRequestLobbyListFilterSlotsAvailable(1)  # At least 1 slot open

	# Game mode filter
	steam.addRequestLobbyListStringFilter("game_mode", "survival", 0)  # Equal

	# Version filter (important!)
	steam.addRequestLobbyListStringFilter("version", "1.0.0", 0)

	# Request lobbies
	steam.requestLobbyList()

func _on_lobbies_found(lobbies: Array):
	if not is_searching:
		return

	print("Found %d lobbies" % lobbies.size())

	# Filter lobbies based on our preferences
	var suitable_lobbies = filter_suitable_lobbies(lobbies)

	if suitable_lobbies.is_empty():
		# No suitable lobbies, widen search or create own
		if search_attempt >= 3:
			# Create our own lobby after 3 failed attempts
			create_public_lobby()
		return

	# Join best lobby
	var best_lobby = find_best_lobby(suitable_lobbies)
	if best_lobby:
		print("Joining lobby %d" % best_lobby.id)
		steam_manager.join_lobby(best_lobby.id)

func filter_suitable_lobbies(lobbies: Array) -> Array:
	var suitable: Array = []

	for lobby_data in lobbies:
		# Check if lobby has space
		if lobby_data.members >= lobby_data.max_members:
			continue

		# Check wave range
		var wave = int(lobby_data.get("wave", "1"))
		if wave < preferred_wave_range.x or wave > preferred_wave_range.y:
			continue

		# Check if already started (optional)
		var is_started = lobby_data.get("started", "false") == "true"
		if is_started:
			continue

		suitable.append(lobby_data)

	return suitable

func find_best_lobby(lobbies: Array) -> Dictionary:
	if lobbies.is_empty():
		return {}

	# Score lobbies
	var best_lobby = null
	var best_score = -1.0

	for lobby in lobbies:
		var score = calculate_lobby_score(lobby)
		if score > best_score:
			best_score = score
			best_lobby = lobby

	return best_lobby

func calculate_lobby_score(lobby: Dictionary) -> float:
	var score = 0.0

	# Prefer lobbies with more players (but not full)
	var member_ratio = float(lobby.members) / float(lobby.max_members)
	if member_ratio >= 0.5:  # At least half full
		score += 50.0
	score += member_ratio * 20.0

	# Prefer lobbies at similar wave
	var wave = int(lobby.get("wave", "1"))
	var wave_diff = abs(wave - (preferred_wave_range.x + preferred_wave_range.y) / 2)
	score -= wave_diff * 2.0

	# Prefer lobbies that are about to start
	if lobby.members >= MIN_PLAYERS:
		score += 30.0

	return score

func create_public_lobby():
	print("Creating public lobby for matchmaking...")

	if not steam_manager:
		return

	# Create public lobby
	steam_manager.create_lobby(2)  # 2 = Public

	# Set matchmaking tags
	await get_tree().create_timer(0.5).timeout

	if steam_manager.is_in_lobby():
		steam_manager.set_lobby_data("matchmaking", "true")
		steam_manager.set_lobby_data("min_players", str(MIN_PLAYERS))

		# Start server
		if network_manager:
			network_manager.create_server_steam(steam_manager.get_lobby_id())

func _on_lobby_joined(lobby_id: int):
	if not is_searching:
		return

	stop_matchmaking()
	match_found.emit(lobby_id)
	print("Match found! Lobby: %d" % lobby_id)

func _on_lobby_join_failed(reason: String):
	if not is_searching:
		return

	print("Failed to join lobby: %s" % reason)
	# Continue searching
