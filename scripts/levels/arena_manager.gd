extends Node3D

# Arena manager - handles wave spawning, game loop, and arena events
# Integrates all systems for complete gameplay

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal all_zombies_defeated
signal player_died

# Wave system
var current_wave: int = 0
var zombies_alive: int = 0
var zombies_to_spawn: int = 0
var wave_active: bool = false
var intermission_time: float = 30.0
var intermission_timer: float = 0.0

# Spawn points
var spawn_points: Array = []
var spawn_timer: float = 0.0
var spawn_interval: float = 2.0

# Zombie scenes
var zombie_scenes: Dictionary = {}

# Player reference
var player: Node = null

# Points
var player_points: int = 500  # Starting points

func _ready():
	# Find spawn points
	_collect_spawn_points()

	# Load zombie scenes
	_load_zombie_scenes()

	# Find player
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	# Wait for player to be ready
	await get_tree().create_timer(1.0).timeout

	# Start first wave
	start_wave()

func _process(delta):
	if wave_active:
		_update_wave_spawning(delta)

	if intermission_timer > 0:
		intermission_timer -= delta

		if intermission_timer <= 0:
			start_wave()

func _collect_spawn_points():
	var spawns = get_node("SpawnPoints")
	if spawns:
		for child in spawns.get_children():
			if child is Marker3D:
				spawn_points.append(child)

	print("Found %d spawn points" % spawn_points.size())

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

func _on_zombie_died(zombie: Node, points: int, _experience: int):
	zombies_alive -= 1

	# Award points
	player_points += points

	_update_hud()

	# Spawn gibs
	if has_node("/root/GoreSystem"):
		var gore = get_node("/root/GoreSystem")
		gore.spawn_gibs(zombie.global_position, Vector3(0, 2, 0), 5)

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
	if multiplayer.is_server() and get_tree().get_frame() % 60 == 0:
		sync_wave_state.rpc(current_wave, zombies_alive, zombies_to_spawn, wave_active)
