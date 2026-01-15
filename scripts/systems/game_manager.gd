extends Node
# Note: Do not use class_name here - this script is an autoload singleton
# Access via: GameManager (the autoload name)

@export var zombie_spawn_points: Array[Node3D] = []
@export var zombie_scene: PackedScene
@export var zombies_per_wave: int = 5
@export var wave_delay: float = 30.0
@export var max_zombies_alive: int = 20

var current_wave: int = 0
var zombies_alive: int = 0
var zombies_killed: int = 0
var is_wave_active: bool = false
var wave_timer: float = 0.0

# Zombie scenes by type
var zombie_scenes: Dictionary = {
	"normal": preload("res://scenes/zombies/zombie.tscn") if ResourceLoader.exists("res://scenes/zombies/zombie.tscn") else null,
	"fast": preload("res://scenes/zombies/zombie_runner.tscn") if ResourceLoader.exists("res://scenes/zombies/zombie_runner.tscn") else null,
	"tank": preload("res://scenes/zombies/zombie_tank.tscn") if ResourceLoader.exists("res://scenes/zombies/zombie_tank.tscn") else null,
	"spitter": preload("res://scenes/zombies/zombie_spitter.tscn") if ResourceLoader.exists("res://scenes/zombies/zombie_spitter.tscn") else null,
	"exploder": preload("res://scenes/zombies/zombie_exploder.tscn") if ResourceLoader.exists("res://scenes/zombies/zombie_exploder.tscn") else null,
	"elite": preload("res://scenes/zombies/zombie_berserker.tscn") if ResourceLoader.exists("res://scenes/zombies/zombie_berserker.tscn") else null,
	"boss": preload("res://scenes/zombies/zombie_monster.tscn") if ResourceLoader.exists("res://scenes/zombies/zombie_monster.tscn") else null
}

@warning_ignore("unused_signal")
signal wave_started(wave_number: int)
@warning_ignore("unused_signal")
signal wave_completed(wave_number: int)
@warning_ignore("unused_signal")
signal zombie_spawned(zombie: Node)
@warning_ignore("unused_signal")
signal game_started
@warning_ignore("unused_signal")
signal game_over(victory: bool)
@warning_ignore("unused_signal")
signal extraction_available(wave: int)
@warning_ignore("unused_signal")
signal boss_wave_started(boss_name: String)

func _ready():
	# Emit game started signal
	game_started.emit()

	# Connect to SigilDefenseSystem signals
	var sigil_defense = get_node_or_null("/root/SigilDefenseSystem")
	if sigil_defense:
		sigil_defense.sigil_destroyed.connect(_on_sigil_destroyed)
		sigil_defense.extraction_available.connect(_on_extraction_available)
		sigil_defense.final_extraction_complete.connect(_on_final_extraction)

	# Connect to WaveLootSystem signals
	var wave_loot = get_node_or_null("/root/WaveLootSystem")
	if wave_loot:
		wave_loot.boss_spawned.connect(_on_boss_announced)

	# Auto-find spawn points if not set
	if zombie_spawn_points.is_empty():
		_find_spawn_points()

	# Start first wave after delay
	await get_tree().create_timer(5.0).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	start_next_wave()

func _find_spawn_points():
	"""Automatically find zombie spawn points in the scene"""
	# Look for nodes in zombie_spawn group
	var group_spawns = get_tree().get_nodes_in_group("zombie_spawn")
	for spawn in group_spawns:
		if spawn is Node3D:
			zombie_spawn_points.append(spawn)

	# If still empty, look for ZombieSpawnPoints container
	if zombie_spawn_points.is_empty():
		var scene = get_tree().current_scene
		if scene and scene.has_node("ZombieSpawnPoints"):
			var spawn_container = scene.get_node("ZombieSpawnPoints")
			for child in spawn_container.get_children():
				if child is Marker3D or child is Node3D:
					zombie_spawn_points.append(child)

	# If still empty, create some default spawn points around the arena
	if zombie_spawn_points.is_empty():
		print("Warning: No zombie spawn points found. Creating defaults.")
		var spawn_positions = [
			Vector3(30, 0, 30),
			Vector3(-30, 0, 30),
			Vector3(30, 0, -30),
			Vector3(-30, 0, -30),
			Vector3(40, 0, 0),
			Vector3(-40, 0, 0),
			Vector3(0, 0, 40),
			Vector3(0, 0, -40)
		]
		for pos in spawn_positions:
			var marker = Marker3D.new()
			marker.global_position = pos
			add_child(marker)
			zombie_spawn_points.append(marker)

	print("Found %d zombie spawn points" % zombie_spawn_points.size())

func _process(delta):
	if not is_wave_active:
		wave_timer -= delta
		if wave_timer <= 0:
			start_next_wave()

func start_next_wave():
	current_wave += 1
	is_wave_active = true
	wave_started.emit(current_wave)

	# Use WaveLootSystem for spawn configuration if available
	var wave_loot = get_node_or_null("/root/WaveLootSystem")
	if wave_loot:
		var difficulty = wave_loot.start_wave(current_wave)
		var spawn_config = wave_loot.get_spawn_configuration(current_wave)
		spawn_wave_advanced(spawn_config)

		# Update SigilDefenseSystem
		var sigil_defense = get_node_or_null("/root/SigilDefenseSystem")
		if sigil_defense:
			sigil_defense.start_round(current_wave)
	else:
		# Fallback to simple spawning
		var zombies_to_spawn = zombies_per_wave + (current_wave - 1) * 2
		spawn_wave(zombies_to_spawn)

func spawn_wave_advanced(spawn_config: Array):
	"""Spawn zombies based on WaveLootSystem configuration"""
	for config in spawn_config:
		var zombie_type = config.get("type", 0)
		var count = config.get("count", 1)
		var health = config.get("health", 100.0)
		var damage = config.get("damage", 15.0)
		var speed = config.get("speed", 3.0)

		for i in range(count):
			await get_tree().create_timer(1.5).timeout
			if not is_instance_valid(self) or not is_inside_tree():
				return
			spawn_zombie_typed(zombie_type, health, damage, speed)

func spawn_zombie_typed(zombie_type: int, health: float, damage: float, speed: float):
	"""Spawn a specific type of zombie with scaled stats"""
	if zombie_spawn_points.is_empty():
		return

	if zombies_alive >= max_zombies_alive:
		return

	# Get appropriate scene for zombie type
	var scene_to_use = _get_zombie_scene_for_type(zombie_type)
	if not scene_to_use:
		scene_to_use = zombie_scene
	if not scene_to_use:
		return

	var spawn_point = zombie_spawn_points[randi() % zombie_spawn_points.size()]
	var zombie = scene_to_use.instantiate()
	if not zombie:
		return

	var scene = get_tree().current_scene
	if not scene:
		zombie.queue_free()
		return

	scene.add_child(zombie)
	zombie.global_position = spawn_point.global_position

	# Apply scaled stats
	if zombie.has_method("set") or "max_health" in zombie:
		zombie.max_health = health
		zombie.current_health = health
		zombie.attack_damage = damage
		zombie.move_speed = speed
		zombie.current_wave = current_wave

	# Connect zombie died signal if it exists
	if zombie.has_signal("zombie_died"):
		zombie.zombie_died.connect(_on_zombie_died)

	zombies_alive += 1
	zombie_spawned.emit(zombie)

func _get_zombie_scene_for_type(zombie_type: int) -> PackedScene:
	"""Map zombie type enum to scene"""
	match zombie_type:
		0: return zombie_scenes.get("normal")
		1: return zombie_scenes.get("fast")
		2: return zombie_scenes.get("tank")
		3: return zombie_scenes.get("spitter")
		4: return zombie_scenes.get("exploder")
		5: return zombie_scenes.get("elite")
		6, 7, 8: return zombie_scenes.get("boss")
		_: return zombie_scenes.get("normal")

func spawn_wave(count: int):
	for i in range(count):
		await get_tree().create_timer(2.0).timeout  # Stagger spawns
		if not is_instance_valid(self) or not is_inside_tree():
			return
		spawn_zombie()

func spawn_zombie():
	if not zombie_scene or zombie_spawn_points.is_empty():
		return

	if zombies_alive >= max_zombies_alive:
		return

	var spawn_point = zombie_spawn_points[randi() % zombie_spawn_points.size()]
	var zombie = zombie_scene.instantiate()
	if not zombie:
		return
	var scene = get_tree().current_scene
	if not scene:
		zombie.queue_free()
		return
	scene.add_child(zombie)
	zombie.global_position = spawn_point.global_position

	# Connect zombie died signal if it exists
	if zombie.has_signal("zombie_died"):
		zombie.zombie_died.connect(_on_zombie_died)

	zombies_alive += 1
	zombie_spawned.emit(zombie)

func _on_zombie_died(_zombie: Node, _points: int = 0, _experience: int = 0):
	zombies_alive -= 1
	zombies_killed += 1

	# Check if wave is complete
	if zombies_alive <= 0 and is_wave_active:
		complete_wave()

func complete_wave():
	is_wave_active = false
	wave_completed.emit(current_wave)
	wave_timer = wave_delay

	# Notify SigilDefenseSystem
	var sigil_defense = get_node_or_null("/root/SigilDefenseSystem")
	if sigil_defense:
		sigil_defense.complete_round()

	# Check WaveLootSystem for wave completion
	var wave_loot = get_node_or_null("/root/WaveLootSystem")
	if wave_loot and wave_loot.is_wave_complete():
		print("Wave %d complete! Total zombies killed: %d" % [current_wave, zombies_killed])

# ============================================
# SIGIL DEFENSE INTEGRATION
# ============================================

func _on_sigil_destroyed():
	"""Handle sigil destruction - game over"""
	game_over.emit(false)
	print("GAME OVER - Sigil destroyed!")

func _on_extraction_available(wave: int):
	"""Handle extraction availability"""
	extraction_available.emit(wave)
	print("Extraction available at wave %d!" % wave)

func _on_final_extraction():
	"""Handle final extraction completion - victory"""
	game_over.emit(true)
	print("VICTORY - Final extraction complete!")

func _on_boss_announced(boss_name: String, wave: int):
	"""Handle boss wave announcement"""
	boss_wave_started.emit(boss_name)
	print("BOSS WAVE %d: %s incoming!" % [wave, boss_name])

# ============================================
# NETWORK SYNC
# ============================================

@rpc("authority", "call_remote", "reliable")
func sync_wave_state(wave: int, active: bool, alive: int, killed: int):
	"""Sync wave state to clients"""
	current_wave = wave
	is_wave_active = active
	zombies_alive = alive
	zombies_killed = killed

func broadcast_wave_state():
	"""Server broadcasts wave state to all clients"""
	if multiplayer.is_server():
		sync_wave_state.rpc(current_wave, is_wave_active, zombies_alive, zombies_killed)
