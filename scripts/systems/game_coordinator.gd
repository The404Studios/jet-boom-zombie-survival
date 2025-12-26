extends Node
class_name GameCoordinator

# Game Coordinator - Central hub that wires all game systems together
# Manages game flow, player spawning, sigil meetup phase, and wave progression

signal game_phase_changed(phase: GamePhase)
signal meetup_timer_updated(time_remaining: float)
signal all_players_ready
signal game_started
signal game_over(victory: bool)

enum GamePhase {
	LOBBY,           # Waiting for players
	SPAWNING,        # Spawning players around the map
	MEETUP,          # Players must reach sigil within time limit
	WAVE_ACTIVE,     # Wave is in progress
	INTERMISSION,    # Between waves - shop time
	GAME_OVER        # Game ended
}

# Configuration
@export var meetup_time: float = 60.0  # Seconds to reach sigil
@export var late_penalty_damage: float = 10.0  # Damage per second if late
@export var starting_sigils: int = 500
@export var starting_points: int = 500

# Current state
var current_phase: GamePhase = GamePhase.LOBBY
var meetup_timer: float = 0.0
var players_at_sigil: Array[Node] = []
var all_players: Array[Node] = []
var current_wave: int = 0

# System references
var wave_manager: WaveManager = null
var sigil: Node = null
var loot_spawner: Node = null
var points_system: Node = null

# Player spawn points (scattered around map)
var player_spawn_points: Array[Node3D] = []

# Sigil center point
var sigil_position: Vector3 = Vector3.ZERO

func _ready():
	add_to_group("game_coordinator")

	# Find/create required systems
	await get_tree().create_timer(0.2).timeout
	_initialize_systems()

	# Start game after a short delay
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	start_game()

func _initialize_systems():
	# Find or create WaveManager
	wave_manager = get_tree().get_first_node_in_group("wave_manager")
	if not wave_manager:
		wave_manager = get_node_or_null("/root/WaveManager")
	if not wave_manager:
		wave_manager = WaveManager.new()
		wave_manager.name = "WaveManager"
		add_child(wave_manager)

	# Connect wave manager signals
	if wave_manager:
		if not wave_manager.wave_started.is_connected(_on_wave_started):
			wave_manager.wave_started.connect(_on_wave_started)
		if not wave_manager.wave_completed.is_connected(_on_wave_completed):
			wave_manager.wave_completed.connect(_on_wave_completed)
		if not wave_manager.intermission_started.is_connected(_on_intermission_started):
			wave_manager.intermission_started.connect(_on_intermission_started)

	# Find sigil
	sigil = get_tree().get_first_node_in_group("sigil")
	if sigil:
		sigil_position = sigil.global_position
		# Connect sigil signals
		if sigil.has_signal("player_entered_zone"):
			sigil.player_entered_zone.connect(_on_player_entered_sigil)
		if sigil.has_signal("player_exited_zone"):
			sigil.player_exited_zone.connect(_on_player_exited_sigil)

	# Find loot spawner
	loot_spawner = get_tree().get_first_node_in_group("loot_spawner")
	if not loot_spawner:
		loot_spawner = get_node_or_null("/root/LootSpawner")

	# Find points system
	points_system = get_node_or_null("/root/PointsSystem")

	# Collect player spawn points
	_collect_player_spawn_points()

func _collect_player_spawn_points():
	player_spawn_points.clear()

	# Find spawn points in the scene
	var spawns = get_tree().get_nodes_in_group("player_spawn")
	for spawn in spawns:
		if spawn is Node3D:
			player_spawn_points.append(spawn)

	# If no spawn points found, create default ones around map center
	if player_spawn_points.is_empty():
		_create_default_spawn_points()

func _create_default_spawn_points():
	# Create spawn points in a circle around the sigil
	var spawn_distance = 50.0  # Distance from sigil
	var spawn_count = 8

	for i in range(spawn_count):
		var angle = (float(i) / spawn_count) * TAU
		var spawn_marker = Marker3D.new()
		spawn_marker.position = sigil_position + Vector3(
			cos(angle) * spawn_distance,
			0,
			sin(angle) * spawn_distance
		)
		spawn_marker.add_to_group("player_spawn")
		add_child(spawn_marker)
		player_spawn_points.append(spawn_marker)

	print("Created %d default player spawn points" % spawn_count)

func _process(delta):
	match current_phase:
		GamePhase.MEETUP:
			_update_meetup_phase(delta)
		GamePhase.WAVE_ACTIVE:
			_update_wave_phase(delta)

func _update_meetup_phase(delta):
	meetup_timer -= delta
	meetup_timer_updated.emit(meetup_timer)

	# Check if all players are at sigil
	if _are_all_players_at_sigil():
		_start_wave_phase()
		return

	# Timer expired
	if meetup_timer <= 0:
		# Apply penalty to players not at sigil and force start
		_penalize_late_players()
		_start_wave_phase()

func _update_wave_phase(_delta):
	# Wave manager handles this
	pass

func _are_all_players_at_sigil() -> bool:
	if all_players.is_empty():
		return false
	for player in all_players:
		if is_instance_valid(player) and player not in players_at_sigil:
			return false
	return true

func _penalize_late_players():
	for player in all_players:
		if is_instance_valid(player) and player not in players_at_sigil:
			# Deal damage to late players
			if player.has_method("take_damage"):
				player.take_damage(late_penalty_damage * 5, Vector3.ZERO)

			# Notify via chat
			if has_node("/root/ChatSystem"):
				get_node("/root/ChatSystem").emit_system_message(
					"%s didn't reach the sigil in time! -50 HP" % _get_player_name(player)
				)

func _get_player_name(player: Node) -> String:
	if "player_name" in player:
		return player.player_name
	return "Player"

# ============================================
# GAME FLOW
# ============================================

func start_game():
	print("Game Coordinator: Starting game")

	# Find all players
	all_players.clear()
	all_players.append_array(get_tree().get_nodes_in_group("player"))

	if all_players.is_empty():
		# Wait for player to spawn
		await get_tree().create_timer(2.0).timeout
		all_players.append_array(get_tree().get_nodes_in_group("player"))

	# Initialize players with starting resources
	for player in all_players:
		_initialize_player(player)

	# Spawn loot around the map
	if loot_spawner and loot_spawner.has_method("spawn_initial_loot"):
		loot_spawner.spawn_initial_loot()

	# Start the meetup phase
	_start_meetup_phase()

	game_started.emit()

func _initialize_player(player: Node):
	if not is_instance_valid(player):
		return

	# Give starting sigils
	if player.has_node("SigilShop"):
		var shop = player.get_node("SigilShop")
		shop.add_sigils(starting_sigils, "Starting bonus")
	elif has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		persistence.add_currency("sigils", starting_sigils)

	# Give starting points
	if points_system:
		points_system.add_points(starting_points)

func _start_meetup_phase():
	current_phase = GamePhase.MEETUP
	meetup_timer = meetup_time
	players_at_sigil.clear()

	game_phase_changed.emit(current_phase)

	# Notify players
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message(
			"Get to the Sigil within %d seconds! The wave will start when everyone arrives." % int(meetup_time)
		)

	# Update HUD
	_update_hud_phase("REACH THE SIGIL", meetup_time)

	print("Meetup phase started - %d seconds to reach sigil" % int(meetup_time))

func _start_wave_phase():
	current_phase = GamePhase.WAVE_ACTIVE
	current_wave += 1

	game_phase_changed.emit(current_phase)

	# Start the wave via wave manager
	if wave_manager:
		# Don't use wave_manager's built-in start, we control timing
		wave_manager.start_next_wave()

	# Spawn wave loot
	if loot_spawner and loot_spawner.has_method("spawn_wave_loot"):
		loot_spawner.spawn_wave_loot(current_wave)

	# Update HUD
	_update_hud_phase("WAVE %d" % current_wave, 0)

	print("Wave %d started!" % current_wave)

func _start_intermission_phase(duration: float):
	current_phase = GamePhase.INTERMISSION

	game_phase_changed.emit(current_phase)

	# Update HUD
	_update_hud_phase("INTERMISSION", duration)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message(
			"Wave complete! You have %d seconds to prepare. Visit the Sigil to shop!" % int(duration)
		)

func _update_hud_phase(phase_name: String, timer: float):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_phase"):
		hud.update_phase(phase_name, timer)

# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_player_entered_sigil(player: Node):
	if player not in players_at_sigil:
		players_at_sigil.append(player)

		if has_node("/root/ChatSystem"):
			get_node("/root/ChatSystem").emit_system_message(
				"%s reached the Sigil! (%d/%d)" % [_get_player_name(player), players_at_sigil.size(), all_players.size()]
			)

		# Check if all players are ready
		if _are_all_players_at_sigil() and current_phase == GamePhase.MEETUP:
			all_players_ready.emit()
			# Short delay before starting wave
			await get_tree().create_timer(2.0).timeout
			if is_instance_valid(self) and current_phase == GamePhase.MEETUP:
				_start_wave_phase()

func _on_player_exited_sigil(player: Node):
	players_at_sigil.erase(player)

func _on_wave_started(wave_number: int, zombie_count: int):
	current_wave = wave_number
	_update_hud_phase("WAVE %d - %d zombies" % [wave_number, zombie_count], 0)

func _on_wave_completed(wave_number: int):
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message(
			"Wave %d complete!" % wave_number
		)

	# Award wave completion bonuses
	_award_wave_completion_bonus(wave_number)

func _on_intermission_started(duration: float):
	_start_intermission_phase(duration)

	# After intermission, start meetup phase again
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self) and current_phase == GamePhase.INTERMISSION:
		_start_meetup_phase()

func _award_wave_completion_bonus(wave_number: int):
	var sigil_bonus = 50 + (wave_number * 25)
	var point_bonus = 250 + (wave_number * 50)

	# Award to all players at sigil
	for player in all_players:
		if not is_instance_valid(player):
			continue

		# Sigils
		if player.has_node("SigilShop"):
			player.get_node("SigilShop").add_sigils(sigil_bonus, "Wave %d complete" % wave_number)
		elif has_node("/root/PlayerPersistence"):
			get_node("/root/PlayerPersistence").add_currency("sigils", sigil_bonus)

		# Experience
		if "character_attributes" in player and player.character_attributes:
			player.character_attributes.add_experience(100 * wave_number)

	# Points
	if points_system:
		points_system.add_points(point_bonus)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message(
			"+%d Sigils, +%d Points for completing Wave %d!" % [sigil_bonus, point_bonus, wave_number]
		)

# ============================================
# PLAYER SPAWNING
# ============================================

func spawn_player_at_random_point(player: Node):
	"""Spawn a player at a random spawn point away from the sigil"""
	if player_spawn_points.is_empty():
		push_warning("No spawn points available!")
		return

	var spawn_point = player_spawn_points[randi() % player_spawn_points.size()]
	player.global_position = spawn_point.global_position

	print("Spawned player at %s" % spawn_point.global_position)

func get_random_spawn_point() -> Vector3:
	"""Get a random spawn point position"""
	if player_spawn_points.is_empty():
		return sigil_position + Vector3(50, 0, 0)

	var spawn_point = player_spawn_points[randi() % player_spawn_points.size()]
	return spawn_point.global_position

# ============================================
# GAME STATE
# ============================================

func get_current_phase() -> GamePhase:
	return current_phase

func get_phase_name() -> String:
	match current_phase:
		GamePhase.LOBBY: return "Lobby"
		GamePhase.SPAWNING: return "Spawning"
		GamePhase.MEETUP: return "Meetup"
		GamePhase.WAVE_ACTIVE: return "Wave Active"
		GamePhase.INTERMISSION: return "Intermission"
		GamePhase.GAME_OVER: return "Game Over"
	return "Unknown"

func get_meetup_time_remaining() -> float:
	return meetup_timer if current_phase == GamePhase.MEETUP else 0.0

func is_wave_active() -> bool:
	return current_phase == GamePhase.WAVE_ACTIVE

func end_game(victory: bool):
	current_phase = GamePhase.GAME_OVER
	game_phase_changed.emit(current_phase)
	game_over.emit(victory)

	if has_node("/root/ChatSystem"):
		var msg = "Victory! All waves completed!" if victory else "Game Over - The sigil was destroyed!"
		get_node("/root/ChatSystem").emit_system_message(msg)
