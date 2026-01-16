extends Node3D
class_name DefenseSigil

## Simple Sigil for arena defense mode
## Players must protect this sigil from zombie attacks

signal sigil_damaged(damage: float, current_health: float)
signal sigil_destroyed
signal sigil_repaired(amount: float)

@export var sigil_name: String = "Defense Sigil"
@export var max_health: float = 1000.0
@export var current_health: float = 1000.0
@export var repair_rate: float = 5.0  # Health per second when being repaired
@export var damage_reduction: float = 0.0  # 0-1, percentage reduction

# Visual components
var mesh_instance: MeshInstance3D
var sigil_light: OmniLight3D
var health_bar: Node3D

# State
var is_destroyed: bool = false
var players_repairing: Array = []

# Colors for health states
const COLOR_HEALTHY = Color(0.2, 0.7, 1.0)
const COLOR_DAMAGED = Color(1.0, 0.8, 0.2)
const COLOR_CRITICAL = Color(1.0, 0.2, 0.2)

func _ready():
	add_to_group("sigil")
	add_to_group("damageable")

	# Find existing mesh
	mesh_instance = get_node_or_null("MeshInstance3D")

	# Find or create light
	sigil_light = get_node_or_null("SigilLight")
	if not sigil_light:
		sigil_light = OmniLight3D.new()
		sigil_light.name = "SigilLight"
		sigil_light.light_color = COLOR_HEALTHY
		sigil_light.light_energy = 2.0
		sigil_light.omni_range = 8.0
		sigil_light.position.y = 2.0
		add_child(sigil_light)

	_update_visuals()

func _process(delta):
	# Process repair if players are repairing
	if players_repairing.size() > 0 and current_health < max_health:
		var repair_amount = repair_rate * delta * players_repairing.size()
		repair(repair_amount)

func take_damage(amount: float, _source: Node = null) -> float:
	if is_destroyed:
		return 0.0

	# Apply damage reduction
	var actual_damage = amount * (1.0 - damage_reduction)

	current_health = max(0, current_health - actual_damage)
	sigil_damaged.emit(actual_damage, current_health)

	_update_visuals()
	_spawn_damage_effect()

	if current_health <= 0:
		_destroy()

	return actual_damage

func repair(amount: float):
	if is_destroyed:
		return

	var old_health = current_health
	current_health = min(max_health, current_health + amount)

	if current_health != old_health:
		sigil_repaired.emit(current_health - old_health)
		_update_visuals()

func _destroy():
	is_destroyed = true
	sigil_destroyed.emit()

	# Visual destruction
	if mesh_instance:
		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3(0.1, 0.1, 0.1), 0.5)

	if sigil_light:
		sigil_light.light_energy = 0.0

	# Notify systems
	var event_bus = get_node_or_null("/root/EventBus")
	if event_bus and event_bus.has_signal("sigil_destroyed"):
		event_bus.sigil_destroyed.emit(self)

func _update_visuals():
	var health_percent = current_health / max_health if max_health > 0 else 0.0

	# Determine color based on health
	var color = COLOR_HEALTHY
	if health_percent < 0.25:
		color = COLOR_CRITICAL
	elif health_percent < 0.5:
		color = COLOR_DAMAGED

	# Update light
	if sigil_light:
		sigil_light.light_color = color
		sigil_light.light_energy = 2.0 * health_percent + 0.5

	# Update mesh material
	if mesh_instance:
		var mat = mesh_instance.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat.emission = color
			mat.albedo_color = Color(color.r, color.g, color.b, 0.8)

func _spawn_damage_effect():
	# Spawn particles on damage
	var particles = GPUParticles3D.new()
	particles.position = Vector3(0, 0.5, 0)
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 20
	particles.lifetime = 0.5
	particles.explosiveness = 1.0

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 1.0
	material.direction = Vector3(0, 1, 0)
	material.spread = 60.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 4.0
	material.gravity = Vector3.ZERO
	material.color = COLOR_CRITICAL
	particles.process_material = material

	add_child(particles)

	# Auto cleanup
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

# Called when player enters repair range
func start_repair(player: Node):
	if player not in players_repairing:
		players_repairing.append(player)

func stop_repair(player: Node):
	players_repairing.erase(player)

# Utility
func get_health_percent() -> float:
	return current_health / max_health if max_health > 0 else 0.0

func is_critical() -> bool:
	return (current_health / max_health if max_health > 0 else 0.0) < 0.25

func reset():
	current_health = max_health
	is_destroyed = false
	players_repairing.clear()

	if mesh_instance:
		mesh_instance.scale = Vector3.ONE

	_update_visuals()
