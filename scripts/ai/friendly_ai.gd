extends CharacterBody3D
class_name FriendlyAI

# Friendly AI companion that fights alongside the player

signal died
signal target_acquired(target: Node3D)
signal target_killed(target: Node3D)

enum AIType { SOLDIER, SNIPER, MEDIC, TANK }
enum AIState { IDLE, FOLLOWING, COMBAT, HEALING, DEAD }

@export var ai_type: AIType = AIType.SOLDIER
@export var ai_name: String = "Soldier"
@export var max_health: float = 100.0
@export var damage: float = 10.0
@export var fire_rate: float = 0.3
@export var move_speed: float = 4.0
@export var detection_range: float = 20.0
@export var follow_distance: float = 5.0
@export var attack_range: float = 15.0
@export var duration: float = 60.0  # How long AI lasts before despawning

var current_health: float = 100.0
var current_state: AIState = AIState.IDLE
var current_target: Node3D = null
var owner_player: Node = null
var shoot_timer: float = 0.0
var lifetime_timer: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Components
var mesh: MeshInstance3D
var nav_agent: NavigationAgent3D
var detection_area: Area3D
var weapon_point: Marker3D

func _ready():
	add_to_group("friendly_ai")
	add_to_group("player_ally")
	current_health = max_health
	lifetime_timer = duration

	_create_visuals()
	_setup_navigation()
	_setup_detection()
	_apply_ai_type()

func _create_visuals():
	# Body
	mesh = MeshInstance3D.new()
	mesh.name = "Body"
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	mesh.mesh = capsule
	mesh.position.y = 0.8
	add_child(mesh)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.2)  # Green for ally
	mesh.material_override = mat

	# Head
	var head = MeshInstance3D.new()
	head.name = "Head"
	var sphere = SphereMesh.new()
	sphere.radius = 0.2
	head.mesh = sphere
	head.position.y = 1.7
	add_child(head)
	head.material_override = mat

	# Weapon
	weapon_point = Marker3D.new()
	weapon_point.name = "WeaponPoint"
	weapon_point.position = Vector3(0.3, 1.2, -0.3)
	add_child(weapon_point)

	var weapon = MeshInstance3D.new()
	weapon.name = "Weapon"
	var box = BoxMesh.new()
	box.size = Vector3(0.05, 0.08, 0.4)
	weapon.mesh = box
	weapon_point.add_child(weapon)

	var weapon_mat = StandardMaterial3D.new()
	weapon_mat.albedo_color = Color(0.2, 0.2, 0.22)
	weapon_mat.metallic = 0.8
	weapon.material_override = weapon_mat

	# Name label
	var label = Label3D.new()
	label.name = "NameLabel"
	label.text = ai_name
	label.font_size = 24
	label.position.y = 2.1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.2, 0.8, 0.2)
	add_child(label)

	# Collision
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.6
	col.shape = shape
	col.position.y = 0.8
	add_child(col)

func _setup_navigation():
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.0
	add_child(nav_agent)

func _setup_detection():
	detection_area = Area3D.new()
	detection_area.name = "DetectionArea"
	add_child(detection_area)

	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = detection_range
	col.shape = sphere
	detection_area.add_child(col)

	detection_area.collision_layer = 0
	detection_area.collision_mask = 4  # Zombies

func _apply_ai_type():
	var mat = mesh.material_override as StandardMaterial3D

	match ai_type:
		AIType.SOLDIER:
			ai_name = "Soldier"
			damage = 10.0
			fire_rate = 0.3
			max_health = 100.0
			mat.albedo_color = Color(0.2, 0.5, 0.2)  # Green
		AIType.SNIPER:
			ai_name = "Sniper"
			damage = 40.0
			fire_rate = 1.5
			attack_range = 35.0
			max_health = 60.0
			mat.albedo_color = Color(0.4, 0.4, 0.5)  # Gray
		AIType.MEDIC:
			ai_name = "Medic"
			damage = 5.0
			fire_rate = 0.5
			max_health = 80.0
			mat.albedo_color = Color(0.8, 0.2, 0.2)  # Red cross
		AIType.TANK:
			ai_name = "Tank"
			damage = 20.0
			fire_rate = 0.6
			max_health = 250.0
			move_speed = 2.5
			mat.albedo_color = Color(0.5, 0.4, 0.2)  # Brown/tan

	current_health = max_health

	# Update name label
	var label = get_node_or_null("NameLabel")
	if label:
		label.text = ai_name

func _physics_process(delta):
	if current_state == AIState.DEAD:
		return

	# Lifetime countdown
	lifetime_timer -= delta
	if lifetime_timer <= 0:
		_expire()
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Update timers
	shoot_timer = max(shoot_timer - delta, 0)

	# State machine
	match current_state:
		AIState.IDLE:
			_state_idle(delta)
		AIState.FOLLOWING:
			_state_following(delta)
		AIState.COMBAT:
			_state_combat(delta)
		AIState.HEALING:
			_state_healing(delta)

	move_and_slide()

func _state_idle(_delta):
	# Look for owner or threats
	if owner_player and is_instance_valid(owner_player):
		var dist = global_position.distance_to(owner_player.global_position)
		if dist > follow_distance:
			current_state = AIState.FOLLOWING

	_scan_for_targets()
	if current_target:
		current_state = AIState.COMBAT

func _state_following(delta):
	if not owner_player or not is_instance_valid(owner_player):
		current_state = AIState.IDLE
		return

	# Check for threats first
	_scan_for_targets()
	if current_target:
		current_state = AIState.COMBAT
		return

	# Move towards owner
	var dist = global_position.distance_to(owner_player.global_position)
	if dist <= follow_distance:
		current_state = AIState.IDLE
		velocity.x = 0
		velocity.z = 0
		return

	nav_agent.target_position = owner_player.global_position

	if not nav_agent.is_navigation_finished():
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		direction.y = 0

		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

		# Face movement direction
		if direction.length() > 0.1:
			look_at(global_position + direction, Vector3.UP)

func _state_combat(_delta):
	# Validate target
	if not current_target or not is_instance_valid(current_target):
		current_target = null
		current_state = AIState.FOLLOWING if owner_player else AIState.IDLE
		return

	# Check if target is dead
	if not _is_valid_target(current_target):
		target_killed.emit(current_target)
		current_target = null
		_scan_for_targets()
		if not current_target:
			current_state = AIState.FOLLOWING if owner_player else AIState.IDLE
		return

	# Face target
	var target_pos = current_target.global_position
	target_pos.y = global_position.y
	look_at(target_pos, Vector3.UP)

	var dist = global_position.distance_to(current_target.global_position)

	# Move towards target if too far
	if dist > attack_range:
		nav_agent.target_position = current_target.global_position
		if not nav_agent.is_navigation_finished():
			var next_pos = nav_agent.get_next_path_position()
			var direction = (next_pos - global_position).normalized()
			direction.y = 0
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
	else:
		velocity.x = 0
		velocity.z = 0

		# Shoot
		if shoot_timer <= 0:
			_fire_at_target()

func _state_healing(_delta):
	# Medic healing behavior
	if ai_type != AIType.MEDIC:
		current_state = AIState.FOLLOWING if owner_player else AIState.IDLE
		return

	# Find injured ally
	var heal_target = _find_injured_ally()
	if not heal_target:
		current_state = AIState.FOLLOWING if owner_player else AIState.IDLE
		return

	# Move to and heal
	var dist = global_position.distance_to(heal_target.global_position)
	if dist > 2.0:
		nav_agent.target_position = heal_target.global_position
		if not nav_agent.is_navigation_finished():
			var next_pos = nav_agent.get_next_path_position()
			var direction = (next_pos - global_position).normalized()
			direction.y = 0
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
	else:
		velocity.x = 0
		velocity.z = 0
		if shoot_timer <= 0:
			_heal_ally(heal_target)

func _scan_for_targets():
	var closest_dist = INF
	var closest_target: Node3D = null

	for body in detection_area.get_overlapping_bodies():
		if _is_valid_target(body):
			var dist = global_position.distance_to(body.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_target = body

	if closest_target and closest_target != current_target:
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

func _fire_at_target():
	if not current_target:
		return

	shoot_timer = fire_rate

	# Raycast
	var from = weapon_point.global_position
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

func _find_injured_ally() -> Node:
	var injured: Node = null
	var lowest_health = 1.0  # Percent

	# Check owner player
	if owner_player and is_instance_valid(owner_player):
		if "current_health" in owner_player and "max_health" in owner_player:
			var percent = owner_player.current_health / owner_player.max_health
			if percent < 0.8 and percent < lowest_health:
				lowest_health = percent
				injured = owner_player

	# Check other friendly AI
	for ally in get_tree().get_nodes_in_group("friendly_ai"):
		if ally == self:
			continue
		if "current_health" in ally and "max_health" in ally:
			var percent = ally.current_health / ally.max_health
			if percent < 0.8 and percent < lowest_health:
				lowest_health = percent
				injured = ally

	return injured

func _heal_ally(ally: Node):
	shoot_timer = 2.0  # Heal every 2 seconds

	var heal_amount = 15.0

	if ally.has_method("heal"):
		ally.heal(heal_amount)
	elif "current_health" in ally and "max_health" in ally:
		ally.current_health = min(ally.current_health + heal_amount, ally.max_health)

	# Heal effect
	_spawn_heal_effect(ally.global_position)

	if has_node("/root/ChatSystem"):
		var ally_name = ally.ai_name if "ai_name" in ally else "Player"
		get_node("/root/ChatSystem").emit_system_message("%s healed %s for %d HP" % [ai_name, ally_name, heal_amount])

func _spawn_muzzle_flash():
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.3)
	light.light_energy = 2.0
	light.omni_range = 2.0
	light.global_position = weapon_point.global_position
	get_tree().current_scene.add_child(light)

	var tween = create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.05)
	tween.tween_callback(light.queue_free)

func _spawn_heal_effect(pos: Vector3):
	var particles = GPUParticles3D.new()
	particles.global_position = pos + Vector3(0, 1, 0)
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 20
	particles.lifetime = 1.0

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5
	material.direction = Vector3(0, 1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 2.0
	material.gravity = Vector3(0, 0, 0)
	material.color = Color(0.2, 1.0, 0.2)
	particles.process_material = material

	get_tree().current_scene.add_child(particles)

	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	current_health -= amount
	current_health = max(current_health, 0)

	# Flash red
	if mesh and mesh.material_override:
		var mat = mesh.material_override as StandardMaterial3D
		var original_color = mat.albedo_color
		var tween = create_tween()
		tween.tween_property(mat, "albedo_color", Color.RED, 0.1)
		tween.tween_property(mat, "albedo_color", original_color, 0.1)

	if current_health <= 0:
		die()

func heal(amount: float):
	current_health = min(current_health + amount, max_health)

func die():
	current_state = AIState.DEAD
	died.emit()

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("%s has fallen!" % ai_name)

	# Death animation
	var tween = create_tween()
	tween.tween_property(self, "rotation:x", PI / 2, 0.3)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 1.0)
	tween.tween_callback(queue_free)

func _expire():
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("%s's summon duration expired" % ai_name)

	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 1.0)
	tween.tween_callback(queue_free)

func set_owner_player(player: Node):
	owner_player = player
	current_state = AIState.FOLLOWING

func get_health_percent() -> float:
	return current_health / max_health if max_health > 0 else 0.0

# Static factory
static func spawn_ally(type: AIType, spawn_position: Vector3, player: Node = null) -> FriendlyAI:
	var ally = FriendlyAI.new()
	ally.ai_type = type
	ally.global_position = spawn_position

	if player:
		ally.set_owner_player(player)

	return ally
