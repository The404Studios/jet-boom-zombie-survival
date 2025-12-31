extends Node

# Gore system with blood particles, decals, and model-based gibs
# Fully network replicated for multiplayer consistency
# Features: Body part dismemberment, blood splatter, gore trails

@warning_ignore("unused_signal")
signal gore_spawned(gore_position: Vector3, gore_type: String)
signal dismemberment_occurred(position: Vector3, body_part: String)

const MAX_BLOOD_DECALS: int = 100
const MAX_GIBS: int = 75
const DECAL_LIFETIME: float = 30.0
const GIB_LIFETIME: float = 15.0

# Body part types for dismemberment
enum BodyPart { HEAD, TORSO, ARM_LEFT, ARM_RIGHT, LEG_LEFT, LEG_RIGHT, HAND, FOOT, SPINE, RIBCAGE }

var blood_decals: Array = []
var active_gibs: Array = []
var gore_enabled: bool = true
var gore_level: int = 3  # 0=off, 1=minimal, 2=normal, 3=extreme

# Cached materials for performance
var blood_material: StandardMaterial3D
var bone_material: StandardMaterial3D
var flesh_material: StandardMaterial3D
var organ_material: StandardMaterial3D

func _ready():
	# Create procedural gore scenes
	_create_gore_scenes()
	_create_gore_materials()

func _create_gore_scenes():
	"""Initialize gore system - particles and gibs created on-demand"""
	blood_decals.clear()
	active_gibs.clear()

func _create_gore_materials():
	"""Pre-create materials for gore effects"""
	# Blood material - dark red, wet look
	blood_material = StandardMaterial3D.new()
	blood_material.albedo_color = Color(0.5, 0.02, 0.02, 1.0)
	blood_material.roughness = 0.2
	blood_material.metallic = 0.1

	# Bone material - off-white
	bone_material = StandardMaterial3D.new()
	bone_material.albedo_color = Color(0.9, 0.85, 0.75, 1.0)
	bone_material.roughness = 0.7

	# Flesh material - pink/red muscle tissue
	flesh_material = StandardMaterial3D.new()
	flesh_material.albedo_color = Color(0.65, 0.25, 0.25, 1.0)
	flesh_material.roughness = 0.6

	# Organ material - dark red, shiny
	organ_material = StandardMaterial3D.new()
	organ_material.albedo_color = Color(0.4, 0.08, 0.08, 1.0)
	organ_material.roughness = 0.3
	organ_material.metallic = 0.05

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
	if not gore_enabled or gore_level == 0:
		return

	if not multiplayer.has_multiplayer_peer():
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

	var mesh_instance = MeshInstance3D.new()
	var gib_type = randi() % 5

	match gib_type:
		0:  # Flesh chunk
			var box = BoxMesh.new()
			box.size = Vector3(randf_range(0.08, 0.2), randf_range(0.08, 0.2), randf_range(0.08, 0.2))
			mesh_instance.mesh = box
			mesh_instance.material_override = flesh_material.duplicate()
		1:  # Blood clot
			var sphere = SphereMesh.new()
			sphere.radius = randf_range(0.05, 0.12)
			sphere.height = randf_range(0.1, 0.24)
			mesh_instance.mesh = sphere
			mesh_instance.material_override = blood_material.duplicate()
		2:  # Bone fragment
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = randf_range(0.02, 0.05)
			cylinder.bottom_radius = randf_range(0.02, 0.05)
			cylinder.height = randf_range(0.15, 0.35)
			mesh_instance.mesh = cylinder
			mesh_instance.material_override = bone_material.duplicate()
		3:  # Organ piece
			var sphere = SphereMesh.new()
			sphere.radius = randf_range(0.08, 0.15)
			sphere.height = randf_range(0.12, 0.25)
			mesh_instance.mesh = sphere
			mesh_instance.material_override = organ_material.duplicate()
		4:  # Tissue strip
			var box = BoxMesh.new()
			box.size = Vector3(randf_range(0.02, 0.05), randf_range(0.15, 0.3), randf_range(0.02, 0.05))
			mesh_instance.mesh = box
			mesh_instance.material_override = flesh_material.duplicate()

	gib.add_child(mesh_instance)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.1
	collision.shape = shape
	gib.add_child(collision)

	# Physics properties
	gib.mass = randf_range(0.2, 0.8)
	gib.gravity_scale = 1.2
	gib.collision_layer = 0  # Don't block anything
	gib.collision_mask = 1   # Only collide with ground

	# Apply random force
	var random_force = base_force + Vector3(
		randf_range(-4, 4),
		randf_range(3, 7),
		randf_range(-4, 4)
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
		gib.apply_torque_impulse(Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)))

	# Cleanup old gibs if too many
	while active_gibs.size() > MAX_GIBS:
		var old_gib = active_gibs.pop_front()
		if is_instance_valid(old_gib):
			old_gib.queue_free()

	# Auto cleanup
	_cleanup_gib(gib)

	return gib

func _cleanup_gib(gib: RigidBody3D):
	await get_tree().create_timer(GIB_LIFETIME).timeout

	if is_instance_valid(gib):
		if gib.get_child_count() > 0:
			var mesh = gib.get_child(0) as MeshInstance3D
			if mesh and mesh.material_override:
				var tween = create_tween()
				var mat = mesh.material_override as StandardMaterial3D
				if mat:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)

		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(gib):
			active_gibs.erase(gib)
			gib.queue_free()

# ============================================
# DISMEMBERMENT (Body part separation)
# ============================================

func spawn_dismemberment_effect(position: Vector3, body_part: String):
	"""Spawn special effect for dismemberment (headshot, limb loss)"""
	if not gore_enabled or gore_level < 2:
		return

	if not multiplayer.has_multiplayer_peer():
		_spawn_dismemberment_local(position, body_part)
		return

	if multiplayer.is_server():
		_spawn_dismemberment_networked.rpc(position, body_part)
	else:
		_spawn_dismemberment_networked.rpc_id(1, position, body_part)

func _spawn_dismemberment_local(position: Vector3, body_part: String):
	# Extra blood spray for dismemberment
	spawn_blood_effect(position, Vector3.UP, 5)

	# Spawn appropriate body part
	match body_part:
		"head":
			_create_head_gib(position)
		"arm_left", "arm_right", "arm":
			_create_arm_gib(position, body_part == "arm_left")
		"leg_left", "leg_right", "leg":
			_create_leg_gib(position, body_part == "leg_left")
		"torso":
			_create_torso_gib(position)
		"hand":
			_create_hand_gib(position)
		"foot":
			_create_foot_gib(position)

	# Additional small gibs and blood trail
	for i in range(3):
		_create_single_gib(position, Vector3(randf_range(-2, 2), 3, randf_range(-2, 2)))

	dismemberment_occurred.emit(position, body_part)

@rpc("any_peer", "call_local", "reliable")
func _spawn_dismemberment_networked(position: Vector3, body_part: String):
	_spawn_dismemberment_local(position, body_part)

func spawn_full_body_explosion(position: Vector3, force_multiplier: float = 1.0):
	"""Spawn all body parts exploding outward - for explosive deaths"""
	if not gore_enabled or gore_level < 2:
		return

	# Spawn all major body parts
	_create_head_gib(position + Vector3(0, 1.6, 0))
	_create_torso_gib(position + Vector3(0, 1.0, 0))
	_create_arm_gib(position + Vector3(0.4, 1.2, 0), false)
	_create_arm_gib(position + Vector3(-0.4, 1.2, 0), true)
	_create_leg_gib(position + Vector3(0.2, 0.5, 0), false)
	_create_leg_gib(position + Vector3(-0.2, 0.5, 0), true)

	# Lots of small gibs
	var gib_count = 15 if gore_level >= 3 else 8
	for i in range(gib_count):
		var offset = Vector3(randf_range(-0.5, 0.5), randf_range(0.5, 1.5), randf_range(-0.5, 0.5))
		var force = Vector3(randf_range(-5, 5), randf_range(4, 10), randf_range(-5, 5)) * force_multiplier
		_create_single_gib(position + offset, force)

	# Major blood explosion
	spawn_blood_effect(position + Vector3.UP, Vector3.UP, 8)

func _create_head_gib(position: Vector3):
	var gib = RigidBody3D.new()
	gib.global_position = position
	gib.collision_layer = 0
	gib.collision_mask = 1

	# Head shape - slightly elongated sphere
	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.28
	mesh_instance.mesh = sphere

	# Zombie skin material with blood
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.35, 0.3, 1.0)
	mat.roughness = 0.8
	mesh_instance.material_override = mat

	gib.add_child(mesh_instance)

	# Add blood stump at neck
	var stump = MeshInstance3D.new()
	var stump_mesh = CylinderMesh.new()
	stump_mesh.top_radius = 0.06
	stump_mesh.bottom_radius = 0.08
	stump_mesh.height = 0.05
	stump.mesh = stump_mesh
	stump.material_override = blood_material.duplicate()
	stump.position = Vector3(0, -0.14, 0)
	gib.add_child(stump)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.12
	collision.shape = shape
	gib.add_child(collision)

	gib.mass = 1.5
	_add_gib_to_scene(gib, Vector3(randf_range(-2, 2), randf_range(5, 9), randf_range(-2, 2)))

func _create_arm_gib(position: Vector3, is_left: bool):
	var gib = RigidBody3D.new()
	gib.global_position = position
	gib.collision_layer = 0
	gib.collision_mask = 1

	# Upper arm
	var upper_arm = MeshInstance3D.new()
	var upper_capsule = CapsuleMesh.new()
	upper_capsule.radius = 0.05
	upper_capsule.height = 0.35
	upper_arm.mesh = upper_capsule
	upper_arm.material_override = flesh_material.duplicate()
	upper_arm.position = Vector3(0, 0.15, 0)
	gib.add_child(upper_arm)

	# Lower arm
	var lower_arm = MeshInstance3D.new()
	var lower_capsule = CapsuleMesh.new()
	lower_capsule.radius = 0.04
	lower_capsule.height = 0.3
	lower_arm.mesh = lower_capsule
	lower_arm.material_override = flesh_material.duplicate()
	lower_arm.position = Vector3(0, -0.18, 0)
	gib.add_child(lower_arm)

	# Hand
	var hand = MeshInstance3D.new()
	var hand_mesh = BoxMesh.new()
	hand_mesh.size = Vector3(0.08, 0.1, 0.04)
	hand.mesh = hand_mesh
	hand.material_override = flesh_material.duplicate()
	hand.position = Vector3(0, -0.38, 0)
	gib.add_child(hand)

	# Bloody stump at shoulder
	var stump = MeshInstance3D.new()
	var stump_mesh = SphereMesh.new()
	stump_mesh.radius = 0.06
	stump_mesh.height = 0.08
	stump.mesh = stump_mesh
	stump.material_override = blood_material.duplicate()
	stump.position = Vector3(0, 0.35, 0)
	gib.add_child(stump)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.06
	shape.height = 0.7
	collision.shape = shape
	gib.add_child(collision)

	gib.mass = 1.2
	var dir = -1.0 if is_left else 1.0
	_add_gib_to_scene(gib, Vector3(randf_range(2, 4) * dir, randf_range(3, 6), randf_range(-2, 2)))

func _create_leg_gib(position: Vector3, is_left: bool):
	var gib = RigidBody3D.new()
	gib.global_position = position
	gib.collision_layer = 0
	gib.collision_mask = 1

	# Upper leg (thigh)
	var thigh = MeshInstance3D.new()
	var thigh_capsule = CapsuleMesh.new()
	thigh_capsule.radius = 0.08
	thigh_capsule.height = 0.45
	thigh.mesh = thigh_capsule
	thigh.material_override = flesh_material.duplicate()
	thigh.position = Vector3(0, 0.2, 0)
	gib.add_child(thigh)

	# Lower leg (calf)
	var calf = MeshInstance3D.new()
	var calf_capsule = CapsuleMesh.new()
	calf_capsule.radius = 0.06
	calf_capsule.height = 0.4
	calf.mesh = calf_capsule
	calf.material_override = flesh_material.duplicate()
	calf.position = Vector3(0, -0.25, 0)
	gib.add_child(calf)

	# Foot
	var foot = MeshInstance3D.new()
	var foot_mesh = BoxMesh.new()
	foot_mesh.size = Vector3(0.08, 0.06, 0.18)
	foot.mesh = foot_mesh
	foot.material_override = flesh_material.duplicate()
	foot.position = Vector3(0, -0.5, 0.05)
	gib.add_child(foot)

	# Bloody stump at hip
	var stump = MeshInstance3D.new()
	var stump_mesh = SphereMesh.new()
	stump_mesh.radius = 0.08
	stump_mesh.height = 0.1
	stump.mesh = stump_mesh
	stump.material_override = blood_material.duplicate()
	stump.position = Vector3(0, 0.45, 0)
	gib.add_child(stump)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.08
	shape.height = 0.9
	collision.shape = shape
	gib.add_child(collision)

	gib.mass = 2.0
	var dir = -1.0 if is_left else 1.0
	_add_gib_to_scene(gib, Vector3(randf_range(1, 3) * dir, randf_range(2, 5), randf_range(-2, 2)))

func _create_torso_gib(position: Vector3):
	var gib = RigidBody3D.new()
	gib.global_position = position
	gib.collision_layer = 0
	gib.collision_mask = 1

	# Main torso
	var torso = MeshInstance3D.new()
	var torso_mesh = BoxMesh.new()
	torso_mesh.size = Vector3(0.4, 0.5, 0.25)
	torso.mesh = torso_mesh
	torso.material_override = flesh_material.duplicate()
	gib.add_child(torso)

	# Ribcage peek
	var ribs = MeshInstance3D.new()
	var ribs_mesh = BoxMesh.new()
	ribs_mesh.size = Vector3(0.3, 0.15, 0.2)
	ribs.mesh = ribs_mesh
	ribs.material_override = bone_material.duplicate()
	ribs.position = Vector3(0, 0.1, 0.05)
	gib.add_child(ribs)

	# Bloody areas at connection points
	var neck_stump = MeshInstance3D.new()
	var neck_mesh = CylinderMesh.new()
	neck_mesh.top_radius = 0.06
	neck_mesh.bottom_radius = 0.08
	neck_mesh.height = 0.05
	neck_stump.mesh = neck_mesh
	neck_stump.material_override = blood_material.duplicate()
	neck_stump.position = Vector3(0, 0.27, 0)
	gib.add_child(neck_stump)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.4, 0.5, 0.25)
	collision.shape = shape
	gib.add_child(collision)

	gib.mass = 4.0
	_add_gib_to_scene(gib, Vector3(randf_range(-1, 1), randf_range(2, 4), randf_range(-1, 1)))

func _create_hand_gib(position: Vector3):
	var gib = RigidBody3D.new()
	gib.global_position = position
	gib.collision_layer = 0
	gib.collision_mask = 1

	# Hand
	var hand = MeshInstance3D.new()
	var hand_mesh = BoxMesh.new()
	hand_mesh.size = Vector3(0.08, 0.12, 0.04)
	hand.mesh = hand_mesh
	hand.material_override = flesh_material.duplicate()
	gib.add_child(hand)

	# Fingers (simplified as box)
	var fingers = MeshInstance3D.new()
	var fingers_mesh = BoxMesh.new()
	fingers_mesh.size = Vector3(0.06, 0.08, 0.03)
	fingers.mesh = fingers_mesh
	fingers.material_override = flesh_material.duplicate()
	fingers.position = Vector3(0, -0.1, 0)
	gib.add_child(fingers)

	# Bloody wrist stump
	var stump = MeshInstance3D.new()
	var stump_mesh = CylinderMesh.new()
	stump_mesh.top_radius = 0.03
	stump_mesh.bottom_radius = 0.04
	stump_mesh.height = 0.03
	stump.mesh = stump_mesh
	stump.material_override = blood_material.duplicate()
	stump.position = Vector3(0, 0.08, 0)
	gib.add_child(stump)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.1, 0.15, 0.05)
	collision.shape = shape
	gib.add_child(collision)

	gib.mass = 0.3
	_add_gib_to_scene(gib, Vector3(randf_range(-3, 3), randf_range(4, 7), randf_range(-3, 3)))

func _create_foot_gib(position: Vector3):
	var gib = RigidBody3D.new()
	gib.global_position = position
	gib.collision_layer = 0
	gib.collision_mask = 1

	# Foot
	var foot = MeshInstance3D.new()
	var foot_mesh = BoxMesh.new()
	foot_mesh.size = Vector3(0.08, 0.06, 0.2)
	foot.mesh = foot_mesh
	foot.material_override = flesh_material.duplicate()
	gib.add_child(foot)

	# Bloody ankle stump
	var stump = MeshInstance3D.new()
	var stump_mesh = CylinderMesh.new()
	stump_mesh.top_radius = 0.04
	stump_mesh.bottom_radius = 0.05
	stump_mesh.height = 0.04
	stump.mesh = stump_mesh
	stump.material_override = blood_material.duplicate()
	stump.position = Vector3(0, 0.05, -0.05)
	gib.add_child(stump)

	# Collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.1, 0.08, 0.22)
	collision.shape = shape
	gib.add_child(collision)

	gib.mass = 0.5
	_add_gib_to_scene(gib, Vector3(randf_range(-2, 2), randf_range(2, 5), randf_range(-2, 2)))

func _add_gib_to_scene(gib: RigidBody3D, impulse: Vector3):
	"""Helper to add gib to scene and apply physics"""
	var scene = get_tree().current_scene
	if not scene:
		gib.queue_free()
		return

	scene.add_child(gib)
	active_gibs.append(gib)

	# Apply physics after a frame
	await get_tree().physics_frame
	if is_instance_valid(gib):
		gib.apply_central_impulse(impulse)
		gib.apply_torque_impulse(Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12)))

	# Spawn blood trail while flying
	_spawn_flying_blood_trail(gib)

	# Cleanup
	_cleanup_gib(gib)

func _spawn_flying_blood_trail(gib: RigidBody3D):
	"""Spawn blood drips while the gib is in the air"""
	if gore_level < 3:
		return

	for i in range(5):
		await get_tree().create_timer(0.15).timeout
		if not is_instance_valid(gib):
			return
		if gib.linear_velocity.length() < 0.5:
			return
		spawn_blood_effect(gib.global_position, Vector3.DOWN, 1)

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
