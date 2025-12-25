extends Node3D

# Arena manager - handles wave spawning, game loop, and arena events
# Integrates all systems for complete gameplay
# Now works with GameCoordinator for phase management

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal all_zombies_defeated
signal player_died
signal zombie_killed(zombie: Node, points: int, xp: int)

# Wave system
var current_wave: int = 0
var zombies_alive: int = 0
var zombies_to_spawn: int = 0
var wave_active: bool = false
var intermission_time: float = 30.0
var intermission_timer: float = 0.0

# Spawn points
var spawn_points: Array = []
var player_spawn_points: Array = []
var loot_spawn_points: Array = []
var spawn_timer: float = 0.0
var spawn_interval: float = 2.0

# Zombie scenes
var zombie_scenes: Dictionary = {}

# Player reference
var player: Node = null

# Points
var player_points: int = 500  # Starting points

# System references
var game_coordinator: GameCoordinator = null
var loot_spawner: LootSpawner = null
var wave_manager: Node = null

func _ready():
	# Add to arena_manager group so other systems can find us
	add_to_group("arena_manager")

	# Rebake navigation mesh on startup
	_bake_navigation_mesh()

	# Find spawn points
	_collect_spawn_points()
	_collect_player_spawn_points()
	_collect_loot_spawn_points()

	# Load zombie scenes
	_load_zombie_scenes()

	# Find player
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	# Notify network manager that we've loaded
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and multiplayer.has_multiplayer_peer():
		network_manager.notify_player_loaded.rpc_id(1)

	# Initialize core systems
	await get_tree().create_timer(0.5).timeout
	_initialize_systems()

	# Wait for player to be ready
	await get_tree().create_timer(0.5).timeout

	# Let game coordinator handle game start
	# If no coordinator, start directly
	if not game_coordinator:
		if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
			start_wave()

func _initialize_systems():
	# Create game coordinator if not present
	game_coordinator = get_tree().get_first_node_in_group("game_coordinator")
	if not game_coordinator:
		game_coordinator = GameCoordinator.new()
		game_coordinator.name = "GameCoordinator"
		add_child(game_coordinator)

	# Create loot spawner if not present
	loot_spawner = get_tree().get_first_node_in_group("loot_spawner")
	if not loot_spawner:
		loot_spawner = LootSpawner.new()
		loot_spawner.name = "LootSpawner"
		add_child(loot_spawner)

	# Find wave manager
	wave_manager = get_tree().get_first_node_in_group("wave_manager")

func _process(delta):
	if wave_active:
		_update_wave_spawning(delta)

	if intermission_timer > 0:
		intermission_timer -= delta

		if intermission_timer <= 0:
			start_wave()

func _bake_navigation_mesh():
	"""Bake navigation mesh to ensure zombies can navigate properly"""
	var nav_region = get_node_or_null("NavigationRegion3D")
	if nav_region and nav_region is NavigationRegion3D:
		# Bake in background to not block game start
		nav_region.bake_navigation_mesh()
		print("Navigation mesh baked successfully")
	else:
		# Try to find navigation region in scene
		nav_region = get_tree().get_first_node_in_group("navigation_region")
		if nav_region and nav_region is NavigationRegion3D:
			nav_region.bake_navigation_mesh()
			print("Navigation mesh baked from group")
		else:
			push_warning("No NavigationRegion3D found - zombies may not navigate properly!")

func _collect_spawn_points():
	var spawns = get_node_or_null("SpawnPoints")
	if spawns:
		for child in spawns.get_children():
			if child is Marker3D:
				spawn_points.append(child)
	else:
		# Look for spawn points in groups
		spawn_points = get_tree().get_nodes_in_group("zombie_spawn")

	# Create default spawn points if none found
	if spawn_points.is_empty():
		_create_default_zombie_spawns()

	print("Found %d zombie spawn points" % spawn_points.size())

func _collect_player_spawn_points():
	# Find player spawn points
	player_spawn_points = get_tree().get_nodes_in_group("player_spawn")

	var player_spawns = get_node_or_null("PlayerSpawnPoints")
	if player_spawns:
		for child in player_spawns.get_children():
			if child is Marker3D:
				player_spawn_points.append(child)

	# Create default player spawn points if none found
	if player_spawn_points.is_empty():
		_create_default_player_spawns()

	print("Found %d player spawn points" % player_spawn_points.size())

func _collect_loot_spawn_points():
	# Find loot spawn points
	loot_spawn_points = get_tree().get_nodes_in_group("loot_spawn")

	var loot_spawns = get_node_or_null("LootSpawnPoints")
	if loot_spawns:
		for child in loot_spawns.get_children():
			if child is Marker3D:
				loot_spawn_points.append(child)

	print("Found %d loot spawn points" % loot_spawn_points.size())

func _create_default_zombie_spawns():
	# Create spawn points around the perimeter
	var center = Vector3.ZERO
	var sigil = get_tree().get_first_node_in_group("sigil")
	if sigil:
		center = sigil.global_position

	var spawn_distance = 60.0
	var spawn_count = 8

	for i in range(spawn_count):
		var angle = (float(i) / spawn_count) * TAU
		var marker = Marker3D.new()
		marker.position = center + Vector3(cos(angle) * spawn_distance, 0, sin(angle) * spawn_distance)
		marker.add_to_group("zombie_spawn")
		add_child(marker)
		spawn_points.append(marker)

func _create_default_player_spawns():
	# Create player spawn points in a circle around the map edge
	var center = Vector3.ZERO
	var sigil = get_tree().get_first_node_in_group("sigil")
	if sigil:
		center = sigil.global_position

	var spawn_distance = 45.0  # Closer than zombie spawns, but still away from sigil
	var spawn_count = 8

	for i in range(spawn_count):
		var angle = (float(i) / spawn_count) * TAU + 0.2  # Offset from zombie spawns
		var marker = Marker3D.new()
		marker.position = center + Vector3(cos(angle) * spawn_distance, 0, sin(angle) * spawn_distance)
		marker.add_to_group("player_spawn")
		add_child(marker)
		player_spawn_points.append(marker)

func _load_zombie_scenes():
	zombie_scenes = {
		"shambler": load("res://scenes/zombies/zombie_shambler.tscn"),
		"runner": load("res://scenes/zombies/zombie_runner.tscn"),
		"tank": load("res://scenes/zombies/zombie_tank.tscn"),
		"monster": load("res://scenes/zombies/zombie_monster.tscn")
	}

# ============================================
# WAVE SYSTEM
# ============================================

func start_wave():
	current_wave += 1
	wave_active = true
	intermission_timer = 0.0

	# Calculate zombies for this wave
	zombies_to_spawn = 10 + (current_wave * 5)  # 15, 20, 25, 30...
	zombies_alive = 0

	# Notify systems
	wave_started.emit(current_wave)

	# Update sigil health for wave
	var sigils = get_tree().get_nodes_in_group("sigil")
	for sigil in sigils:
		if sigil.has_method("setup_for_wave"):
			sigil.setup_for_wave(current_wave)

	# Update prop health for wave
	var props = get_tree().get_nodes_in_group("props")
	for prop in props:
		if prop.has_method("setup_for_wave"):
			prop.setup_for_wave(current_wave)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Wave %d starting! %d zombies incoming!" % [current_wave, zombies_to_spawn])

	# Update HUD
	_update_hud()

	print("Wave %d started - %d zombies" % [current_wave, zombies_to_spawn])

func _update_wave_spawning(delta):
	if zombies_to_spawn <= 0:
		# All zombies spawned, wait for them to die
		if zombies_alive <= 0:
			_complete_wave()
		return

	spawn_timer -= delta

	if spawn_timer <= 0:
		_spawn_zombie()
		spawn_timer = spawn_interval

func _spawn_zombie():
	if spawn_points.is_empty():
		return

	# Choose zombie type based on wave
	var zombie_type = _get_zombie_type_for_wave()

	# Get random spawn point
	var spawn_point = spawn_points[randi() % spawn_points.size()]
	var spawn_pos = spawn_point.global_position

	# Spawn zombie
	var zombie_scene = zombie_scenes.get(zombie_type)
	if zombie_scene:
		var zombie = zombie_scene.instantiate()
		add_child(zombie)
		zombie.global_position = spawn_pos

		# Connect death signal
		if zombie.has_signal("zombie_died"):
			zombie.zombie_died.connect(_on_zombie_died)

		zombies_alive += 1
		zombies_to_spawn -= 1

		_update_hud()

func _get_zombie_type_for_wave() -> String:
	# Weighted selection based on wave
	var roll = randf()

	if current_wave >= 10:
		# Boss wave
		if roll < 0.1:
			return "monster"

	if current_wave >= 7:
		if roll < 0.3:
			return "tank"

	if current_wave >= 4:
		if roll < 0.4:
			return "runner"

	return "shambler"

func _complete_wave():
	wave_active = false

	# Award wave completion points
	var wave_bonus = 100 * current_wave
	player_points += wave_bonus

	# Notify
	wave_completed.emit(current_wave)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Wave %d complete! +%d points. Next wave in %d seconds." % [current_wave, wave_bonus, int(intermission_time)])

	# Start intermission
	intermission_timer = intermission_time

	_update_hud()

	print("Wave %d completed!" % current_wave)

func _on_zombie_died(zombie: Node, points: int, experience: int):
	zombies_alive -= 1

	# Award points
	player_points += points

	_update_hud()

	# Emit signal for other systems
	zombie_killed.emit(zombie, points, experience)

	# Spawn loot from zombie
	if loot_spawner and loot_spawner.has_method("spawn_zombie_drop"):
		var zombie_type = "shambler"
		if "zombie_type" in zombie:
			zombie_type = zombie.zombie_type
		elif "class_name" in zombie:
			zombie_type = zombie.class_name
		loot_spawner.spawn_zombie_drop(zombie.global_position, zombie_type)

	# Spawn gibs
	if has_node("/root/GoreSystem"):
		var gore = get_node("/root/GoreSystem")
		gore.spawn_gibs(zombie.global_position, Vector3(0, 2, 0), 5)

	# Award experience to player
	if player and "character_attributes" in player and player.character_attributes:
		player.character_attributes.add_experience(experience)

func add_player_points(player_id: int, amount: int):
	"""Add points to a specific player (for multiplayer support)"""
	# In singleplayer, just add to the main points pool
	# In multiplayer, would track per-player points
	if not multiplayer.has_multiplayer_peer():
		player_points += amount
	else:
		# Track per-player points if needed in multiplayer
		player_points += amount

	_update_hud()

	# Sync points in multiplayer
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_player_points.rpc(player_points)

@rpc("authority", "call_local")
func sync_player_points(points: int):
	player_points = points
	_update_hud()

# ============================================
# UI UPDATES
# ============================================

func _update_hud():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_wave_info"):
		hud.update_wave_info(current_wave, zombies_alive, zombies_to_spawn + zombies_alive)

	if hud and hud.has_method("update_points"):
		hud.update_points(player_points)

# ============================================
# ITEM SPAWNING
# ============================================

func spawn_ammo_pickup(position: Vector3):
	# Create ammo pickup
	var ammo = preload("res://scenes/items/ammo_pickup.tscn").instantiate()
	add_child(ammo)
	ammo.global_position = position

func spawn_health_pickup(position: Vector3):
	# Create health pickup
	var health = preload("res://scenes/items/health_pickup.tscn").instantiate()
	add_child(health)
	health.global_position = position

func spawn_weapon_pickup(weapon_name: String, position: Vector3):
	# Create weapon pickup
	var weapon = preload("res://scenes/items/weapon_pickup.tscn").instantiate()
	add_child(weapon)
	weapon.global_position = position
	weapon.weapon_name = weapon_name

# ============================================
# NETWORK SYNC
# ============================================

@rpc("authority", "call_local")
func sync_wave_state(wave: int, alive: int, to_spawn: int, active: bool):
	current_wave = wave
	zombies_alive = alive
	zombies_to_spawn = to_spawn
	wave_active = active
	_update_hud()

func _physics_process(_delta):
	# Sync wave state for clients (if server)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and get_tree().get_frame() % 60 == 0:
		sync_wave_state.rpc(current_wave, zombies_alive, zombies_to_spawn, wave_active)
