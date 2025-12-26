extends Node

# Gore system with blood particles, decals, and gibs
# Fully network replicated for multiplayer consistency

@warning_ignore("unused_signal")
signal gore_spawned(gore_position: Vector3, gore_type: String)

const MAX_BLOOD_DECALS: int = 100
const MAX_GIBS: int = 50
const DECAL_LIFETIME: float = 30.0
const GIB_LIFETIME: float = 10.0

var blood_decals: Array = []
var active_gibs: Array = []
var gore_enabled: bool = true

# Particle scenes (will be created procedurally)
var blood_particle_scene: PackedScene
var gib_scene: PackedScene

func _ready():
	# Create procedural gore scenes
	_create_gore_scenes()

func _create_gore_scenes():
	"""Initialize gore system - particles and gibs created on-demand"""
	# Pre-allocate arrays
	blood_decals.resize(MAX_BLOOD_DECALS)
	active_gibs.resize(MAX_GIBS)

	# Fill with null
	for i in range(MAX_BLOOD_DECALS):
		blood_decals[i] = null
	for i in range(MAX_GIBS):
		active_gibs[i] = null

# ============================================
# BLOOD EFFECTS (Network Replicated)
# ============================================

func spawn_blood_effect(position: Vector3, normal: Vector3, amount: int = 1):
	"""Spawn blood particles at impact point"""
	if not multiplayer.has_multiplayer_peer():
		# Single-player - spawn directly
		_spawn_blood_effect_local(position, normal, amount)
		return

	if multiplayer.is_server():
		_spawn_blood_effect_networked.rpc(position, normal, amount)
	else:
		_spawn_blood_effect_networked.rpc_id(1, position, normal, amount)

func _spawn_blood_effect_local(position: Vector3, normal: Vector3, amount: int):
	# Create blood particle burst
	_create_blood_particles(position, normal, amount)
	# Add blood decal
	_create_blood_decal(position, normal)
	# Play blood sound
	if has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		audio.play_sound_3d("impact_flesh", position, 0.7)

@rpc("any_peer", "call_local", "reliable")
func _spawn_blood_effect_networked(position: Vector3, normal: Vector3, amount: int):
	_spawn_blood_effect_local(position, normal, amount)

func _create_blood_particles(position: Vector3, normal: Vector3, amount: int) -> Node:
	var particles = GPUParticles3D.new()

	# Configure particles
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = amount * 10
	particles.lifetime = 1.0
	particles.global_position = position

	# Create material
	var material = ParticleProcessMaterial.new()

	# Emission
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.1

	# Direction - spray away from surface
	material.direction = normal
	material.spread = 30.0

	# Velocity
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0

	# Gravity
	material.gravity = Vector3(0, -9.8, 0)

	# Color - dark red blood
	material.color = Color(0.6, 0.0, 0.0, 1.0)

	# Scale
	material.scale_min = 0.05
	material.scale_max = 0.15

	particles.process_material = material

	# Add to scene
	var scene = get_tree().current_scene
	if not scene:
		particles.queue_free()
		return null
	scene.add_child(particles)

	# Auto-cleanup
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

	return particles

func _create_blood_decal(position: Vector3, normal: Vector3):
	var decal = Decal.new()

	# Position and orient
	decal.global_position = position + normal * 0.01
	decal.look_at(position + normal, Vector3.UP)

	# Size
	decal.size = Vector3(randf_range(0.3, 0.8), randf_range(0.3, 0.8), 1.0)

	# Texture - create simple blood splat
	var texture = _create_blood_texture()
	decal.texture_albedo = texture

	# Properties
	decal.modulate = Color(0.5, 0.0, 0.0, randf_range(0.6, 0.9))
	decal.cull_mask = 1  # Only on environment layer

	# Add to scene
	var scene = get_tree().current_scene
	if not scene:
		decal.queue_free()
		return null
	scene.add_child(decal)
	blood_decals.append(decal)

	# Limit decals
	if blood_decals.size() > MAX_BLOOD_DECALS:
		var old_decal = blood_decals.pop_front()
		old_decal.queue_free()

	# Fade out over time
	_fade_decal(decal)

	return decal

func _create_blood_texture() -> ImageTexture:
	# Create simple blood splat texture
	var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)

	# Draw random blood splat pattern
	for y in range(64):
		for x in range(64):
			var dx = x - 32
			var dy = y - 32
			var dist = sqrt(dx * dx + dy * dy)

			# Splat shape with randomness
			var alpha = 0.0
			if dist < 25.0:
				alpha = (25.0 - dist) / 25.0
				alpha *= randf_range(0.7, 1.0)
				# Add some splatters
				if randf() > 0.7:
					alpha *= randf_range(0.3, 1.0)

			image.set_pixel(x, y, Color(1, 0, 0, alpha))

	return ImageTexture.create_from_image(image)

func _fade_decal(decal: Decal):
	await get_tree().create_timer(DECAL_LIFETIME).timeout

	# Fade out
	var tween = create_tween()
	var current_color = decal.modulate
	tween.tween_property(decal, "modulate", Color(current_color.r, current_color.g, current_color.b, 0.0), 2.0)

	await tween.finished
	if is_instance_valid(decal):
		decal.queue_free()

# ============================================
# GIBS SYSTEM (Network Replicated)
# ============================================

func spawn_gibs(position: Vector3, force: Vector3, count: int = 5):
	"""Spawn flying gibs from zombie death"""
	if not multiplayer.has_multiplayer_peer():
		# Single-player - spawn directly
		_spawn_gibs_local(position, force, count)
		return

	if multiplayer.is_server():
		_spawn_gibs_networked.rpc(position, force, count)
	else:
		_spawn_gibs_networked.rpc_id(1, position, force, count)

func _spawn_gibs_local(position: Vector3, force: Vector3, count: int):
	for i in range(count):
		_create_single_gib(position, force)

@rpc("any_peer", "call_local", "reliable")
func _spawn_gibs_networked(position: Vector3, force: Vector3, count: int):
	_spawn_gibs_local(position, force, count)

func _create_single_gib(position: Vector3, base_force: Vector3) -> RigidBody3D:
	var gib = RigidBody3D.new()
	gib.global_position = position + Vector3(randf_range(-0.3, 0.3), randf_range(0, 0.5), randf_range(-0.3, 0.3))

	# Create mesh
	var mesh_instance = MeshInstance3D.new()
	var gib_type = randi() % 3

	match gib_type:
		0:  # Chunk
			var box = BoxMesh.new()
			box.size = Vector3(randf_range(0.1, 0.3), randf_range(0.1, 0.3), randf_range(0.1, 0.3))
			mesh_instance.mesh = box
		1:  # Splatter
			var sphere = SphereMesh.new()
			sphere.radius = randf_range(0.08, 0.15)
			sphere.height = randf_range(0.15, 0.3)
			mesh_instance.mesh = sphere
		2:  # Bone-like
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = 0.05
			cylinder.bottom_radius = 0.05
			cylinder.height = randf_range(0.2, 0.4)
			mesh_instance.mesh = cylinder

	# Material - dark bloody color
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(randf_range(0.3, 0.6), 0.0, 0.0, 1.0)
	material.roughness = 0.9
	mesh_instance.material_override = material

	gib.add_child(mesh_instance)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.2, 0.2, 0.2)
	collision.shape = shape
	gib.add_child(collision)

	# Physics properties
	gib.mass = 0.5
	gib.gravity_scale = 1.5

	# Apply random force
	var random_force = base_force + Vector3(
		randf_range(-3, 3),
		randf_range(2, 5),
		randf_range(-3, 3)
	)

	# Add to scene
	var scene = get_tree().current_scene
	if not scene:
		gib.queue_free()
		return null
	scene.add_child(gib)
	active_gibs.append(gib)

	# Apply impulse after physics frame
	await get_tree().physics_frame
	if is_instance_valid(gib):
		gib.apply_central_impulse(random_force)
		gib.apply_torque_impulse(Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)))

	# Cleanup old gibs if too many
	if active_gibs.size() > MAX_GIBS:
		var old_gib = active_gibs.pop_front()
		if is_instance_valid(old_gib):
			old_gib.queue_free()

	# Auto cleanup
	_cleanup_gib(gib)

	return gib

func _cleanup_gib(gib: RigidBody3D):
	await get_tree().create_timer(GIB_LIFETIME).timeout

	if is_instance_valid(gib):
		# Fade out - check if gib has children before accessing
		if gib.get_child_count() > 0:
			var mesh = gib.get_child(0) as MeshInstance3D
			if mesh:
				var tween = create_tween()
				var mat = mesh.material_override as StandardMaterial3D
				if mat:
					var current_color = mat.albedo_color
					tween.tween_property(mat, "albedo_color", Color(current_color.r, current_color.g, current_color.b, 0.0), 1.0)

		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(gib):
			gib.queue_free()

# ============================================
# DISMEMBERMENT (Headshots, etc.)
# ============================================

func spawn_dismemberment_effect(position: Vector3, body_part: String):
	"""Spawn special effect for dismemberment (headshot, limb loss)"""
	if not multiplayer.has_multiplayer_peer():
		# Single-player - spawn directly
		_spawn_dismemberment_local(position, body_part)
		return

	if multiplayer.is_server():
		_spawn_dismemberment_networked.rpc(position, body_part)
	else:
		_spawn_dismemberment_networked.rpc_id(1, position, body_part)

func _spawn_dismemberment_local(position: Vector3, body_part: String):
	# Extra blood for dismemberment
	spawn_blood_effect(position, Vector3.UP, 3)

	# Spawn body part gib
	match body_part:
		"head":
			_create_head_gib(position)
		"arm", "leg":
			_create_limb_gib(position)

@rpc("any_peer", "call_local", "reliable")
func _spawn_dismemberment_networked(position: Vector3, body_part: String):
	_spawn_dismemberment_local(position, body_part)

func _create_head_gib(position: Vector3):
	var gib = RigidBody3D.new()
	gib.global_position = position

	# Head mesh
	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mesh_instance.mesh = sphere

	# Bloody material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.3, 0.3, 1.0)
	mesh_instance.material_override = material

	gib.add_child(mesh_instance)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.15
	collision.shape = shape
	gib.add_child(collision)

	gib.mass = 2.0
	var scene = get_tree().current_scene
	if not scene:
		gib.queue_free()
		return
	scene.add_child(gib)

	# Apply upward force
	await get_tree().physics_frame
	if is_instance_valid(gib):
		gib.apply_central_impulse(Vector3(randf_range(-2, 2), randf_range(5, 8), randf_range(-2, 2)))
		gib.apply_torque_impulse(Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10)))

	# Cleanup
	await get_tree().create_timer(GIB_LIFETIME).timeout
	if is_instance_valid(gib):
		gib.queue_free()

func _create_limb_gib(position: Vector3):
	var gib = RigidBody3D.new()
	gib.global_position = position

	# Limb mesh
	var mesh_instance = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.08
	capsule.height = 0.5
	mesh_instance.mesh = capsule

	# Material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.2, 0.2, 1.0)
	mesh_instance.material_override = material

	gib.add_child(mesh_instance)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.08
	shape.height = 0.5
	collision.shape = shape
	gib.add_child(collision)

	gib.mass = 1.0
	var scene = get_tree().current_scene
	if not scene:
		gib.queue_free()
		return
	scene.add_child(gib)

	# Apply force
	await get_tree().physics_frame
	if is_instance_valid(gib):
		gib.apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(3, 6), randf_range(-3, 3)))
		gib.apply_torque_impulse(Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)))

	# Cleanup
	await get_tree().create_timer(GIB_LIFETIME).timeout
	if is_instance_valid(gib):
		gib.queue_free()

# ============================================
# CLEANUP
# ============================================

func clear_all_gore():
	"""Clear all blood decals and gibs"""
	for decal in blood_decals:
		if is_instance_valid(decal):
			decal.queue_free()
	blood_decals.clear()

	for gib in active_gibs:
		if is_instance_valid(gib):
			gib.queue_free()
	active_gibs.clear()

func set_gore_enabled(enabled: bool):
	"""Toggle gore system on/off"""
	gore_enabled = enabled

	# If disabling, clear all gore
	if not enabled:
		clear_all_gore()

	print("Gore system %s" % ("enabled" if enabled else "disabled"))

# Alias methods for compatibility
func spawn_blood_splatter(position: Vector3, normal: Vector3):
	"""Alias for spawn_blood_effect - for compatibility"""
	spawn_blood_effect(position, normal, 1)

func spawn_death_effect(position: Vector3):
	"""Spawn death gore effect at position"""
	spawn_gibs(position, Vector3.UP * 3.0, 5)
	spawn_blood_effect(position, Vector3.UP, 3)
