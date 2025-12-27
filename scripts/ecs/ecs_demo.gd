## ECSDemo - Demonstration script showing how to use the ECS system
## Attach this to a Node3D in your scene to test the ECS
extends Node3D

## Reference to ECS Manager (autoload)
@onready var ecs: Node = get_node("/root/ECSManager")

## Spawn points for zombies
@export var zombie_spawn_points: Array[Node3D] = []

## Player spawn point
@export var player_spawn_point: Node3D = null

## Demo settings
@export var spawn_player: bool = true
@export var spawn_test_zombies: bool = true
@export var test_zombie_count: int = 5


func _ready() -> void:
	# Wait for ECS to initialize
	await get_tree().process_frame

	if not ecs:
		push_error("[ECSDemo] ECSManager not found!")
		return

	print("[ECSDemo] Starting ECS demonstration...")

	# Spawn player
	if spawn_player:
		_spawn_player()

	# Spawn test zombies
	if spawn_test_zombies:
		_spawn_test_zombies()

	# Setup input handling
	set_process_unhandled_input(true)


## Spawn the player entity
func _spawn_player() -> void:
	var spawn_pos := Vector3.ZERO
	if player_spawn_point:
		spawn_pos = player_spawn_point.global_position
	else:
		spawn_pos = global_position

	var config := {
		"walk_speed": 5.0,
		"sprint_speed": 8.0,
		"jump_velocity": 6.0,
		"max_health": 100.0,
		"max_stamina": 100.0,
		# Use a character model if available
		"model_path": ecs.model_registry.get_player_model()
	}

	var player := ecs.create_player(spawn_pos, config)

	# Connect player health for HUD updates
	var health := player.get_component("Health") as HealthComponent
	if health:
		health.health_changed.connect(_on_player_health_changed)
		health.died.connect(_on_player_died)

	print("[ECSDemo] Player spawned at %s" % spawn_pos)


## Spawn test zombies
func _spawn_test_zombies() -> void:
	var zombie_types := ["shambler", "runner", "tank"]

	for i in range(test_zombie_count):
		var spawn_pos := Vector3.ZERO

		if not zombie_spawn_points.is_empty():
			spawn_pos = zombie_spawn_points[i % zombie_spawn_points.size()].global_position
		else:
			# Random position in a circle around origin
			var angle := (float(i) / test_zombie_count) * TAU
			var radius := 10.0
			spawn_pos = Vector3(
				cos(angle) * radius,
				0,
				sin(angle) * radius
			)

		var zombie_type: String = zombie_types[i % zombie_types.size()]
		ecs.create_zombie(spawn_pos, zombie_type)

	print("[ECSDemo] Spawned %d test zombies" % test_zombie_count)


func _unhandled_input(event: InputEvent) -> void:
	# Demo key bindings
	if event.is_action_pressed("ui_home"):
		# Spawn a zombie at random position
		var pos := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		ecs.create_zombie(pos, "shambler")
		print("[ECSDemo] Spawned shambler at %s" % pos)

	elif event.is_action_pressed("ui_end"):
		# Kill all zombies
		ecs.kill_all_zombies()
		print("[ECSDemo] Killed all zombies")

	elif event.is_action_pressed("ui_page_up"):
		# Spawn wave of zombies
		var wave_size := 10
		for i in range(wave_size):
			var pos := Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
			var types := ["shambler", "runner", "poison"]
			ecs.create_zombie(pos, types[i % types.size()])
		print("[ECSDemo] Spawned wave of %d zombies" % wave_size)

	elif event.is_action_pressed("ui_page_down"):
		# Heal player
		var player := ecs.get_player()
		if player:
			ecs.heal_entity(player, 50.0)
			print("[ECSDemo] Healed player for 50 HP")


## Player health changed callback
func _on_player_health_changed(current: float, maximum: float) -> void:
	print("[ECSDemo] Player health: %.1f / %.1f" % [current, maximum])


## Player died callback
func _on_player_died(_killer: Entity) -> void:
	print("[ECSDemo] Player died!")
	# Could trigger game over UI here


## Get zombie statistics
func get_stats() -> Dictionary:
	return {
		"total_zombies": ecs.get_zombie_count(),
		"alive_zombies": ecs.get_alive_zombie_count(),
		"player_health": ecs.get_player_health_percent() * 100,
		"player_position": ecs.get_player_position()
	}


## Print current statistics
func print_stats() -> void:
	var stats := get_stats()
	print("[ECSDemo] Stats:")
	print("  Total Zombies: %d" % stats["total_zombies"])
	print("  Alive Zombies: %d" % stats["alive_zombies"])
	print("  Player Health: %.1f%%" % stats["player_health"])
	print("  Player Position: %s" % stats["player_position"])
