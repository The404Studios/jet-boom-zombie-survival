extends Node

# Visual effects manager with network replication
# Handles muzzle flashes, impacts, explosions, and other VFX

signal effect_spawned(effect_type: String, position: Vector3)

# VFX pools
const POOL_SIZE: int = 50
var effect_pool: Array = []
var pool_index: int = 0

func _ready():
	# Create effect pool
	_create_effect_pool()

func _create_effect_pool():
	for i in POOL_SIZE:
		var particles = GPUParticles3D.new()
		particles.one_shot = true
		particles.emitting = false
		add_child(particles)
		effect_pool.append(particles)

# ============================================
# MUZZLE FLASH (Network Replicated)
# ============================================

func spawn_muzzle_flash(position: Vector3, direction: Vector3, weapon_type: String = "default"):
	if multiplayer.is_server():
		_spawn_muzzle_flash_networked.rpc(position, direction, weapon_type)
	else:
		_spawn_muzzle_flash_networked.rpc_id(1, position, direction, weapon_type)

@rpc("any_peer", "call_local", "reliable")
func _spawn_muzzle_flash_networked(position: Vector3, direction: Vector3, weapon_type: String):
	var particles = _get_next_particle()

	# Configure based on weapon type
	var amount = 20
	var lifetime = 0.1
	var scale_range = Vector2(0.1, 0.3)

	match weapon_type:
		"shotgun":
			amount = 50
			lifetime = 0.15
			scale_range = Vector2(0.2, 0.5)
		"sniper", "rpg":
			amount = 40
			lifetime = 0.2
			scale_range = Vector2(0.15, 0.4)
		"machinegun":
			amount = 30
			lifetime = 0.12

	particles.amount = amount
	particles.lifetime = lifetime
	particles.global_position = position

	# Create flash material
	var material = ParticleProcessMaterial.new()

	# Emission
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.05

	# Direction
	material.direction = direction
	material.spread = 20.0

	# Velocity
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 2.0

	# Color - bright yellow/orange flash
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.5, 0.0, 0.8))
	gradient.add_point(1.0, Color(0.3, 0.1, 0.0, 0.0))

	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient

	material.color_ramp = gradient_texture

	# Scale
	material.scale_min = scale_range.x
	material.scale_max = scale_range.y

	particles.process_material = material
	particles.restart()

# ============================================
# BULLET IMPACT (Network Replicated)
# ============================================

func spawn_impact_effect(position: Vector3, normal: Vector3, surface_type: String = "default"):
	if multiplayer.is_server():
		_spawn_impact_networked.rpc(position, normal, surface_type)
	else:
		_spawn_impact_networked.rpc_id(1, position, normal, surface_type)

@rpc("any_peer", "call_local", "reliable")
func _spawn_impact_networked(position: Vector3, normal: Vector3, surface_type: String):
	var particles = _get_next_particle()

	# Configure based on surface
	var color = Color.WHITE
	var amount = 15

	match surface_type:
		"flesh":
			# Blood splatter handled by GoreSystem
			return
		"metal":
			color = Color(0.8, 0.8, 0.9, 1.0)
			amount = 20
		"wood":
			color = Color(0.6, 0.4, 0.2, 1.0)
			amount = 12
		"concrete":
			color = Color(0.7, 0.7, 0.7, 1.0)
			amount = 18
		_:
			color = Color(0.8, 0.8, 0.8, 1.0)

	particles.amount = amount
	particles.lifetime = 0.5
	particles.global_position = position

	# Create material
	var material = ParticleProcessMaterial.new()

	# Emission
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.02

	# Direction - away from surface
	material.direction = normal
	material.spread = 45.0

	# Velocity
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0

	# Gravity
	material.gravity = Vector3(0, -9.8, 0)

	# Color
	material.color = color

	# Scale
	material.scale_min = 0.02
	material.scale_max = 0.08

	particles.process_material = material
	particles.restart()

	# Create impact decal (bullet hole)
	_create_impact_decal(position, normal, surface_type)

	# Play audio
	if has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		audio.play_impact(surface_type, position)

func _create_impact_decal(position: Vector3, normal: Vector3, surface_type: String):
	var decal = Decal.new()

	# Position and orient
	decal.global_position = position + normal * 0.01
	decal.look_at(position + normal, Vector3.UP)

	# Size
	var size = 0.1
	if surface_type == "concrete":
		size = 0.15

	decal.size = Vector3(size, size, 0.5)

	# Create bullet hole texture
	var texture = _create_bullet_hole_texture()
	decal.texture_albedo = texture

	# Color based on surface
	var color = Color.WHITE
	match surface_type:
		"metal":
			color = Color(0.3, 0.3, 0.3, 0.8)
		"wood":
			color = Color(0.2, 0.15, 0.1, 0.9)
		"concrete":
			color = Color(0.4, 0.4, 0.4, 0.85)
		_:
			color = Color(0.3, 0.3, 0.3, 0.8)

	decal.modulate = color
	decal.cull_mask = 1

	# Add to scene
	get_tree().current_scene.add_child(decal)

	# Auto cleanup
	await get_tree().create_timer(60.0).timeout
	if is_instance_valid(decal):
		decal.queue_free()

func _create_bullet_hole_texture() -> ImageTexture:
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)

	# Draw bullet hole
	for y in range(32):
		for x in range(32):
			var dx = x - 16
			var dy = y - 16
			var dist = sqrt(dx * dx + dy * dy)

			var alpha = 0.0
			if dist < 6.0:
				alpha = 1.0
			elif dist < 8.0:
				alpha = (8.0 - dist) / 2.0

			# Add some randomness
			if randf() > 0.8:
				alpha *= randf_range(0.5, 1.0)

			image.set_pixel(x, y, Color(0, 0, 0, alpha))

	return ImageTexture.create_from_image(image)

# ============================================
# EXPLOSION (Network Replicated)
# ============================================

func spawn_explosion(position: Vector3, radius: float = 5.0):
	if multiplayer.is_server():
		_spawn_explosion_networked.rpc(position, radius)
	else:
		_spawn_explosion_networked.rpc_id(1, position, radius)

@rpc("any_peer", "call_local", "reliable")
func _spawn_explosion_networked(position: Vector3, radius: float):
	# Main explosion particles
	var explosion = GPUParticles3D.new()
	explosion.global_position = position
	explosion.amount = 100
	explosion.lifetime = 1.0
	explosion.one_shot = true
	explosion.explosiveness = 1.0

	# Material
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = radius * 0.2

	material.direction = Vector3.UP
	material.spread = 180.0

	material.initial_velocity_min = radius * 2.0
	material.initial_velocity_max = radius * 4.0

	material.gravity = Vector3(0, -5.0, 0)

	# Color gradient - fire to smoke
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))
	gradient.add_point(0.2, Color(1.0, 0.5, 0.0, 1.0))
	gradient.add_point(0.5, Color(0.3, 0.3, 0.3, 0.8))
	gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))

	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	material.scale_min = 0.5
	material.scale_max = 1.5

	explosion.process_material = material

	get_tree().current_scene.add_child(explosion)

	# Shockwave ring
	_create_shockwave(position, radius)

	# Cleanup
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(explosion):
		explosion.queue_free()

func _create_shockwave(position: Vector3, radius: float):
	# Simple expanding ring effect
	var ring = MeshInstance3D.new()
	ring.global_position = position + Vector3(0, 0.1, 0)

	# Create ring mesh
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.1
	mesh.bottom_radius = 0.1
	mesh.height = 0.2
	ring.mesh = mesh

	# Material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.0, 0.8)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.0)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material

	get_tree().current_scene.add_child(ring)

	# Expand animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "top_radius", radius, 0.5)
	tween.tween_property(mesh, "bottom_radius", radius, 0.5)
	tween.tween_property(material, "albedo_color", Color(1.0, 0.5, 0.0, 0.0), 0.5)

	await tween.finished
	if is_instance_valid(ring):
		ring.queue_free()

# ============================================
# SHELL CASINGS (Network Replicated)
# ============================================

func spawn_shell_casing(position: Vector3, direction: Vector3):
	if multiplayer.is_server():
		_spawn_shell_networked.rpc(position, direction)
	else:
		_spawn_shell_networked.rpc_id(1, position, direction)

@rpc("any_peer", "call_local", "unreliable")
func _spawn_shell_networked(position: Vector3, direction: Vector3):
	var shell = RigidBody3D.new()
	shell.global_position = position

	# Shell mesh
	var mesh_instance = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.01
	cylinder.bottom_radius = 0.01
	cylinder.height = 0.02
	mesh_instance.mesh = cylinder

	# Material - brass
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.6, 0.2, 1.0)
	material.metallic = 0.8
	material.roughness = 0.3
	mesh_instance.material_override = material

	shell.add_child(mesh_instance)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = 0.01
	shape.height = 0.02
	collision.shape = shape
	shell.add_child(collision)

	shell.mass = 0.01
	get_tree().current_scene.add_child(shell)

	# Apply ejection force
	await get_tree().physics_frame
	if is_instance_valid(shell):
		var force = direction * randf_range(2.0, 4.0)
		shell.apply_central_impulse(force)
		shell.apply_torque_impulse(Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)))

	# Cleanup after 5 seconds
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(shell):
		shell.queue_free()

# ============================================
# HELPER FUNCTIONS
# ============================================

func _get_next_particle() -> GPUParticles3D:
	var particle = effect_pool[pool_index]
	pool_index = (pool_index + 1) % POOL_SIZE
	return particle
