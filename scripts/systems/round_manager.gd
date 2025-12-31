extends Node
class_name RoundManager

# Manages game rounds/sessions for zombie survival
# Handles round states, win/lose conditions, and round transitions

signal round_starting(round_number: int)
signal round_started(round_number: int)
signal round_ending(victory: bool)
signal round_ended(victory: bool, stats: Dictionary)
signal intermission_started(duration: float)
signal intermission_ended
signal game_over(victory: bool, final_stats: Dictionary)
signal objective_updated(objective: String, progress: float)

enum RoundState {
	WAITING,       # Waiting for players
	COUNTDOWN,     # Pre-round countdown
	ACTIVE,        # Round in progress
	INTERMISSION,  # Between rounds
	ENDING,        # Round ending
	GAME_OVER      # Game finished
}

# Round settings
@export var rounds_to_win: int = 10  # Total rounds to complete for victory
@export var countdown_duration: float = 5.0
@export var intermission_duration: float = 15.0
@export var minimum_players: int = 1
@export var allow_late_join: bool = true

# Current state
var current_state: RoundState = RoundState.WAITING
var current_round: int = 0
var round_start_time: float = 0.0
var state_timer: float = 0.0

# Round statistics
var round_stats: Dictionary = {
	"zombies_killed": 0,
	"players_died": 0,
	"damage_dealt": 0,
	"damage_taken": 0,
	"items_used": 0,
	"headshots": 0,
	"time_elapsed": 0.0
}

# Game statistics (accumulated across rounds)
var game_stats: Dictionary = {
	"total_rounds": 0,
	"total_zombies_killed": 0,
	"total_deaths": 0,
	"fastest_round": INF,
	"highest_kills_round": 0
}

# Objectives
var current_objective: String = ""
var objective_progress: float = 0.0

# References
var wave_manager: Node = null
var player_manager: Node = null
var network_manager: Node = null

# Backend integration
var backend: Node = null
var websocket_hub: Node = null

func _ready():
	# Get references
	wave_manager = get_node_or_null("/root/WaveManager")
	player_manager = get_node_or_null("/root/PlayerManager")
	network_manager = get_node_or_null("/root/NetworkManager")

	# Initialize backend
	_init_backend()

	# Connect signals
	if wave_manager:
		if wave_manager.has_signal("wave_completed"):
			wave_manager.wave_completed.connect(_on_wave_completed)
		if wave_manager.has_signal("all_waves_completed"):
			wave_manager.all_waves_completed.connect(_on_all_waves_completed)

	if player_manager:
		if player_manager.has_signal("all_players_dead"):
			player_manager.all_players_dead.connect(_on_all_players_dead)
		if player_manager.has_signal("player_died"):
			player_manager.player_died.connect(_on_player_died)

func _init_backend():
	backend = get_node_or_null("/root/Backend")
	websocket_hub = get_node_or_null("/root/WebSocketHub")

func _process(delta):
	match current_state:
		RoundState.WAITING:
			_process_waiting(delta)
		RoundState.COUNTDOWN:
			_process_countdown(delta)
		RoundState.ACTIVE:
			_process_active(delta)
		RoundState.INTERMISSION:
			_process_intermission(delta)
		RoundState.ENDING:
			_process_ending(delta)

# ============================================
# STATE PROCESSING
# ============================================

func _process_waiting(_delta: float):
	# Check if we have enough players
	var player_count = _get_player_count()

	if player_count >= minimum_players:
		start_countdown()

func _process_countdown(delta: float):
	state_timer -= delta

	if state_timer <= 0:
		start_round()

func _process_active(delta: float):
	# Update round time
	round_stats.time_elapsed += delta

	# Check win/lose conditions
	_check_round_conditions()

func _process_intermission(delta: float):
	state_timer -= delta

	if state_timer <= 0:
		intermission_ended.emit()
		start_countdown()

func _process_ending(delta: float):
	state_timer -= delta

	if state_timer <= 0:
		_finalize_round()

# ============================================
# ROUND FLOW
# ============================================

func start_countdown():
	"""Start pre-round countdown"""
	current_state = RoundState.COUNTDOWN
	state_timer = countdown_duration

	current_round += 1
	round_starting.emit(current_round)

	# Sync to network
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_round_state.rpc(RoundState.COUNTDOWN, current_round, countdown_duration)

func start_round():
	"""Start the active round"""
	current_state = RoundState.ACTIVE
	round_start_time = Time.get_ticks_msec() / 1000.0

	# Reset round stats
	_reset_round_stats()

	# Set objective
	current_objective = "Survive Wave %d" % current_round
	objective_progress = 0.0
	objective_updated.emit(current_objective, objective_progress)

	round_started.emit(current_round)

	# Start wave spawning
	if wave_manager and wave_manager.has_method("start_wave"):
		wave_manager.start_wave(current_round)

	# Sync to network
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_round_state.rpc(RoundState.ACTIVE, current_round, 0.0)

func end_round(victory: bool):
	"""End the current round"""
	if current_state == RoundState.ENDING or current_state == RoundState.GAME_OVER:
		return

	current_state = RoundState.ENDING
	state_timer = 3.0  # Brief pause before next round

	round_ending.emit(victory)

	# Update game stats
	game_stats.total_rounds += 1
	game_stats.total_zombies_killed += round_stats.zombies_killed
	game_stats.total_deaths += round_stats.players_died

	if round_stats.time_elapsed < game_stats.fastest_round:
		game_stats.fastest_round = round_stats.time_elapsed

	if round_stats.zombies_killed > game_stats.highest_kills_round:
		game_stats.highest_kills_round = round_stats.zombies_killed

	# Sync to network
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_round_end.rpc(victory, round_stats)

func _finalize_round():
	"""Finalize round and determine next action"""
	var victory = round_stats.players_died == 0

	round_ended.emit(victory, round_stats)

	# Check for game over
	if not victory:
		# Players lost - game over
		trigger_game_over(false)
	elif current_round >= rounds_to_win:
		# All rounds completed - victory!
		trigger_game_over(true)
	else:
		# Continue to intermission
		start_intermission()

func start_intermission():
	"""Start intermission between rounds"""
	current_state = RoundState.INTERMISSION
	state_timer = intermission_duration

	intermission_started.emit(intermission_duration)

	# Respawn dead players
	if player_manager and player_manager.has_method("respawn_all_dead"):
		player_manager.respawn_all_dead()

	# Sync to network
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_round_state.rpc(RoundState.INTERMISSION, current_round, intermission_duration)

func trigger_game_over(victory: bool):
	"""Trigger game over state"""
	current_state = RoundState.GAME_OVER

	game_over.emit(victory, game_stats)

	# Sync to network
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_game_over.rpc(victory, game_stats)

	# Sync final stats to backend
	_sync_game_stats_to_backend(victory)

# ============================================
# CONDITIONS
# ============================================

func _check_round_conditions():
	"""Check for round win/lose conditions"""
	# Check if all players are dead
	var alive_count = _get_alive_player_count()
	if alive_count <= 0:
		end_round(false)
		return

	# Check if wave is complete
	if wave_manager:
		var zombies_remaining = 0
		if "zombies_alive" in wave_manager:
			zombies_remaining = wave_manager.zombies_alive
		elif wave_manager.has_method("get_zombies_alive"):
			zombies_remaining = wave_manager.get_zombies_alive()

		if zombies_remaining <= 0:
			var wave_complete = false
			if "is_wave_active" in wave_manager:
				wave_complete = not wave_manager.is_wave_active
			elif wave_manager.has_method("is_wave_complete"):
				wave_complete = wave_manager.is_wave_complete()

			if wave_complete:
				end_round(true)

# ============================================
# STATISTICS
# ============================================

func _reset_round_stats():
	"""Reset statistics for a new round"""
	round_stats = {
		"zombies_killed": 0,
		"players_died": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"items_used": 0,
		"headshots": 0,
		"time_elapsed": 0.0
	}

func add_zombie_kill(headshot: bool = false):
	"""Record a zombie kill"""
	round_stats.zombies_killed += 1
	if headshot:
		round_stats.headshots += 1

	# Update objective progress
	if wave_manager:
		var total_zombies = 10 + (current_round * 2)  # Estimate
		objective_progress = float(round_stats.zombies_killed) / total_zombies
		objective_updated.emit(current_objective, objective_progress)

func add_damage_dealt(amount: float):
	"""Record damage dealt"""
	round_stats.damage_dealt += amount

func add_damage_taken(amount: float):
	"""Record damage taken"""
	round_stats.damage_taken += amount

func add_item_used():
	"""Record item usage"""
	round_stats.items_used += 1

func get_round_stats() -> Dictionary:
	return round_stats.duplicate()

func get_game_stats() -> Dictionary:
	return game_stats.duplicate()

# ============================================
# NETWORK SYNC
# ============================================

@rpc("authority", "call_remote", "reliable")
func _sync_round_state(state: int, round_num: int, timer: float):
	"""Sync round state to clients"""
	current_state = state as RoundState
	current_round = round_num
	state_timer = timer

	match current_state:
		RoundState.COUNTDOWN:
			round_starting.emit(current_round)
		RoundState.ACTIVE:
			_reset_round_stats()
			round_started.emit(current_round)
		RoundState.INTERMISSION:
			intermission_started.emit(timer)

@rpc("authority", "call_remote", "reliable")
func _sync_round_end(victory: bool, stats: Dictionary):
	"""Sync round end to clients"""
	round_stats = stats
	round_ending.emit(victory)

@rpc("authority", "call_remote", "reliable")
func _sync_game_over(victory: bool, stats: Dictionary):
	"""Sync game over to clients"""
	current_state = RoundState.GAME_OVER
	game_stats = stats
	game_over.emit(victory, stats)

# ============================================
# EVENTS
# ============================================

func _on_wave_completed(_wave_number: int):
	"""Handle wave completion"""
	# Round ends when wave is complete
	if current_state == RoundState.ACTIVE:
		end_round(true)

func _on_all_waves_completed():
	"""Handle all waves complete"""
	trigger_game_over(true)

func _on_all_players_dead():
	"""Handle all players dying"""
	if current_state == RoundState.ACTIVE:
		end_round(false)

func _on_player_died(_peer_id: int, _killer_id: int):
	"""Handle player death"""
	round_stats.players_died += 1

# ============================================
# UTILITY
# ============================================

func _get_player_count() -> int:
	"""Get number of connected players"""
	if player_manager and player_manager.has_method("get_player_count"):
		return player_manager.get_player_count()

	return get_tree().get_nodes_in_group("players").size()

func _get_alive_player_count() -> int:
	"""Get number of alive players"""
	if player_manager and player_manager.has_method("get_alive_count"):
		return player_manager.get_alive_count()

	var count = 0
	for player in get_tree().get_nodes_in_group("players"):
		if player.has_method("is_alive") and player.is_alive():
			count += 1
		elif "is_dead" in player and not player.is_dead:
			count += 1
		elif "current_health" in player and player.current_health > 0:
			count += 1
		else:
			count += 1  # Assume alive if can't check

	return count

func is_round_active() -> bool:
	return current_state == RoundState.ACTIVE

func is_intermission() -> bool:
	return current_state == RoundState.INTERMISSION

func is_game_over() -> bool:
	return current_state == RoundState.GAME_OVER

func get_current_round() -> int:
	return current_round

func get_state_timer() -> float:
	return state_timer

func get_round_time() -> float:
	return round_stats.time_elapsed

func reset_game():
	"""Reset for a new game"""
	current_state = RoundState.WAITING
	current_round = 0
	state_timer = 0.0

	_reset_round_stats()
	game_stats = {
		"total_rounds": 0,
		"total_zombies_killed": 0,
		"total_deaths": 0,
		"fastest_round": INF,
		"highest_kills_round": 0
	}

# ============================================
# BACKEND INTEGRATION
# ============================================

func _sync_game_stats_to_backend(victory: bool):
	"""Sync game stats to backend at game end"""
	if not backend or not backend.is_authenticated:
		return

	# Update player stats
	var stat_update = {
		"kills": game_stats.total_zombies_killed,
		"deaths": game_stats.total_deaths,
		"gamesPlayed": 1,
		"gamesWon": 1 if victory else 0,
		"highestWave": current_round,
		"headshots": round_stats.headshots,
		"damageDealt": int(round_stats.damage_dealt)
	}

	backend.update_stats(stat_update, func(response):
		if response.success:
			print("Game stats synced to backend")
	)

	# Record match
	var match_record = {
		"victory": victory,
		"rounds": current_round,
		"kills": game_stats.total_zombies_killed,
		"deaths": game_stats.total_deaths,
		"duration": int(round_stats.time_elapsed)
	}

	backend.record_match(match_record, func(response):
		if response.success:
			print("Match recorded to backend")
	)

func sync_round_progress_to_backend():
	"""Sync current round progress to backend (for server info)"""
	if not websocket_hub:
		return

	if websocket_hub.has_method("update_server_info"):
		websocket_hub.update_server_info({
			"currentRound": current_round,
			"maxRounds": rounds_to_win,
			"state": RoundState.keys()[current_state]
		})
