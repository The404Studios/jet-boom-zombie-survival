extends RigidBody3D
class_name DestructibleProp

## Destructible prop that can be damaged and destroyed
## Optionally drops items when destroyed

signal damaged(current_health: float, max_health: float)
signal destroyed(position: Vector3)

@export var max_health: float = 100.0
@export var drop_items: bool = true
@export var item_drop_chance: float = 0.4

var current_health: float
var is_destroyed: bool = false

@onready var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")

func _ready():
	current_health = max_health
	add_to_group("props")
	add_to_group("destructible")
	add_to_group("zombie_targets")

func take_damage(amount: float, _source: Node = null):
	if is_destroyed:
		return

	current_health = max(0, current_health - amount)
	damaged.emit(current_health, max_health)

	_show_damage_effect()

	if current_health <= 0:
		_destroy()

func _show_damage_effect():
	if not mesh:
		return

	# Flash red
	var mat = mesh.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		var original_color = mat.albedo_color
		mat.albedo_color = Color(1.0, 0.3, 0.3)

		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(mesh) and not is_destroyed:
			mat.albedo_color = original_color

func _destroy():
	is_destroyed = true
	destroyed.emit(global_position)

	# Spawn debris/particles
	_spawn_destruction_effect()

	# Drop items
	if drop_items and randf() < item_drop_chance:
		_drop_loot()

	# Play sound
	var audio = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sound_3d"):
		audio.play_sound_3d("wood_break", global_position, 0.7)

	# Remove after short delay
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _spawn_destruction_effect():
	# Create debris particles
	var particles = GPUParticles3D.new()
	particles.global_position = global_position
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 30
	particles.lifetime = 1.0
	particles.explosiveness = 1.0

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, -10, 0)
	material.scale_min = 0.1
	material.scale_max = 0.3
	material.color = Color(0.55, 0.4, 0.25)
	particles.process_material = material

	# Use simple box mesh for debris
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.55, 0.4, 0.25)
	var box = BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.1)
	box.material = mesh_mat
	particles.draw_pass_1 = box

	get_tree().current_scene.add_child(particles)

	# Auto cleanup
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func _drop_loot():
	var loot_spawner = get_node_or_null("/root/LootSpawner")
	if loot_spawner and loot_spawner.has_method("spawn_random_loot"):
		loot_spawner.spawn_random_loot(global_position + Vector3.UP * 0.5)
	else:
		# Fallback: try to spawn ammo or health
		var survival_system = get_node_or_null("/root/SurvivalSystem")
		if survival_system and survival_system.has_method("spawn_random_pickup"):
			survival_system.spawn_random_pickup(global_position + Vector3.UP * 0.5)

func get_health_percent() -> float:
	return current_health / max_health if max_health > 0 else 0.0
