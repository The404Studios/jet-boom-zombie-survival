extends Node3D
class_name Turret

# Automated turret that shoots at nearby zombies

signal target_acquired(target: Node3D)
signal target_lost
signal fired
signal destroyed

enum TurretType { BASIC, HEAVY, FLAME, TESLA }

@export var turret_type: TurretType = TurretType.BASIC
@export var max_health: float = 200.0
@export var damage: float = 10.0
@export var fire_rate: float = 0.2
@export var detection_range: float = 20.0
@export var rotation_speed: float = 3.0

var current_health: float = 200.0
var current_target: Node3D = null
var shoot_timer: float = 0.0
var is_active: bool = true

# Components
var base_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var barrel_mesh: MeshInstance3D
var detection_area: Area3D
var muzzle_point: Marker3D

func _ready():
	add_to_group("turret")
	add_to_group("player_structure")
	current_health = max_health

	_create_turret_visuals()
	_setup_detection()
	_apply_turret_type()

func _create_turret_visuals():
	# Base
	base_mesh = MeshInstance3D.new()
	base_mesh.name = "Base"
	var base_box = BoxMesh.new()
	base_box.size = Vector3(0.6, 0.3, 0.6)
	base_mesh.mesh = base_box
	add_child(base_mesh)

	var base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.3, 0.3, 0.35)
	base_mat.metallic = 0.7
	base_mesh.material_override = base_mat

	# Rotating head
	head_mesh = MeshInstance3D.new()
	head_mesh.name = "Head"
	var head_box = BoxMesh.new()
	head_box.size = Vector3(0.4, 0.25, 0.4)
	head_mesh.mesh = head_box
	head_mesh.position.y = 0.275
	add_child(head_mesh)

	var head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.25, 0.4, 0.25)
	head_mat.metallic = 0.6
	head_mesh.material_override = head_mat

	# Barrel
	barrel_mesh = MeshInstance3D.new()
	barrel_mesh.name = "Barrel"
	var barrel_cyl = CylinderMesh.new()
	barrel_cyl.top_radius = 0.04
	barrel_cyl.bottom_radius = 0.05
	barrel_cyl.height = 0.6
	barrel_mesh.mesh = barrel_cyl
	barrel_mesh.rotation.x = PI / 2
	barrel_mesh.position = Vector3(0, 0, -0.35)
	head_mesh.add_child(barrel_mesh)

	var barrel_mat = StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.2, 0.2, 0.22)
	barrel_mat.metallic = 0.9
	barrel_mesh.material_override = barrel_mat

	# Muzzle point
	muzzle_point = Marker3D.new()
	muzzle_point.name = "MuzzlePoint"
	muzzle_point.position = Vector3(0, 0, -0.65)
	head_mesh.add_child(muzzle_point)

	# Status light
	var light = OmniLight3D.new()
	light.name = "StatusLight"
	light.light_color = Color.GREEN
	light.light_energy = 0.5
	light.omni_range = 2.0
	light.position.y = 0.5
	add_child(light)

func _setup_detection():
	detection_area = Area3D.new()
	detection_area.name = "DetectionArea"
	add_child(detection_area)

	var collision = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = detection_range
	collision.shape = sphere
	detection_area.add_child(collision)

	# Only detect zombies
	detection_area.collision_layer = 0
	detection_area.collision_mask = 4  # Layer 3 = Zombies

	detection_area.body_entered.connect(_on_target_entered)
	detection_area.body_exited.connect(_on_target_exited)

func _apply_turret_type():
	match turret_type:
		TurretType.BASIC:
			damage = 10.0
			fire_rate = 0.2
		TurretType.HEAVY:
			damage = 30.0
			fire_rate = 0.5
			# Make barrel thicker
			if barrel_mesh and barrel_mesh.mesh is CylinderMesh:
				(barrel_mesh.mesh as CylinderMesh).top_radius = 0.08
				(barrel_mesh.mesh as CylinderMesh).bottom_radius = 0.1
		TurretType.FLAME:
			damage = 5.0
			fire_rate = 0.05
			detection_range = 10.0
			# Orange color for flame turret
			if head_mesh and head_mesh.material_override:
				(head_mesh.material_override as StandardMaterial3D).albedo_color = Color(0.8, 0.4, 0.1)
		TurretType.TESLA:
			damage = 15.0
			fire_rate = 1.0
			detection_range = 25.0
			# Blue for tesla
			if head_mesh and head_mesh.material_override:
				(head_mesh.material_override as StandardMaterial3D).albedo_color = Color(0.2, 0.3, 0.8)
				(head_mesh.material_override as StandardMaterial3D).emission_enabled = true
				(head_mesh.material_override as StandardMaterial3D).emission = Color(0.3, 0.5, 1.0)

func _process(delta):
	if not is_active:
		return

	shoot_timer = max(shoot_timer - delta, 0)

	# Find closest valid target
	_update_target()

	# Rotate towards target
	if current_target and is_instance_valid(current_target):
		_rotate_towards_target(delta)

		# Shoot when aimed
		if shoot_timer <= 0 and _is_aimed_at_target():
			_fire()

func _update_target():
	if current_target and is_instance_valid(current_target):
		# Check if still in range and alive
		var dist = global_position.distance_to(current_target.global_position)
		if dist > detection_range or not _is_valid_target(current_target):
			current_target = null
			target_lost.emit()

	if not current_target:
		# Find new target
		var closest_dist = INF
		var closest_target: Node3D = null

		for body in detection_area.get_overlapping_bodies():
			if _is_valid_target(body):
				var dist = global_position.distance_to(body.global_position)
				if dist < closest_dist:
					closest_dist = dist
					closest_target = body

		if closest_target:
			current_target = closest_target
			target_acquired.emit(current_target)

func _is_valid_target(body: Node3D) -> bool:
	if not body.is_in_group("zombie"):
		return false
	if body.has_method("is_dead") and body.is_dead():
		return false
	if "current_health" in body and body.current_health <= 0:
		return false
	return true

func _rotate_towards_target(delta):
	if not current_target or not head_mesh:
		return

	var target_pos = current_target.global_position
	target_pos.y = head_mesh.global_position.y  # Only rotate on Y axis

	var direction = (target_pos - head_mesh.global_position).normalized()
	var target_rotation = atan2(direction.x, direction.z)

	head_mesh.rotation.y = lerp_angle(head_mesh.rotation.y, target_rotation, rotation_speed * delta)

func _is_aimed_at_target() -> bool:
	if not current_target or not muzzle_point:
		return false

	var to_target = (current_target.global_position - muzzle_point.global_position).normalized()
	var forward = -muzzle_point.global_transform.basis.z

	return forward.dot(to_target) > 0.95  # Within ~18 degrees

func _fire():
	shoot_timer = fire_rate
	fired.emit()

	match turret_type:
		TurretType.BASIC, TurretType.HEAVY:
			_fire_bullet()
		TurretType.FLAME:
			_fire_flame()
		TurretType.TESLA:
			_fire_tesla()

func _fire_bullet():
	if not current_target:
		return

	# Raycast hit
	var from = muzzle_point.global_position
	var to = current_target.global_position + Vector3(0, 0.5, 0)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b0101  # Environment and Zombies
	query.exclude = [self]

	var result = space_state.intersect_ray(query)

	if result and result.collider == current_target:
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage, result.position)

	# Muzzle flash
	_spawn_muzzle_flash()

	# Tracer effect
	_spawn_tracer(from, to)

func _fire_flame():
	# Cone of fire damage
	for body in detection_area.get_overlapping_bodies():
		if _is_valid_target(body):
			var dist = global_position.distance_to(body.global_position)
			if dist <= detection_range * 0.5:  # Shorter range for flame
				var to_target = (body.global_position - global_position).normalized()
				var forward = -muzzle_point.global_transform.basis.z
				if forward.dot(to_target) > 0.5:  # In front arc
					if body.has_method("take_damage"):
						body.take_damage(damage, body.global_position)
					if body.has_method("apply_burn"):
						body.apply_burn(2.0)

	# Flame particles
	_spawn_flame_effect()

func _fire_tesla():
	if not current_target:
		return

	# Chain lightning to nearby enemies
	var hit_targets = [current_target]
	var chain_range = 8.0
	var chains_remaining = 3

	var last_target = current_target

	while chains_remaining > 0:
		var next_target = null
		var closest_dist = INF

		for body in detection_area.get_overlapping_bodies():
			if _is_valid_target(body) and body not in hit_targets:
				var dist = last_target.global_position.distance_to(body.global_position)
				if dist < chain_range and dist < closest_dist:
					closest_dist = dist
					next_target = body

		if next_target:
			hit_targets.append(next_target)
			_spawn_lightning(last_target.global_position, next_target.global_position)
			last_target = next_target
			chains_remaining -= 1
		else:
			break

	# Apply damage to all hit targets
	for target in hit_targets:
		if target.has_method("take_damage"):
			target.take_damage(damage, target.global_position)

	# Initial lightning from turret
	_spawn_lightning(muzzle_point.global_position, current_target.global_position)

func _spawn_muzzle_flash():
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.3)
	light.light_energy = 3.0
	light.omni_range = 3.0
	light.global_position = muzzle_point.global_position
	get_tree().current_scene.add_child(light)

	var tween = create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.05)
	tween.tween_callback(light.queue_free)

func _spawn_tracer(from: Vector3, to: Vector3):
	var line = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(from)
	immediate_mesh.surface_add_vertex(to)
	immediate_mesh.surface_end()

	line.mesh = immediate_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = mat

	get_tree().current_scene.add_child(line)

	var tween = create_tween()
	tween.tween_interval(0.05)
	tween.tween_callback(line.queue_free)

func _spawn_flame_effect():
	# Simple flame particles
	var particles = GPUParticles3D.new()
	particles.global_position = muzzle_point.global_position
	particles.global_rotation = muzzle_point.global_rotation
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.5
	particles.amount = 20
	particles.lifetime = 0.5

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = Vector3(0, 0, -1)
	material.spread = 15.0
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 12.0
	material.gravity = Vector3(0, 1, 0)
	material.color = Color(1.0, 0.5, 0.1)
	particles.process_material = material

	get_tree().current_scene.add_child(particles)

	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_callback(particles.queue_free)

func _spawn_lightning(from: Vector3, to: Vector3):
	# Create jagged lightning line
	var line = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var segments = 8
	var direction = to - from
	var segment_length = direction.length() / segments

	immediate_mesh.surface_add_vertex(from)

	for i in range(1, segments):
		var point = from + direction.normalized() * segment_length * i
		point += Vector3(
			randf_range(-0.3, 0.3),
			randf_range(-0.3, 0.3),
			randf_range(-0.3, 0.3)
		)
		immediate_mesh.surface_add_vertex(point)

	immediate_mesh.surface_add_vertex(to)
	immediate_mesh.surface_end()

	line.mesh = immediate_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.7, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.6, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = mat

	get_tree().current_scene.add_child(line)

	var tween = create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(line.queue_free)

func _on_target_entered(body: Node3D):
	if not current_target and _is_valid_target(body):
		current_target = body
		target_acquired.emit(body)

func _on_target_exited(body: Node3D):
	if body == current_target:
		current_target = null
		target_lost.emit()

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	current_health -= amount
	current_health = max(current_health, 0)

	# Flash red
	if head_mesh and head_mesh.material_override:
		var mat = head_mesh.material_override as StandardMaterial3D
		var original_color = mat.albedo_color
		var tween = create_tween()
		tween.tween_property(mat, "albedo_color", Color.RED, 0.1)
		tween.tween_property(mat, "albedo_color", original_color, 0.1)

	if current_health <= 0:
		destroy()

func destroy():
	is_active = false
	destroyed.emit()

	# Explosion effect
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_explosion"):
		vfx.spawn_explosion(global_position, 2.0)

	# Notify
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Turret destroyed!")

	queue_free()

func repair(amount: float):
	current_health = min(current_health + amount, max_health)

func get_health_percent() -> float:
	return current_health / max_health if max_health > 0 else 0.0

# Static factory for creating turrets
static func create_turret(type: TurretType = TurretType.BASIC) -> Turret:
	var turret = Turret.new()
	turret.turret_type = type
	return turret
