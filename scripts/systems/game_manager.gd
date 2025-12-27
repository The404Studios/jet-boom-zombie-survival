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

func _ready():
	# Load zombie scene if not set (autoloads can't use @export properly)
	if not zombie_scene:
		zombie_scene = load("res://scenes/zombies/zombie.tscn")
		if zombie_scene:
			print("[GameManager] Loaded zombie scene: ", zombie_scene.resource_path)
		else:
			push_error("[GameManager] Failed to load zombie scene!")

	# Emit game started signal
	game_started.emit()

	# Wait for scene to be ready and spawn points to be added
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Wait for spawn points (main_scene.gd sets them)
	var wait_time = 0.0
	while zombie_spawn_points.is_empty() and wait_time < 5.0:
		await get_tree().create_timer(0.5).timeout
		wait_time += 0.5
		if not is_instance_valid(self) or not is_inside_tree():
			return

	if zombie_spawn_points.is_empty():
		push_warning("[GameManager] No spawn points after waiting! Zombies won't spawn.")
		return

	print("[GameManager] Ready with %d spawn points" % zombie_spawn_points.size())

	# Start first wave after additional delay
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	start_next_wave()

func _process(delta):
	if not is_wave_active:
		wave_timer -= delta
		if wave_timer <= 0:
			start_next_wave()

func start_next_wave():
	current_wave += 1
	is_wave_active = true
	wave_started.emit(current_wave)

	var zombies_to_spawn = zombies_per_wave + (current_wave - 1) * 2
	spawn_wave(zombies_to_spawn)

func spawn_wave(count: int):
	for i in range(count):
		await get_tree().create_timer(2.0).timeout  # Stagger spawns
		if not is_instance_valid(self) or not is_inside_tree():
			return
		spawn_zombie()

func spawn_zombie():
	if not zombie_scene:
		push_error("[GameManager] No zombie scene set!")
		return
	if zombie_spawn_points.is_empty():
		push_error("[GameManager] No spawn points set!")
		return

	if zombies_alive >= max_zombies_alive:
		print("[GameManager] Max zombies reached (%d/%d)" % [zombies_alive, max_zombies_alive])
		return

	# Get valid spawn point
	var spawn_point = zombie_spawn_points[randi() % zombie_spawn_points.size()]
	if not is_instance_valid(spawn_point):
		push_warning("[GameManager] Invalid spawn point!")
		return

	# Instantiate zombie
	var zombie = zombie_scene.instantiate()
	if not zombie:
		push_error("[GameManager] Failed to instantiate zombie!")
		return

	# Add to scene
	var scene = get_tree().current_scene
	if not scene:
		zombie.queue_free()
		push_error("[GameManager] No current scene!")
		return

	scene.add_child(zombie)
	zombie.global_position = spawn_point.global_position + Vector3(0, 0.5, 0)

	# Ensure zombie is in correct group
	if not zombie.is_in_group("zombie"):
		zombie.add_to_group("zombie")

	# Connect zombie died signal if it exists
	if zombie.has_signal("zombie_died"):
		zombie.zombie_died.connect(_on_zombie_died)

	zombies_alive += 1
	zombie_spawned.emit(zombie)
	print("[GameManager] Spawned zombie #%d at %v (Wave %d)" % [zombies_alive, spawn_point.global_position, current_wave])

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
