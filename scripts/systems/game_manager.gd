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
	# Emit game started signal
	game_started.emit()

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

	var zombies_to_spawn = zombies_per_wave + (current_wave - 1) * 2
	spawn_wave(zombies_to_spawn)

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
