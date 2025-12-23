extends Node3D
class_name PropSpawner

@export var prop_scenes: Array[PackedScene] = []
@export var spawn_count: int = 50
@export var spawn_radius: float = 50.0
@export var min_distance_from_center: float = 10.0

func _ready():
	spawn_props()

func spawn_props():
	for i in range(spawn_count):
		if prop_scenes.is_empty():
			return

		var random_prop = prop_scenes[randi() % prop_scenes.size()]
		if not random_prop:
			continue

		var prop_instance = random_prop.instantiate()
		add_child(prop_instance)

		# Random position in radius
		var angle = randf() * TAU
		var distance = randf_range(min_distance_from_center, spawn_radius)
		var x = cos(angle) * distance
		var z = sin(angle) * distance

		prop_instance.global_position = Vector3(x, 0, z)

		# Random rotation
		prop_instance.rotation.y = randf() * TAU

		# Random scale variation
		var scale_variation = randf_range(0.8, 1.2)
		prop_instance.scale *= scale_variation
