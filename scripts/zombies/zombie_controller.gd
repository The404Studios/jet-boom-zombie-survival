extends CharacterBody3D
class_name ZombieController

@export var zombie_class_data: ZombieClassData

var max_health: float = 100.0
var current_health: float = 100.0
var move_speed: float = 3.0
var attack_damage: float = 10.0
var attack_range: float = 2.0
var attack_speed: float = 1.5
var armor: float = 0.0
var points_reward: int = 100
var experience_reward: int = 50

var current_wave: int = 1
var target: Node3D = null
var attack_timer: float = 0.0
var ability_timer: float = 0.0
var is_attacking: bool = false
var is_dead: bool = false
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Special Abilities
var has_poison: bool = false
var poison_dps: float = 0.0
var has_explosion: bool = false
var explosion_damage: float = 0.0
var explosion_radius: float = 0.0
var has_ranged_attack: bool = false
var ranged_damage: float = 0.0
var ranged_range: float = 0.0
var ranged_cooldown: float = 3.0
var buff_nearby: bool = false
var buff_radius: float = 10.0
var buff_amount: float = 0.2

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model if has_node("Model") else null
@onready var status_effects: StatusEffectSystem = $StatusEffectSystem if has_node("StatusEffectSystem") else null
@onready var mesh_instance: MeshInstance3D = $Model/MeshInstance3D if has_node("Model/MeshInstance3D") else null
var animation_player: AnimationPlayer = null

signal zombie_died(zombie: ZombieController, points: int, experience: int)
signal zombie_damaged(zombie: ZombieController, damage: float)
signal ability_used(zombie: ZombieController, ability_type: String)

func _ready():
	add_to_group("zombies")

	if not status_effects:
		status_effects = StatusEffectSystem.new()
		add_child(status_effects)

	# Find animation player (may be in model)
	_find_animation_player()

	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = attack_range

	# Apply visual tint
	apply_visual_tint()

	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(self):
		return
	find_target()

	# Buff nearby zombies if screamer
	if buff_nearby:
		start_buff_loop()

func _find_animation_player():
	# Check direct child first
	if has_node("AnimationPlayer"):
		animation_player = $AnimationPlayer
		return

	# Search in model
	if model:
		animation_player = _search_for_animation_player(model)

func _search_for_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var result = _search_for_animation_player(child)
		if result:
			return result

	return null

func setup_from_class(class_data: ZombieClassData, wave: int):
	zombie_class_data = class_data
	current_wave = wave

	# Apply scaled stats
	max_health = class_data.get_scaled_health(wave)
	current_health = max_health
	move_speed = class_data.base_move_speed
	attack_damage = class_data.get_scaled_damage(wave)
	attack_range = class_data.attack_range
	attack_speed = class_data.attack_speed
	armor = class_data.get_scaled_armor(wave)
	points_reward = class_data.get_points_for_wave(wave)
	experience_reward = class_data.experience_reward

	# Special abilities
	has_poison = class_data.has_poison
	poison_dps = class_data.poison_damage_per_second
	has_explosion = class_data.has_explosion
	explosion_damage = class_data.explosion_damage
	explosion_radius = class_data.explosion_radius
	has_ranged_attack = class_data.has_ranged_attack
	ranged_damage = class_data.ranged_damage
	ranged_range = class_data.ranged_range
	ranged_cooldown = class_data.ranged_attack_cooldown
	buff_nearby = class_data.buff_nearby_zombies
	buff_radius = class_data.buff_radius
	buff_amount = class_data.buff_amount

	# Scale model
	if model and class_data.model_scale != 1.0:
		model.scale = Vector3.ONE * class_data.model_scale

	apply_visual_tint()

func apply_visual_tint():
	if not zombie_class_data or not mesh_instance:
		return

	var mat = StandardMaterial3D.new()
	mat.albedo_color = zombie_class_data.tint_color

	if zombie_class_data.emission_strength > 0:
		mat.emission_enabled = true
		mat.emission = zombie_class_data.emission_color
		mat.emission_energy_multiplier = zombie_class_data.emission_strength

	mesh_instance.material_override = mat

func _physics_process(delta):
	if is_dead:
		return

	attack_timer = max(attack_timer - delta, 0)
	ability_timer = max(ability_timer - delta, 0)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# Find target
	if not target or not is_instance_valid(target):
		find_target()

	if target and is_instance_valid(target):
		var distance_to_target = global_position.distance_to(target.global_position)

		# Use ranged attack if available
		if has_ranged_attack and distance_to_target <= ranged_range and ability_timer <= 0:
			use_ranged_attack()
		elif distance_to_target <= attack_range:
			# Melee attack
			if attack_timer <= 0:
				attack_target()
			velocity.x = 0
			velocity.z = 0
			look_at_target()
		else:
			# Move toward target
			navigation_agent.target_position = target.global_position
			move_toward_target(delta)

	move_and_slide()
	update_animation()

func find_target():
	"""
	JetBoom targeting priority:
	1. Sigil (primary objective)
	2. Props (secondary targets)
	3. Barricades (player-built obstacles)
	4. Players (if they get too close or are blocking path)
	"""

	# Priority 1: Sigil (always primary target)
	var sigils = get_tree().get_nodes_in_group("sigil")
	if sigils.size() > 0:
		target = sigils[0]
		return

	# Priority 2: Props (secondary targets blocking path to sigil)
	var props = get_tree().get_nodes_in_group("props")
	if props.size() > 0:
		var closest_prop = null
		var closest_distance = INF

		for prop in props:
			if not is_instance_valid(prop):
				continue
			var dist = global_position.distance_to(prop.global_position)
			if dist < closest_distance and dist < 5.0:  # Only target nearby props
				closest_distance = dist
				closest_prop = prop

		if closest_prop:
			target = closest_prop
			return

	# Priority 3: Barricades (player-built obstacles)
	var barricades = get_tree().get_nodes_in_group("barricades")
	if barricades.size() > 0:
		var closest_barricade = null
		var closest_distance = INF

		for barricade in barricades:
			if not is_instance_valid(barricade):
				continue
			var dist = global_position.distance_to(barricade.global_position)
			if dist < closest_distance and dist < 5.0:  # Only target nearby barricades
				closest_distance = dist
				closest_barricade = barricade

		if closest_barricade:
			target = closest_barricade
			return

	# Priority 4: Players (if very close or no other targets)
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var closest_player = null
		var closest_distance = INF

		for player in players:
			if not is_instance_valid(player):
				continue
			var dist = global_position.distance_to(player.global_position)
			if dist < closest_distance:
				closest_distance = dist
				closest_player = player

		# Only target players if they're close (within 10 units)
		if closest_player and closest_distance < 10.0:
			target = closest_player
			return

	# Fallback: No valid target found
	target = null

func move_toward_target(delta):
	if navigation_agent.is_navigation_finished():
		return

	var next_position = navigation_agent.get_next_path_position()
	var direction = (next_position - global_position).normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

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
	attack_timer = attack_speed

	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")

	await get_tree().create_timer(0.5).timeout

	if target and is_instance_valid(target) and global_position.distance_to(target.global_position) <= attack_range:
		if target.has_method("take_damage"):
			target.take_damage(attack_damage, global_position)

			# Apply poison
			if has_poison and target.has_method("apply_status_effect"):
				target.apply_status_effect("poison", poison_dps, 5.0)

	is_attacking = false

func use_ranged_attack():
	ability_timer = ranged_cooldown
	ability_used.emit(self, "ranged_attack")

	# Network replicate projectile spawning (or spawn directly in single-player)
	if not multiplayer.has_multiplayer_peer():
		_spawn_projectile(global_position, target.global_position if target else global_position + global_transform.basis.z * 10, ranged_damage)
	elif multiplayer.is_server():
		_spawn_projectile.rpc(global_position, target.global_position if target else global_position + global_transform.basis.z * 10, ranged_damage)

@rpc("authority", "call_local", "reliable")
func _spawn_projectile(spawn_pos: Vector3, target_pos: Vector3, damage: float):
	"""Network replicated projectile spawning"""
	var projectile = create_acid_projectile()
	if projectile:
		get_parent().add_child(projectile)
		projectile.global_position = spawn_pos + Vector3(0, 1.0, 0)
		projectile.launch_toward(target_pos, damage)

func create_acid_projectile() -> Node3D:
	"""Create acid projectile for ranged attack"""
	var projectile_scene = preload("res://scenes/projectiles/acid_projectile.tscn")
	var projectile = projectile_scene.instantiate()
	return projectile

func start_buff_loop():
	while not is_dead and buff_nearby and is_instance_valid(self):
		buff_nearby_zombies()
		await get_tree().create_timer(1.0).timeout
		# Safety check after await
		if not is_instance_valid(self):
			break

func buff_nearby_zombies():
	var zombies = get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if zombie == self or not is_instance_valid(zombie):
			continue

		var dist = global_position.distance_to(zombie.global_position)
		if dist <= buff_radius:
			# Apply temporary buff
			if zombie.has_method("apply_buff"):
				zombie.apply_buff("damage", buff_amount, 2.0)

func apply_buff(buff_type: String, amount: float, duration: float):
	# Apply temporary stat buff
	match buff_type:
		"damage":
			attack_damage *= (1.0 + amount)
			await get_tree().create_timer(duration).timeout
			attack_damage /= (1.0 + amount)
		"speed":
			move_speed *= (1.0 + amount)
			await get_tree().create_timer(duration).timeout
			move_speed /= (1.0 + amount)

func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO):
	if is_dead:
		return

	current_health -= amount
	current_health = max(current_health, 0)

	zombie_damaged.emit(self, amount)

	if animation_player and animation_player.has_animation("hurt") and not is_attacking:
		animation_player.play("hurt")

	flash_red()

	if current_health <= 0:
		die()

func take_damage_advanced(damage_instance: DamageCalculator.DamageInstance):
	if is_dead:
		return

	take_damage(damage_instance.total_damage)

	if damage_instance.bleed_damage > 0 and status_effects:
		status_effects.apply_effect("bleed", damage_instance.bleed_damage, 5.0)

	if damage_instance.poison_damage > 0 and status_effects:
		status_effects.apply_effect("poison", damage_instance.poison_damage, 10.0)

func flash_red():
	if mesh_instance:
		var original_mat = mesh_instance.material_override
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = Color.RED
		mesh_instance.material_override = flash_mat

		await get_tree().create_timer(0.1).timeout
		mesh_instance.material_override = original_mat

func die():
	if is_dead:
		return

	is_dead = true

	# Explosion on death
	if has_explosion:
		explode()

	zombie_died.emit(self, points_reward, experience_reward)

	# Reward players
	reward_nearby_players()

	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")

	collision_layer = 0
	collision_mask = 0

	drop_loot()

	await get_tree().create_timer(5.0).timeout
	queue_free()

func explode():
	ability_used.emit(self, "explosion")

	# Damage nearby entities
	var bodies = get_tree().get_nodes_in_group("player")
	bodies.append_array(get_tree().get_nodes_in_group("barricades"))

	for body in bodies:
		if not is_instance_valid(body):
			continue

		var dist = global_position.distance_to(body.global_position)
		if dist <= explosion_radius:
			var damage = explosion_damage * (1.0 - (dist / explosion_radius))
			if body.has_method("take_damage"):
				body.take_damage(damage, global_position)

	# Visual effect would go here

func reward_nearby_players():
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if not is_instance_valid(player):
			continue

		# Give experience
		if player.has_node("CharacterStats"):
			var stats: CharacterStats = player.get_node("CharacterStats")
			stats.add_experience(experience_reward)

		# Give points
		if player.has_method("add_points"):
			player.add_points(points_reward)

func drop_loot():
	"""Drop loot items when zombie dies"""
	if not zombie_class_data:
		return

	var drop_chance = 0.3 * zombie_class_data.loot_multiplier

	if zombie_class_data.guaranteed_drop or randf() < drop_chance:
		# Determine what to drop
		var drop_type = randf()

		if drop_type < 0.5:
			# Drop ammo
			_spawn_ammo_drop()
		elif drop_type < 0.8:
			# Drop health
			_spawn_health_drop()
		else:
			# Drop special item
			_spawn_special_drop()

func _spawn_ammo_drop():
	"""Spawn ammo pickup"""
	if has_node("/root/GameManager"):
		var arena = get_tree().get_first_node_in_group("arena")
		if arena and arena.has_method("spawn_ammo_pickup"):
			arena.spawn_ammo_pickup(global_position)

func _spawn_health_drop():
	"""Spawn health pickup"""
	if has_node("/root/GameManager"):
		var arena = get_tree().get_first_node_in_group("arena")
		if arena and arena.has_method("spawn_health_pickup"):
			arena.spawn_health_pickup(global_position)

func _spawn_special_drop():
	"""Spawn special loot item"""
	var loot_scene = preload("res://scenes/items/loot_item.tscn")
	var loot = loot_scene.instantiate()
	get_parent().add_child(loot)
	loot.global_position = global_position + Vector3(0, 0.5, 0)

func get_armor() -> float:
	return armor

func apply_status_effect(effect_type: String, damage_per_second: float, duration: float):
	if status_effects:
		status_effects.apply_effect(effect_type, damage_per_second, duration)

func update_animation():
	if not animation_player or is_dead or is_attacking:
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
