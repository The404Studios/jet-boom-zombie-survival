extends Node
# Note: Do not use class_name here - this script is an autoload singleton

# Master game session manager - wires all systems together
# Coordinates: GameEventManager, PlayerManager, RoundManager, WaveManager,
# UI systems (Minimap, ObjectiveTracker, KillFeed, etc.)

signal session_started
signal session_ended(victory: bool, stats: Dictionary)
signal player_stats_updated(stats: Dictionary)

# ============================================
# SYSTEM REFERENCES
# ============================================

# Core managers
var game_events: Node  # GameEventManager
var player_manager: Node  # PlayerManager
var round_manager: Node  # RoundManager
var wave_manager: Node  # WaveManager
var game_coordinator: Node  # GameCoordinator
var spawn_manager: Node  # SpawnManager

# Network
var network_manager: Node
var state_synchronizer: Node

# Backend integration
var backend: Node
var websocket_hub: Node

# UI Elements
var hud_controller: Node
var minimap: Node
var objective_tracker: Node
var notification_manager: Node
var kill_feed: Node
var scoreboard: Node
var damage_numbers: Node
var end_round_stats: Node

# Settings
var is_multiplayer: bool = false
var local_peer_id: int = 1

# Session state
var session_active: bool = false
var session_stats: Dictionary = {}
var player_session_stats: Dictionary = {}  # peer_id -> stats

# Stats tracking
var round_start_time: float = 0.0
var session_start_time: float = 0.0
var total_kills: int = 0
var total_headshots: int = 0
var total_damage_dealt: float = 0.0
var total_damage_taken: float = 0.0
var total_deaths: int = 0
var shots_fired: int = 0
var shots_hit: int = 0

func _ready():
	add_to_group("session_manager")

	# Check multiplayer
	if multiplayer.has_multiplayer_peer():
		is_multiplayer = true
		local_peer_id = multiplayer.get_unique_id()

	# Initialize after a short delay to let other systems load
	call_deferred("_initialize_systems")

func _initialize_systems():
	await get_tree().create_timer(0.3).timeout

	# Get backend references
	backend = get_node_or_null("/root/Backend")
	websocket_hub = get_node_or_null("/root/WebSocketHub")

	# Find or create core systems
	_setup_game_events()
	_setup_player_manager()
	_setup_round_manager()
	_setup_wave_manager()
	_setup_spawn_manager()
	_setup_network_systems()

	# Find or create UI systems
	_setup_ui_systems()

	# Connect all systems together
	_connect_systems()

	print("GameSessionManager: All systems initialized and connected")

# ============================================
# SYSTEM SETUP
# ============================================

func _setup_game_events():
	game_events = get_node_or_null("/root/GameEvents")
	if not game_events:
		game_events = load("res://scripts/systems/game_event_manager.gd").new()
		game_events.name = "GameEvents"
		get_tree().root.add_child(game_events)

	# Connect to game events
	if game_events:
		_connect_if_signal_exists(game_events, "player_died", _on_player_died)
		_connect_if_signal_exists(game_events, "zombie_killed", _on_zombie_killed)
		_connect_if_signal_exists(game_events, "damage_dealt", _on_damage_dealt)
		_connect_if_signal_exists(game_events, "headshot_landed", _on_headshot)
		_connect_if_signal_exists(game_events, "game_over", _on_game_over)
		_connect_if_signal_exists(game_events, "round_ended", _on_round_ended)

func _setup_player_manager():
	player_manager = get_node_or_null("/root/PlayerManager")
	if not player_manager:
		var pm_script = load("res://scripts/systems/player_manager.gd")
		if pm_script:
			player_manager = pm_script.new()
			player_manager.name = "PlayerManager"
			get_tree().root.add_child(player_manager)

	if player_manager:
		_connect_if_signal_exists(player_manager, "player_spawned", _on_player_spawned)
		_connect_if_signal_exists(player_manager, "player_died", _on_player_manager_died)
		_connect_if_signal_exists(player_manager, "all_players_dead", _on_all_players_dead)

func _setup_round_manager():
	round_manager = get_node_or_null("/root/RoundManager")
	if not round_manager:
		var rm_script = load("res://scripts/systems/round_manager.gd")
		if rm_script:
			round_manager = rm_script.new()
			round_manager.name = "RoundManager"
			get_tree().root.add_child(round_manager)

	if round_manager:
		_connect_if_signal_exists(round_manager, "round_started", _on_round_started)
		_connect_if_signal_exists(round_manager, "round_ended", _on_round_ended_rm)
		_connect_if_signal_exists(round_manager, "game_over", _on_game_over_rm)
		_connect_if_signal_exists(round_manager, "intermission_started", _on_intermission_started)

func _setup_wave_manager():
	wave_manager = get_node_or_null("/root/WaveManager")
	if not wave_manager:
		wave_manager = get_tree().get_first_node_in_group("wave_manager")

	if wave_manager:
		_connect_if_signal_exists(wave_manager, "wave_started", _on_wave_started)
		_connect_if_signal_exists(wave_manager, "wave_completed", _on_wave_completed)
		_connect_if_signal_exists(wave_manager, "zombie_spawned", _on_zombie_spawned)
		_connect_if_signal_exists(wave_manager, "intermission_started", _on_wave_intermission)
		_connect_if_signal_exists(wave_manager, "boss_wave", _on_boss_wave)

func _setup_spawn_manager():
	spawn_manager = get_node_or_null("/root/SpawnManager")
	if not spawn_manager:
		var sm_script = load("res://scripts/systems/spawn_manager.gd")
		if sm_script:
			spawn_manager = sm_script.new()
			spawn_manager.name = "SpawnManager"
			get_tree().root.add_child(spawn_manager)

func _setup_network_systems():
	network_manager = get_node_or_null("/root/NetworkManager")

	# Create state synchronizer for multiplayer
	if is_multiplayer and not state_synchronizer:
		var ss_script = load("res://scripts/systems/state_synchronizer.gd")
		if ss_script:
			state_synchronizer = ss_script.new()
			state_synchronizer.name = "StateSynchronizer"
			get_tree().root.add_child(state_synchronizer)

func _setup_ui_systems():
	# Find HUD
	hud_controller = get_tree().get_first_node_in_group("hud")

	# Create or find UI elements
	_setup_minimap()
	_setup_objective_tracker()
	_setup_notification_manager()
	_setup_kill_feed()
	_setup_scoreboard()
	_setup_damage_numbers()
	_setup_end_round_stats()

func _setup_minimap():
	minimap = get_tree().get_first_node_in_group("minimap")
	if not minimap and hud_controller:
		var mm_script = load("res://scripts/ui/minimap.gd")
		if mm_script:
			minimap = mm_script.new()
			minimap.name = "Minimap"
			minimap.add_to_group("minimap")
			# Position in top-right
			minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			minimap.position = Vector2(-170, 10)
			hud_controller.add_child(minimap)

func _setup_objective_tracker():
	objective_tracker = get_tree().get_first_node_in_group("objective_tracker")
	if not objective_tracker and hud_controller:
		var ot_script = load("res://scripts/ui/objective_tracker.gd")
		if ot_script:
			objective_tracker = ot_script.new()
			objective_tracker.name = "ObjectiveTracker"
			objective_tracker.add_to_group("objective_tracker")
			# Position on left side
			objective_tracker.set_anchors_preset(Control.PRESET_TOP_LEFT)
			objective_tracker.position = Vector2(10, 100)
			objective_tracker.custom_minimum_size = Vector2(250, 200)
			hud_controller.add_child(objective_tracker)

func _setup_notification_manager():
	notification_manager = get_node_or_null("/root/NotificationManager")
	if not notification_manager:
		var nm_script = load("res://scripts/ui/notification_manager.gd")
		if nm_script:
			notification_manager = nm_script.new()
			notification_manager.name = "NotificationManager"
			get_tree().root.add_child(notification_manager)

	# Bind to game events
	if game_events and notification_manager:
		game_events.bind_notification_manager(notification_manager)

func _setup_kill_feed():
	kill_feed = get_tree().get_first_node_in_group("kill_feed_ui")
	if not kill_feed and hud_controller:
		var kf_script = load("res://scripts/ui/kill_feed.gd")
		if kf_script:
			kill_feed = kf_script.new()
			kill_feed.name = "KillFeedUI"
			kill_feed.add_to_group("kill_feed_ui")
			# Position in top-right, below minimap
			kill_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			kill_feed.position = Vector2(-310, 180)
			kill_feed.custom_minimum_size = Vector2(300, 200)
			hud_controller.add_child(kill_feed)

	# Bind to game events
	if game_events and kill_feed:
		game_events.bind_kill_feed(kill_feed)

func _setup_scoreboard():
	scoreboard = get_tree().get_first_node_in_group("scoreboard")
	if not scoreboard and hud_controller:
		var sb_script = load("res://scripts/ui/scoreboard.gd")
		if sb_script:
			scoreboard = sb_script.new()
			scoreboard.name = "Scoreboard"
			scoreboard.add_to_group("scoreboard")
			scoreboard.visible = false  # Hidden by default
			hud_controller.add_child(scoreboard)

	# Bind to game events
	if game_events and scoreboard:
		game_events.bind_scoreboard(scoreboard)

func _setup_damage_numbers():
	damage_numbers = get_node_or_null("/root/DamageNumbers")
	if not damage_numbers:
		var dn_script = load("res://scripts/systems/damage_numbers.gd")
		if dn_script:
			damage_numbers = dn_script.new()
			damage_numbers.name = "DamageNumbers"
			get_tree().root.add_child(damage_numbers)

	# Bind to game events
	if game_events and damage_numbers:
		game_events.bind_damage_numbers(damage_numbers)

func _setup_end_round_stats():
	end_round_stats = get_tree().get_first_node_in_group("end_round_stats")
	if not end_round_stats and hud_controller:
		var ers_script = load("res://scripts/ui/end_round_stats.gd")
		if ers_script:
			end_round_stats = ers_script.new()
			end_round_stats.name = "EndRoundStats"
			end_round_stats.add_to_group("end_round_stats")
			end_round_stats.visible = false
			hud_controller.add_child(end_round_stats)

			# Connect signals
			if end_round_stats.has_signal("continue_pressed"):
				end_round_stats.continue_pressed.connect(_on_continue_from_stats)
			if end_round_stats.has_signal("restart_pressed"):
				end_round_stats.restart_pressed.connect(_on_restart_requested)
			if end_round_stats.has_signal("main_menu_pressed"):
				end_round_stats.main_menu_pressed.connect(_on_main_menu_requested)

func _connect_systems():
	# Connect game coordinator to round/wave managers
	game_coordinator = get_tree().get_first_node_in_group("game_coordinator")
	if game_coordinator:
		_connect_if_signal_exists(game_coordinator, "game_phase_changed", _on_phase_changed)
		_connect_if_signal_exists(game_coordinator, "game_over", _on_coordinator_game_over)

# ============================================
# SESSION MANAGEMENT
# ============================================

func start_session():
	"""Start a new game session"""
	session_active = true
	session_start_time = Time.get_unix_time_from_system()

	# Reset stats
	_reset_session_stats()

	# Initialize player stats tracking
	_init_player_stats()

	session_started.emit()

	if notification_manager:
		notification_manager.announce("GAME START", "Survive the zombie horde!")

	print("GameSessionManager: Session started")

func end_session(victory: bool):
	"""End the current game session"""
	session_active = false

	# Compile final stats
	var stats = _compile_session_stats(victory)

	# Sync stats to backend
	_sync_stats_to_backend(victory, stats)

	# Show end screen
	if end_round_stats:
		end_round_stats.show_game_over(victory, stats)

	session_ended.emit(victory, stats)

	print("GameSessionManager: Session ended - Victory: %s" % victory)

func _sync_stats_to_backend(victory: bool, stats: Dictionary):
	"""Sync session stats to backend server"""
	if not backend:
		return

	# Update player stats
	var stat_update = {
		"kills": stats.get("kills", 0),
		"deaths": stats.get("deaths", 0),
		"gamesPlayed": 1,
		"gamesWon": 1 if victory else 0,
		"highestWave": stats.get("final_wave", 0),
		"playTimeSeconds": int(stats.get("total_time", 0)),
		"damageDealt": int(stats.get("damage_dealt", 0)),
		"headshots": stats.get("headshots", 0)
	}

	backend.update_stats(stat_update, func(response):
		if response.success:
			print("GameSessionManager: Stats synced to backend")
		else:
			print("GameSessionManager: Failed to sync stats - %s" % response.get("error", "Unknown"))
	)

	# Record the match
	var match_record = {
		"victory": victory,
		"waveReached": stats.get("final_wave", 0),
		"kills": stats.get("kills", 0),
		"deaths": stats.get("deaths", 0),
		"pointsEarned": stats.get("points_earned", 0),
		"playTimeSeconds": int(stats.get("total_time", 0)),
		"accuracy": stats.get("accuracy", 0),
		"headshots": stats.get("headshots", 0)
	}

	backend.record_match(match_record, func(response):
		if response.success:
			print("GameSessionManager: Match recorded to backend")
	)

	# Notify via WebSocket if connected
	if websocket_hub and websocket_hub.is_connected:
		websocket_hub.broadcast_game_end(victory, stats.get("final_wave", 0), stats)

func _reset_session_stats():
	total_kills = 0
	total_headshots = 0
	total_damage_dealt = 0.0
	total_damage_taken = 0.0
	total_deaths = 0
	shots_fired = 0
	shots_hit = 0
	player_session_stats.clear()

func _init_player_stats():
	# Initialize stats for local player
	player_session_stats[local_peer_id] = _create_empty_player_stats()

	# Initialize for remote players in multiplayer
	if is_multiplayer and network_manager:
		if "players" in network_manager:
			for peer_id in network_manager.players.keys():
				if peer_id != local_peer_id:
					player_session_stats[peer_id] = _create_empty_player_stats()

func _create_empty_player_stats() -> Dictionary:
	return {
		"name": "Player",
		"kills": 0,
		"deaths": 0,
		"headshots": 0,
		"damage_dealt": 0.0,
		"damage_taken": 0.0,
		"score": 0,
		"accuracy": 0,
		"shots_fired": 0,
		"shots_hit": 0,
		"items_collected": 0,
		"is_local": false
	}

func _compile_session_stats(victory: bool) -> Dictionary:
	var total_time = Time.get_unix_time_from_system() - session_start_time
	var wave = 0
	if wave_manager and "current_wave" in wave_manager:
		wave = wave_manager.current_wave

	# Update local player stats
	if player_session_stats.has(local_peer_id):
		var local_stats = player_session_stats[local_peer_id]
		local_stats.kills = total_kills
		local_stats.headshots = total_headshots
		local_stats.damage_dealt = total_damage_dealt
		local_stats.damage_taken = total_damage_taken
		local_stats.deaths = total_deaths
		local_stats.shots_fired = shots_fired
		local_stats.shots_hit = shots_hit
		local_stats.accuracy = int((float(shots_hit) / max(shots_fired, 1)) * 100)
		local_stats.is_local = true
		local_stats.score = total_kills * 100 + total_headshots * 50

	# Convert to array for display
	var players_array = []
	for peer_id in player_session_stats.keys():
		var stats = player_session_stats[peer_id].duplicate()
		stats.peer_id = peer_id
		players_array.append(stats)

	# Generate awards
	var awards = []
	if players_array.size() > 0:
		awards = EndRoundStats.generate_awards(players_array) if end_round_stats else []

	return {
		"victory": victory,
		"final_wave": wave,
		"total_time": total_time,
		"kills": total_kills,
		"headshots": total_headshots,
		"damage_dealt": total_damage_dealt,
		"damage_taken": total_damage_taken,
		"deaths": total_deaths,
		"accuracy": int((float(shots_hit) / max(shots_fired, 1)) * 100),
		"points_earned": total_kills * 100 + total_headshots * 50,
		"items_collected": 0,
		"players": players_array,
		"awards": awards
	}

# ============================================
# EVENT HANDLERS
# ============================================

func _on_player_spawned(peer_id: int, player: Node):
	if not player_session_stats.has(peer_id):
		player_session_stats[peer_id] = _create_empty_player_stats()

	# Set player name
	if player.has("player_name"):
		player_session_stats[peer_id].name = player.player_name
	elif peer_id == local_peer_id:
		player_session_stats[peer_id].name = "You"
	else:
		player_session_stats[peer_id].name = "Player %d" % peer_id

	player_session_stats[peer_id].is_local = (peer_id == local_peer_id)

func _on_player_died(peer_id: int, killer_id: int, _weapon: String, _is_headshot: bool):
	if player_session_stats.has(peer_id):
		player_session_stats[peer_id].deaths += 1

	if peer_id == local_peer_id:
		total_deaths += 1

func _on_player_manager_died(peer_id: int, _killer_id: int):
	if peer_id == local_peer_id:
		total_deaths += 1

func _on_zombie_killed(zombie: Node, killer_id: int, _weapon: String, is_headshot: bool):
	if killer_id == local_peer_id:
		total_kills += 1
		if is_headshot:
			total_headshots += 1

		# Add combo kill
		if game_events:
			game_events.add_combo_kill(killer_id, zombie.global_position if zombie else Vector3.ZERO)

	# Update player stats
	if player_session_stats.has(killer_id):
		player_session_stats[killer_id].kills += 1
		if is_headshot:
			player_session_stats[killer_id].headshots += 1
		player_session_stats[killer_id].score += 100 + (50 if is_headshot else 0)

func _on_damage_dealt(attacker_id: int, _target: Node, damage: float, _position: Vector3, _is_crit: bool):
	if attacker_id == local_peer_id:
		total_damage_dealt += damage
		shots_hit += 1

	if player_session_stats.has(attacker_id):
		player_session_stats[attacker_id].damage_dealt += damage

func _on_headshot(attacker_id: int, _target: Node):
	# Track headshot in player stats
	total_headshots += 1

	if player_session_stats.has(attacker_id):
		if not player_session_stats[attacker_id].has("headshots"):
			player_session_stats[attacker_id].headshots = 0
		player_session_stats[attacker_id].headshots += 1

	# Show hitmarker effect
	if hud_controller and hud_controller.has_method("show_headshot_hitmarker"):
		hud_controller.show_headshot_hitmarker()

func _on_round_started(round_num: int):
	round_start_time = Time.get_unix_time_from_system()

	if objective_tracker:
		objective_tracker.start_wave(round_num, 0)

func _on_wave_started(wave_num: int, zombie_count: int):
	if objective_tracker:
		objective_tracker.start_wave(wave_num, zombie_count)

	if notification_manager:
		notification_manager.notify_wave_start(wave_num)

func _on_wave_completed(wave_num: int):
	if notification_manager:
		notification_manager.notify_wave_complete(wave_num)

	# Show round stats
	var round_time = Time.get_unix_time_from_system() - round_start_time
	var stats = _compile_session_stats(true)
	stats.round_time = round_time

	if end_round_stats:
		end_round_stats.show_round_complete(wave_num, stats, true)

func _on_round_ended(round_num: int, victory: bool):
	if not victory:
		# Game over - show final stats
		var round_time = Time.get_unix_time_from_system() - round_start_time
		var stats = _compile_session_stats(false)
		stats.round_time = round_time
		stats.final_round = round_num

		if end_round_stats:
			end_round_stats.show_game_over(round_num, stats)

		if notification_manager:
			notification_manager.announce("GAME OVER", "Survived %d waves" % round_num)

func _on_round_ended_rm(round_num: int, victory: bool):
	if victory:
		_on_wave_completed(round_num)

func _on_zombie_spawned(zombie: Node, _zombie_class):
	# Update objective tracker zombie count
	if wave_manager and objective_tracker:
		var remaining = wave_manager.get_zombies_remaining() if wave_manager.has_method("get_zombies_remaining") else 0
		var total = wave_manager.zombies_to_spawn if "zombies_to_spawn" in wave_manager else 0
		objective_tracker.set_wave_zombies(remaining, total)

func _on_wave_intermission(duration: float):
	if notification_manager:
		notification_manager.notify_intermission(int(duration))

func _on_boss_wave(wave_num: int):
	if notification_manager:
		notification_manager.announce("BOSS WAVE", "Wave %d - A powerful enemy approaches!" % wave_num)

func _on_intermission_started(duration: float):
	if notification_manager:
		notification_manager.notify_intermission(int(duration))

func _on_game_over(victory: bool):
	end_session(victory)

func _on_game_over_rm(victory: bool):
	end_session(victory)

func _on_coordinator_game_over(victory: bool):
	end_session(victory)

func _on_all_players_dead():
	# All players dead - game over
	end_session(false)

func _on_phase_changed(phase):
	# Update UI based on game phase
	var phase_name = ""
	var phase_color = Color.WHITE

	# Determine phase info (phase could be enum or string)
	if phase is int:
		match phase:
			0:  # LOBBY/WAITING
				phase_name = "Waiting for Players"
				phase_color = Color(0.5, 0.5, 0.8)
			1:  # WARMUP
				phase_name = "Warmup"
				phase_color = Color(0.8, 0.8, 0.2)
			2:  # COMBAT
				phase_name = "Combat"
				phase_color = Color(0.8, 0.2, 0.2)
			3:  # INTERMISSION
				phase_name = "Intermission"
				phase_color = Color(0.2, 0.8, 0.2)
			4:  # BOSS
				phase_name = "Boss Wave"
				phase_color = Color(0.8, 0.2, 0.8)
			5:  # ENDED
				phase_name = "Game Over"
				phase_color = Color(0.5, 0.5, 0.5)
	elif phase is String:
		phase_name = phase.capitalize()

	# Notify HUD
	if hud_controller and hud_controller.has_method("set_game_phase"):
		hud_controller.set_game_phase(phase_name, phase_color)

	# Show phase announcement for important transitions
	if notification_manager and phase_name != "":
		if phase is int and phase in [2, 4]:  # Combat or Boss
			notification_manager.announce(phase_name.to_upper(), "")

func _on_continue_from_stats():
	# Resume game after viewing round stats
	if end_round_stats:
		end_round_stats.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_restart_requested():
	# Restart the game
	get_tree().reload_current_scene()

func _on_main_menu_requested():
	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# ============================================
# PUBLIC API
# ============================================

func record_shot_fired(peer_id: int = -1):
	"""Record a shot being fired for accuracy tracking"""
	if peer_id == -1:
		peer_id = local_peer_id

	if peer_id == local_peer_id:
		shots_fired += 1

	if player_session_stats.has(peer_id):
		player_session_stats[peer_id].shots_fired += 1

func record_shot_hit(peer_id: int = -1):
	"""Record a shot hitting for accuracy tracking"""
	if peer_id == -1:
		peer_id = local_peer_id

	if peer_id == local_peer_id:
		shots_hit += 1

	if player_session_stats.has(peer_id):
		player_session_stats[peer_id].shots_hit += 1

func record_damage_taken(peer_id: int, damage: float):
	"""Record damage taken"""
	if peer_id == local_peer_id:
		total_damage_taken += damage

	if player_session_stats.has(peer_id):
		player_session_stats[peer_id].damage_taken += damage

func record_item_collected(peer_id: int = -1):
	"""Record item collection"""
	if peer_id == -1:
		peer_id = local_peer_id

	if player_session_stats.has(peer_id):
		player_session_stats[peer_id].items_collected += 1

func get_player_stats(peer_id: int = -1) -> Dictionary:
	"""Get stats for a specific player"""
	if peer_id == -1:
		peer_id = local_peer_id

	if player_session_stats.has(peer_id):
		return player_session_stats[peer_id].duplicate()

	return {}

func get_session_stats() -> Dictionary:
	"""Get current session stats"""
	return _compile_session_stats(false)

func get_leaderboard() -> Array:
	"""Get sorted leaderboard"""
	var players = []
	for peer_id in player_session_stats.keys():
		var stats = player_session_stats[peer_id].duplicate()
		stats.peer_id = peer_id
		players.append(stats)

	players.sort_custom(func(a, b): return a.score > b.score)
	return players

# ============================================
# UTILITY
# ============================================

func _connect_if_signal_exists(obj: Node, signal_name: String, callable: Callable):
	"""Safely connect to a signal if it exists and isn't already connected"""
	if obj and obj.has_signal(signal_name):
		if not obj.is_connected(signal_name, callable):
			obj.connect(signal_name, callable)

func _exit_tree():
	"""Clean up all signal connections to prevent memory leaks"""
	# Disconnect game events
	if game_events:
		_disconnect_if_connected(game_events, "player_died", _on_player_died)
		_disconnect_if_connected(game_events, "zombie_killed", _on_zombie_killed)
		_disconnect_if_connected(game_events, "damage_dealt", _on_damage_dealt)
		_disconnect_if_connected(game_events, "headshot_landed", _on_headshot)
		_disconnect_if_connected(game_events, "game_over", _on_game_over)
		_disconnect_if_connected(game_events, "round_ended", _on_round_ended)

	# Disconnect player manager
	if player_manager:
		_disconnect_if_connected(player_manager, "player_spawned", _on_player_spawned)
		_disconnect_if_connected(player_manager, "player_died", _on_player_manager_died)
		_disconnect_if_connected(player_manager, "all_players_dead", _on_all_players_dead)

	# Disconnect round manager
	if round_manager:
		_disconnect_if_connected(round_manager, "round_started", _on_round_started)
		_disconnect_if_connected(round_manager, "round_ended", _on_round_ended_rm)
		_disconnect_if_connected(round_manager, "game_over", _on_game_over_rm)
		_disconnect_if_connected(round_manager, "intermission_started", _on_intermission_started)

	# Disconnect wave manager
	if wave_manager:
		_disconnect_if_connected(wave_manager, "wave_started", _on_wave_started)
		_disconnect_if_connected(wave_manager, "wave_completed", _on_wave_completed)
		_disconnect_if_connected(wave_manager, "zombie_spawned", _on_zombie_spawned)
		_disconnect_if_connected(wave_manager, "intermission_started", _on_wave_intermission)
		_disconnect_if_connected(wave_manager, "boss_wave", _on_boss_wave)

	# Disconnect game coordinator
	if game_coordinator:
		_disconnect_if_connected(game_coordinator, "game_phase_changed", _on_phase_changed)
		_disconnect_if_connected(game_coordinator, "game_over", _on_coordinator_game_over)

	# Disconnect end round stats
	if end_round_stats:
		_disconnect_if_connected(end_round_stats, "continue_pressed", _on_continue_from_stats)
		_disconnect_if_connected(end_round_stats, "restart_pressed", _on_restart_requested)
		_disconnect_if_connected(end_round_stats, "main_menu_pressed", _on_main_menu_requested)

	# Clear data
	player_session_stats.clear()
	session_stats.clear()

func _disconnect_if_connected(obj: Node, signal_name: String, callable: Callable):
	"""Safely disconnect from a signal if connected"""
	if obj and obj.has_signal(signal_name):
		if obj.is_connected(signal_name, callable):
			obj.disconnect(signal_name, callable)
