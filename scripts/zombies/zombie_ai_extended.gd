extends CharacterBody3D
class_name ZombieExtended

@export var max_health: float = 50.0
@export var move_speed: float = 3.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var detection_range: float = 20.0
@export var armor: float = 0.0
@export var loot_items: Array = []  # Array of ItemDataExtended
@export var experience_reward: int = 50

var current_health: float = 50.0
var target: Node3D = null
var attack_timer: float = 0.0
var is_attacking: bool = false
var is_dead: bool = false
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var model: Node3D = $Model if has_node("Model") else null
@onready var status_effects = $StatusEffectSystem if has_node("StatusEffectSystem") else null  # StatusEffectSystem
@onready var head_hitbox: Area3D = $HeadHitbox if has_node("HeadHitbox") else null

signal zombie_died(zombie: ZombieExtended)

func _ready():
	add_to_group("zombies")
	current_health = max_health
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = attack_range

	# Setup status effect system
	if not status_effects:
		status_effects = StatusEffectSystem.new()
		add_child(status_effects)

	# Find player
	await get_tree().create_timer(0.1).timeout
	find_target()

func _physics_process(delta):
	if is_dead:
		return

	attack_timer = max(attack_timer - delta, 0)

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# Find target if we don't have one
	if not target or not is_instance_valid(target):
		find_target()

	if target and is_instance_valid(target):
		var distance_to_target = global_position.distance_to(target.global_position)

		# Check if target is in detection range
		if distance_to_target <= detection_range:
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
			# Idle/Wander
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)

	move_and_slide()

	# Update animation
	update_animation()

func find_target():
	# Find player
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]
	else:
		# Target sigil if no player
		var sigils = get_tree().get_nodes_in_group("sigil")
		if sigils.size() > 0:
			target = sigils[0]

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

	# Visual feedback
	flash_red()

	if current_health <= 0:
		die()

func take_damage_advanced(damage_instance: DamageCalculator.DamageInstance):
	if is_dead:
		return

	# Apply damage
	take_damage(damage_instance.total_damage)

	# Apply status effects
	if damage_instance.bleed_damage > 0 and status_effects:
		status_effects.apply_effect("bleed", damage_instance.bleed_damage, 5.0)

	if damage_instance.poison_damage > 0 and status_effects:
		status_effects.apply_effect("poison", damage_instance.poison_damage, 10.0)

func flash_red():
	if model:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.RED
		# Would apply to model mesh

		await get_tree().create_timer(0.1).timeout
		# Restore original material

func apply_status_effect(effect_type: String, damage_per_second: float, duration: float):
	if status_effects:
		status_effects.apply_effect(effect_type, damage_per_second, duration)

func get_armor() -> float:
	return armor

func die():
	if is_dead:
		return

	is_dead = true
	zombie_died.emit(self)

	# Reward player with experience
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0].has_node("CharacterStats"):
		var stats: CharacterStats = players[0].get_node("CharacterStats")
		stats.add_experience(experience_reward)

	# Play death animation
	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")

	# Disable collision
	collision_layer = 0
	collision_mask = 0

	# Drop loot
	drop_loot()

	# Remove after a delay
	await get_tree().create_timer(5.0).timeout
	queue_free()

func drop_loot():
	if loot_items.size() > 0:
		# Random chance to drop item based on rarity
		var drop_chance = randf()

		if drop_chance < 0.5:  # 50% base drop chance
			var random_item = loot_items[randi() % loot_items.size()]

			# Rarity affects drop chance
			# Rarity enum: COMMON=0, UNCOMMON=1, RARE=2, EPIC=3, LEGENDARY=4, MYTHIC=5
			var rarity_mult = 1.0
			match random_item.rarity:
				0: rarity_mult = 1.0    # COMMON
				1: rarity_mult = 0.7    # UNCOMMON
				2: rarity_mult = 0.4    # RARE
				3: rarity_mult = 0.2    # EPIC
				4: rarity_mult = 0.05   # LEGENDARY
				5: rarity_mult = 0.01   # MYTHIC

			if randf() < rarity_mult:
				spawn_loot_item(random_item)

func spawn_loot_item(item_data):  # ItemDataExtended
	# Create loot node
	var loot = preload("res://scenes/items/loot_item.tscn").instantiate()
	get_parent().add_child(loot)
	loot.global_position = global_position + Vector3(0, 0.5, 0)
	if loot.has_method("set_item_data"):
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
