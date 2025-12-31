extends CharacterBody3D
class_name Zombie

# JetBoom-style Zombie AI with priority targeting:
# 1. Sigil (highest priority - must protect at all costs)
# 2. Props (barricades, crates, etc.)
# 3. Barricades (blocking paths)
# 4. Players (lowest priority target)

@export var max_health: float = 50.0
@export var move_speed: float = 3.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var detection_range: float = 50.0  # Increased for better targeting
@export var loot_items: Array[ItemData] = []

# Zombie class data (set by wave manager)
var zombie_class: String = "Shambler"
var armor: float = 0.0
var has_poison: bool = false
var poison_damage: float = 0.0
var has_explosion: bool = false
var explosion_damage: float = 0.0
var explosion_radius: float = 0.0
var tint_color: Color = Color.WHITE
var model_scale: float = 1.0

var current_health: float = 50.0
var target: Node3D = null
var target_type: String = "none"  # "sigil", "prop", "barricade", "player"
var attack_timer: float = 0.0
var is_attacking: bool = false
var is_dead: bool = false
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Pathfinding
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model if has_node("Model") else null
var animation_player: AnimationPlayer = null

# Target re-evaluation timer
var target_eval_timer: float = 0.0
const TARGET_EVAL_INTERVAL: float = 1.0

# Points/XP awarded on death
@export var kill_points: int = 50
@export var kill_experience: int = 10

signal zombie_died(zombie: Zombie, points: int, experience: int)

func _ready():
	add_to_group("zombies")
	current_health = max_health
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = attack_range

	# Find animation player in model or as child
	_find_animation_player()

	# Apply visual customization
	_apply_visual_settings()

	# Find initial target
	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(self):
		return
	find_target()

func _find_animation_player():
	# Check direct child first
	if has_node("AnimationPlayer"):
		animation_player = $AnimationPlayer
		return

	# Search in model
	if model:
		animation_player = _search_for_animation_player(model)

	if animation_player:
		print("[Zombie] Found AnimationPlayer: ", animation_player.name)

func _search_for_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var result = _search_for_animation_player(child)
		if result:
			return result

	return null

func _physics_process(delta):
	if is_dead:
		return

	attack_timer = max(attack_timer - delta, 0)

	# Periodically re-evaluate target (JetBoom style - always seek best target)
	target_eval_timer -= delta
	if target_eval_timer <= 0:
		target_eval_timer = TARGET_EVAL_INTERVAL
		find_target()

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# Find target if we don't have one
	if not target or not is_instance_valid(target):
		find_target()

	# Check if current target is still valid
	if target and is_instance_valid(target):
		# Check if target is dead/destroyed
		if _is_target_dead(target):
			find_target()

	if target and is_instance_valid(target):
		var distance_to_target = global_position.distance_to(target.global_position)

		# Always pursue target (JetBoom zombies are relentless)
		navigation_agent.target_position = target.global_position

		# Check if in attack range
		if distance_to_target <= attack_range:
			if attack_timer <= 0:
				attack_target()
			velocity.x = 0
			velocity.z = 0
			look_at_target()
		else:
			# Move toward target
			move_toward_target(delta)
	else:
		# No target - move toward center/sigil area
		var sigils = get_tree().get_nodes_in_group("sigil")
		if sigils.size() > 0:
			navigation_agent.target_position = sigils[0].global_position
			move_toward_target(delta)
		else:
			# Idle/Wander
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)

	move_and_slide()

	# Update animation
	update_animation()

func _is_target_dead(check_target: Node3D) -> bool:
	"""Check if target is dead or destroyed"""
	if not is_instance_valid(check_target):
		return true
	if "is_dead" in check_target and check_target.is_dead:
		return true
	if "current_health" in check_target and check_target.current_health <= 0:
		return true
	if "is_destroyed" in check_target and check_target.is_destroyed:
		return true
	return false

func find_target():
	"""JetBoom-style targeting priority:
	1. Sigil (main objective - zombies want to destroy it)
	2. Props blocking path to sigil
	3. Barricades blocking path
	4. Players (last priority - sigil is more important)
	"""
	var best_target: Node3D = null
	var best_priority: int = 999
	var best_distance: float = INF

	# Priority 1: Sigil (highest priority)
	var sigils = get_tree().get_nodes_in_group("sigil")
	for sigil in sigils:
		if not is_instance_valid(sigil):
			continue
		if _is_target_dead(sigil):
			continue
		var dist = global_position.distance_to(sigil.global_position)
		# Check if path is clear to sigil
		if _has_clear_path(sigil.global_position):
			if 1 < best_priority or (1 == best_priority and dist < best_distance):
				best_target = sigil
				best_priority = 1
				best_distance = dist
				target_type = "sigil"

	# Priority 2: Props blocking path (crates, barrels)
	var props = get_tree().get_nodes_in_group("props")
	for prop in props:
		if not is_instance_valid(prop):
			continue
		if _is_target_dead(prop):
			continue
		var dist = global_position.distance_to(prop.global_position)
		if dist <= detection_range:
			# Check if prop is between us and the sigil
			if _is_blocking_path(prop) or dist < 8.0:
				if 2 < best_priority or (2 == best_priority and dist < best_distance):
					best_target = prop
					best_priority = 2
					best_distance = dist
					target_type = "prop"

	# Priority 3: Barricades
	var barricades = get_tree().get_nodes_in_group("barricades")
	for barricade in barricades:
		if not is_instance_valid(barricade):
			continue
		if _is_target_dead(barricade):
			continue
		var dist = global_position.distance_to(barricade.global_position)
		if dist <= detection_range:
			if _is_blocking_path(barricade) or dist < 5.0:
				if 3 < best_priority or (3 == best_priority and dist < best_distance):
					best_target = barricade
					best_priority = 3
					best_distance = dist
					target_type = "barricade"

	# Priority 4: Players (lowest priority)
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if not is_instance_valid(player):
			continue
		if _is_target_dead(player):
			continue
		var dist = global_position.distance_to(player.global_position)
		# Only target players if very close or if no other targets
		if dist <= 10.0 or best_priority > 4:
			if 4 < best_priority or (4 == best_priority and dist < best_distance):
				best_target = player
				best_priority = 4
				best_distance = dist
				target_type = "player"

	# Set target
	if best_target:
		target = best_target
	elif sigils.size() > 0:
		# Fallback - always go for sigil
		target = sigils[0]
		target_type = "sigil"

func _has_clear_path(pos: Vector3) -> bool:
	"""Check if we have a clear path to position"""
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, pos + Vector3.UP)
	query.exclude = [self]
	query.collision_mask = 0b00101  # Environment and barricades
	var result = space_state.intersect_ray(query)
	return result.is_empty()

func _is_blocking_path(obstacle: Node3D) -> bool:
	"""Check if obstacle is between us and our main target (sigil)"""
	var sigils = get_tree().get_nodes_in_group("sigil")
	if sigils.is_empty():
		return false

	var sigil_pos = sigils[0].global_position
	var obstacle_pos = obstacle.global_position
	var my_pos = global_position

	# Simple check: is obstacle roughly on the line between us and sigil?
	var to_sigil = (sigil_pos - my_pos).normalized()
	var to_obstacle = (obstacle_pos - my_pos).normalized()
	var dot = to_sigil.dot(to_obstacle)

	# If dot > 0.7, obstacle is roughly in the direction of the sigil
	return dot > 0.5

func move_toward_target(_delta):
	if navigation_agent.is_navigation_finished():
		return

	var next_position = navigation_agent.get_next_path_position()
	var direction = (next_position - global_position).normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	# Look at movement direction
	if direction.length() > 0:
		look_at(global_position + direction, Vector3.UP)

func look_at_target():
	if target and is_instance_valid(target):
		var target_pos = target.global_position
		target_pos.y = global_position.y
		look_at(target_pos, Vector3.UP)

func attack_target():
	if not target or not is_instance_valid(target):
		return

	is_attacking = true
	attack_timer = attack_cooldown

	# Play attack animation
	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")

	# Deal damage after a delay (animation hit frame)
	await get_tree().create_timer(0.5).timeout

	if target and is_instance_valid(target) and global_position.distance_to(target.global_position) <= attack_range:
		if target.has_method("take_damage"):
			target.take_damage(attack_damage, global_position)

	is_attacking = false

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	if is_dead:
		return

	current_health -= amount
	current_health = max(current_health, 0)

	# Play hurt animation
	if animation_player and animation_player.has_animation("hurt") and not is_attacking:
		animation_player.play("hurt")

	if current_health <= 0:
		die()

func die():
	if is_dead:
		return

	is_dead = true

	# Handle explosion on death (Exploder zombie type)
	if has_explosion and explosion_damage > 0:
		_explode_on_death()

	# Handle poison cloud on death (Poison zombie type)
	if has_poison and poison_damage > 0:
		_spawn_poison_cloud()

	zombie_died.emit(self, kill_points, kill_experience)

	# Spawn gore effects
	if has_node("/root/GoreSystem"):
		get_node("/root/GoreSystem").spawn_death_effect(global_position)

	# Play death animation
	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")

	# Disable collision
	collision_layer = 0
	collision_mask = 0

	# Drop loot
	drop_loot()

	# Notify points system
	if has_node("/root/PointsSystem"):
		var points_system = get_node("/root/PointsSystem")
		points_system.reward_zombie_kill(zombie_class)

	# Remove after a delay
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(self):
		queue_free()

func _explode_on_death():
	"""Exploder zombie - damages nearby targets on death"""
	# Spawn explosion VFX
	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_explosion(global_position, explosion_radius)

	# Play explosion sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("explosion", global_position, 1.0)

	# Damage nearby entities
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 0b00111  # Environment, players, zombies

	var results = space_state.intersect_shape(query, 32)
	for result in results:
		var collider = result.collider
		if collider == self:
			continue
		if collider.has_method("take_damage"):
			var dist = global_position.distance_to(collider.global_position)
			var damage_falloff = 1.0 - (dist / explosion_radius)
			var final_damage = explosion_damage * max(damage_falloff, 0.3)
			collider.take_damage(final_damage, global_position)

func _spawn_poison_cloud():
	"""Poison zombie - leaves damage cloud on death"""
	# Create poison area
	var poison_area = Area3D.new()
	poison_area.global_position = global_position

	var collision = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 4.0
	collision.shape = sphere
	poison_area.add_child(collision)

	# Poison cloud visual
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.amount = 50
	particles.lifetime = 1.5
	particles.explosiveness = 0.0

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 3.0
	mat.gravity = Vector3(0, 0.5, 0)
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.color = Color(0.2, 0.8, 0.2, 0.5)
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	particles.process_material = mat
	poison_area.add_child(particles)

	var scene = get_tree().current_scene
	if scene:
		scene.add_child(poison_area)

		# Damage over time for 5 seconds
		var damage_ticks = 10
		for i in range(damage_ticks):
			await get_tree().create_timer(0.5).timeout
			if not is_instance_valid(poison_area):
				break
			var bodies = poison_area.get_overlapping_bodies()
			for body in bodies:
				if body.is_in_group("player") and body.has_method("take_damage"):
					body.take_damage(poison_damage * 0.5, global_position)

		if is_instance_valid(poison_area):
			poison_area.queue_free()

func drop_loot():
	if loot_items.size() > 0:
		# Random chance to drop item
		if randf() < 0.3:  # 30% chance
			var random_item = loot_items[randi() % loot_items.size()]
			spawn_loot_item(random_item)

func spawn_loot_item(item_data: ItemData):
	# Create loot node
	var loot = preload("res://scenes/items/loot_item.tscn").instantiate()
	get_parent().add_child(loot)
	loot.global_position = global_position + Vector3(0, 0.5, 0)
	loot.set_item_data(item_data)

func update_animation():
	if not animation_player:
		return

	if is_dead:
		return

	if is_attacking:
		return

	var vel_length = Vector3(velocity.x, 0, velocity.z).length()

	if vel_length > 0.1:
		if animation_player.has_animation("walk"):
			if animation_player.current_animation != "walk":
				animation_player.play("walk")
	else:
		if animation_player.has_animation("idle"):
			if animation_player.current_animation != "idle":
				animation_player.play("idle")

# ============================================
# ZOMBIE CLASS SETUP (Called by WaveManager)
# ============================================

func setup_from_class(class_data: ZombieClassData, wave: int):
	"""Configure zombie from class data - called by WaveManager"""
	if not class_data:
		return

	zombie_class = class_data.display_name

	# Apply wave scaling
	var health_scale = 1.0 + (wave * 0.1)
	var damage_scale = 1.0 + (wave * 0.08)
	var armor_scale = wave * 0.5

	# Base stats
	max_health = class_data.base_health * health_scale
	current_health = max_health
	move_speed = class_data.base_move_speed
	attack_damage = class_data.base_damage * damage_scale
	armor = class_data.base_armor + armor_scale

	# Special abilities
	has_poison = class_data.has_poison
	poison_damage = class_data.poison_damage_per_second if class_data.has_poison else 0.0

	has_explosion = class_data.has_explosion
	explosion_damage = class_data.explosion_damage if class_data.has_explosion else 0.0
	explosion_radius = class_data.explosion_radius if class_data.has_explosion else 0.0

	# Visual
	tint_color = class_data.tint_color
	model_scale = class_data.model_scale

	# Points
	kill_points = class_data.points_reward
	kill_experience = class_data.experience_reward

	# Apply visual settings
	_apply_visual_settings()

func _apply_visual_settings():
	"""Apply tint color and scale to model"""
	if model:
		model.scale = Vector3.ONE * model_scale

		# Apply tint to all mesh instances
		_apply_tint_recursive(model, tint_color)

func _apply_tint_recursive(node: Node, color: Color):
	"""Recursively apply tint to all MeshInstance3D children"""
	if node is MeshInstance3D:
		var mesh_inst = node as MeshInstance3D
		# Create material override if none exists
		if not mesh_inst.material_override:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			mesh_inst.material_override = mat
		elif mesh_inst.material_override is StandardMaterial3D:
			var mat = mesh_inst.material_override as StandardMaterial3D
			mat.albedo_color = mat.albedo_color * color

	for child in node.get_children():
		_apply_tint_recursive(child, color)

# ============================================
# DAMAGE HELPERS
# ============================================

func get_armor() -> float:
	return armor

func apply_status_effect(effect_type: String, damage_per_second: float, duration: float):
	"""Apply status effect (bleed, poison, etc.)"""
	# Simple status effect implementation
	if effect_type == "bleed" or effect_type == "poison":
		_apply_dot(damage_per_second, duration)

func _apply_dot(dps: float, duration: float):
	"""Apply damage over time"""
	var ticks = int(duration * 2)  # Tick every 0.5 seconds
	for i in range(ticks):
		await get_tree().create_timer(0.5).timeout
		if is_dead or not is_instance_valid(self):
			return
		take_damage(dps * 0.5, global_position)
