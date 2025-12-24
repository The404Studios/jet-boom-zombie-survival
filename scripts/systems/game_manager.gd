extends Node
class_name GameManager

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

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal zombie_spawned(zombie: Zombie)
signal game_started
signal game_over(victory: bool)

func _ready():
	# Emit game started signal
	game_started.emit()

	# Start first wave after delay
	await get_tree().create_timer(5.0).timeout
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
		spawn_zombie()

func spawn_zombie():
	if not zombie_scene or zombie_spawn_points.is_empty():
		return

	if zombies_alive >= max_zombies_alive:
		return

	var spawn_point = zombie_spawn_points[randi() % zombie_spawn_points.size()]
	var zombie = zombie_scene.instantiate()
	get_tree().current_scene.add_child(zombie)
	zombie.global_position = spawn_point.global_position
	zombie.zombie_died.connect(_on_zombie_died)

	zombies_alive += 1
	zombie_spawned.emit(zombie)

func _on_zombie_died(_zombie: Zombie):
	zombies_alive -= 1
	zombies_killed += 1

	# Check if wave is complete
	if zombies_alive <= 0 and is_wave_active:
		complete_wave()

func complete_wave():
	is_wave_active = false
	wave_completed.emit(current_wave)
	wave_timer = wave_delay
