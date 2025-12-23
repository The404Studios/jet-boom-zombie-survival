extends Area3D
class_name AcidProjectile

# Acid projectile for spitter zombies
# Network replicated

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var lifetime: float = 5.0
var speed: float = 15.0
var has_hit: bool = false

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var particles: GPUParticles3D = $GPUParticles3D

func _ready():
	add_to_group("projectiles")

	# Setup collision
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Create visual
	_create_visual()

	# Auto-destroy after lifetime
	await get_tree().create_timer(lifetime).timeout
	if not has_hit:
		queue_free()

func _create_visual():
	"""Create acid blob visual"""
	if not mesh:
		mesh = MeshInstance3D.new()
		add_child(mesh)

		var sphere = SphereMesh.new()
		sphere.radius = 0.2
		sphere.height = 0.4
		mesh.mesh = sphere

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 1.0, 0.2, 0.8)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 1.0, 0.2)
		mat.emission_energy_multiplier = 2.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = mat

	# Create particle trail
	if not particles:
		particles = GPUParticles3D.new()
		add_child(particles)
		particles.emitting = true
		particles.amount = 20
		particles.lifetime = 0.5
		particles.explosiveness = 0.0

func launch_toward(target_pos: Vector3, projectile_damage: float):
	"""Launch projectile toward target"""
	damage = projectile_damage

	# Calculate velocity
	var direction = (target_pos - global_position).normalized()
	velocity = direction * speed

func _physics_process(delta):
	if has_hit:
		return

	# Move projectile
	global_position += velocity * delta

	# Apply gravity
	velocity.y -= 9.8 * delta

	# Rotate to face direction
	if velocity.length() > 0:
		look_at(global_position + velocity, Vector3.UP)

func _on_body_entered(body: Node):
	"""Hit something"""
	if has_hit:
		return

	has_hit = true

	# Deal damage
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position)

		# Apply poison
		if body.has_method("apply_status_effect"):
			body.apply_status_effect("poison", 5.0, 3.0)

	# Spawn impact effect
	_spawn_impact_effect()

	# Destroy projectile
	queue_free()

func _on_area_entered(area: Area3D):
	"""Hit an area"""
	if has_hit:
		return

	var body = area.get_parent()
	if body and body.has_method("take_damage"):
		_on_body_entered(body)

func _spawn_impact_effect():
	"""Spawn acid splash effect"""
	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_impact_effect(global_position, Vector3.UP, "acid")

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("acid_splash", global_position, 0.7)
