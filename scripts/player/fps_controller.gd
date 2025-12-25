extends CharacterBody3D

# Complete FPS controller with viewmodel integration
# Handles movement, looking, shooting, and weapon management
# Integrates with RPG systems: CharacterAttributes, SkillTree, PlayerConditions

@export var mouse_sensitivity: float = 0.003
@export var base_move_speed: float = 5.0
@export var base_sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 9.8
@export var interact_range: float = 3.0

# Nodes
@onready var camera: Camera3D = $Camera3D
@onready var viewmodel: Node3D = $Camera3D/Viewmodel
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay if has_node("Camera3D/InteractRay") else null
@onready var spectator_controller: SpectatorController = $SpectatorController if has_node("SpectatorController") else null

# RPG Systems
@onready var character_attributes: CharacterAttributes = $CharacterAttributes if has_node("CharacterAttributes") else null
@onready var skill_tree: SkillTree = $SkillTree if has_node("SkillTree") else null
@onready var equipment_system: EquipmentSystem = $EquipmentSystem if has_node("EquipmentSystem") else null
@onready var player_conditions: PlayerConditions = $PlayerConditions if has_node("PlayerConditions") else null
@onready var inventory_system: Node = $InventorySystem if has_node("InventorySystem") else null
@onready var rpg_menu: Control = $UI/RPGMenu if has_node("UI/RPGMenu") else null

# Movement
var current_speed: float = 5.0
var is_sprinting: bool = false

# Phasing (Z key to phase through props)
var is_phasing: bool = false

# Weapon system
var current_ammo: int = 15
var reserve_ammo: int = 45
var current_weapon_data: Resource = null
var equipped_weapons: Array = []  # Array of weapon resources
var current_weapon_index: int = 0

# Shooting
var can_shoot: bool = true
var fire_rate_timer: float = 0.0

# Nailing/Barricade system
var is_nailing: bool = false
var nailing_barricade: Node = null
var nails_placed: int = 0
var nail_timer: float = 0.0
var nails_required: int = 6
var nail_time: float = 0.5  # Time per nail

# Stats (from character attributes)
var max_health: float = 100.0
var current_health: float = 100.0
var max_stamina: float = 100.0
var current_stamina: float = 100.0

# Signals for UI
signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal experience_gained(amount: int)

func _ready():
	# Capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Setup raycast
	if raycast:
		raycast.target_position = Vector3(0, 0, -100)
		raycast.enabled = true

	# Setup interact ray if it doesn't exist
	if not interact_ray and camera:
		interact_ray = RayCast3D.new()
		interact_ray.name = "InteractRay"
		interact_ray.target_position = Vector3(0, 0, -interact_range)
		interact_ray.enabled = true
		interact_ray.collision_mask = 0b11111  # All layers
		camera.add_child(interact_ray)

	# Initialize stats from character attributes
	_sync_stats_from_attributes()

	# Connect to attribute changes
	if character_attributes:
		character_attributes.attribute_changed.connect(_on_attribute_changed)
		character_attributes.level_up.connect(_on_level_up)

	# Equip starting weapon
	_equip_starting_weapon()

	add_to_group("player")

func _sync_stats_from_attributes():
	"""Sync player stats from CharacterAttributes"""
	if character_attributes:
		var derived = character_attributes.get_derived_stats()
		max_health = derived.max_health
		max_stamina = derived.max_stamina
		current_health = min(current_health, max_health)
		current_stamina = min(current_stamina, max_stamina)
	else:
		max_health = 100.0
		max_stamina = 100.0

	current_health = max_health
	current_stamina = max_stamina

func _on_attribute_changed(_attr_name: String, _old_val: int, _new_val: int):
	_sync_stats_from_attributes()

func _on_level_up(new_level: int, _points: int):
	# Full heal on level up
	current_health = max_health
	current_stamina = max_stamina
	health_changed.emit(current_health, max_health)

	# Award skill point
	if skill_tree:
		skill_tree.add_skill_points(1)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Level %d! You gained a skill point." % new_level)

func _input(event):
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	# Check if RPG menu is open - don't process movement
	if rpg_menu and rpg_menu.is_menu_open():
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Sprint (uses stamina)
	var can_sprint = current_stamina > 0
	is_sprinting = Input.is_action_pressed("sprint") and is_on_floor() and can_sprint

	# Calculate movement speed with bonuses
	var base_speed = base_sprint_speed if is_sprinting else base_move_speed

	# Apply attribute bonuses
	var speed_bonus = 1.0
	if character_attributes:
		speed_bonus += character_attributes.movement_speed_bonus / 100.0

	# Apply skill bonuses
	if skill_tree:
		speed_bonus += skill_tree.get_effect_value("movement_speed") / 100.0

	# Apply condition modifiers
	if player_conditions:
		speed_bonus *= player_conditions.get_movement_speed_modifier()

	current_speed = base_speed * speed_bonus

	# Handle stamina drain/regen
	_update_stamina(delta)

	# Phasing through props (Z key)
	_handle_phasing()

	# Movement
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	# Weapon handling
	_handle_weapons(delta)

	# Interaction and nailing
	_handle_interaction(delta)

	# Health regeneration from skills/attributes
	_update_health_regen(delta)

func _update_stamina(delta):
	"""Handle stamina drain and regeneration"""
	if is_sprinting and velocity.length() > 0.1:
		# Drain stamina while sprinting
		current_stamina -= 15.0 * delta
		current_stamina = max(current_stamina, 0)
	else:
		# Regenerate stamina
		var regen_rate = 10.0
		if character_attributes:
			regen_rate += character_attributes.stamina_regen
		if skill_tree:
			regen_rate *= 1.0 + skill_tree.get_effect_value("stamina_regen") / 100.0

		current_stamina = min(current_stamina + regen_rate * delta, max_stamina)

	stamina_changed.emit(current_stamina, max_stamina)

func _update_health_regen(delta):
	"""Handle passive health regeneration"""
	if current_health >= max_health:
		return

	var regen_rate = 0.0

	# Base regen from attributes
	if character_attributes:
		regen_rate += character_attributes.health_regen

	# Skill bonuses
	if skill_tree:
		regen_rate += skill_tree.get_effect_value("health_regen")

	if regen_rate > 0:
		heal(regen_rate * delta)

func _handle_weapons(delta):
	# Update fire rate timer
	if fire_rate_timer > 0:
		fire_rate_timer -= delta

	# Shooting
	if Input.is_action_pressed("shoot") and can_shoot and fire_rate_timer <= 0:
		_fire_weapon()

	# Reload
	if Input.is_action_just_pressed("reload"):
		_reload_weapon()

	# Weapon switching (1-9 keys)
	for i in range(1, 10):
		if Input.is_action_just_pressed("weapon_%d" % i):
			_switch_weapon(i - 1)

# ============================================
# WEAPON SYSTEM
# ============================================

func _equip_starting_weapon():
	# Load starting weapons
	var pistol = ResourceCache.get_cached_resource("res://resources/weapons/pistol.tres")
	if pistol:
		equipped_weapons.append(pistol)
		_switch_weapon(0)
	else:
		# Try loading directly
		pistol = load("res://resources/weapons/pistol.tres")
		if pistol:
			equipped_weapons.append(pistol)
			_switch_weapon(0)
		else:
			# Create default weapon data
			current_weapon_data = null
			current_ammo = 15
			reserve_ammo = 45

func pickup_weapon(weapon_data: Resource) -> bool:
	"""Pick up a new weapon - returns true if successful"""
	if not weapon_data:
		return false

	# Check if we already have this weapon
	for i in range(equipped_weapons.size()):
		if equipped_weapons[i] and equipped_weapons[i].item_name == weapon_data.item_name:
			# Add ammo instead
			reserve_ammo += weapon_data.magazine_size if "magazine_size" in weapon_data else 30
			return true

	# Add new weapon (max 9 weapons)
	if equipped_weapons.size() < 9:
		equipped_weapons.append(weapon_data)
		# Auto-switch to new weapon
		_switch_weapon(equipped_weapons.size() - 1)
		return true

	return false

func _fire_weapon():
	if current_ammo <= 0:
		# Play empty click sound
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sound_2d("weapon_empty", 0.5)
		return

	# Check if weapon is melee
	var is_melee = current_weapon_data and "is_melee" in current_weapon_data and current_weapon_data.is_melee

	if is_melee:
		_fire_melee_weapon()
	elif current_weapon_data and "projectile_count" in current_weapon_data and current_weapon_data.projectile_count > 1:
		_fire_shotgun_weapon()
	else:
		_fire_hitscan_weapon()

func _fire_melee_weapon():
	"""Handle melee weapon attacks"""
	# Check viewmodel can fire
	if viewmodel and viewmodel.has_method("fire_weapon"):
		if not viewmodel.fire_weapon():
			return

	# Get melee range and damage
	var melee_range = current_weapon_data.weapon_range if current_weapon_data and "weapon_range" in current_weapon_data else 2.5
	var base_damage = current_weapon_data.damage if current_weapon_data else 25.0

	# Calculate damage with modifiers
	var damage = base_damage
	if character_attributes:
		damage = character_attributes.calculate_melee_damage(base_damage) if character_attributes.has_method("calculate_melee_damage") else character_attributes.calculate_ranged_damage(base_damage)
	if skill_tree:
		var damage_bonus = skill_tree.get_effect_value("damage_bonus")
		damage *= (1.0 + damage_bonus / 100.0)
	if player_conditions:
		damage *= player_conditions.get_damage_dealt_modifier()

	# Sphere cast for melee hit detection
	var space_state = get_world_3d().direct_space_state
	var cam_origin = camera.global_position
	var cam_forward = -camera.global_transform.basis.z

	# Check for hits in a cone in front of player
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 1.0
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, cam_origin + cam_forward * melee_range * 0.5)
	query.collision_mask = 0b11111  # Hit everything

	var results = space_state.intersect_shape(query, 5)

	var hit_something = false
	for result in results:
		var collider = result.collider
		if collider == self:
			continue

		# Deal damage
		if collider.has_method("take_damage"):
			var hit_pos = collider.global_position
			var is_headshot = _check_headshot(collider, hit_pos)
			var final_damage = damage

			if is_headshot:
				var headshot_mult = 2.0
				if skill_tree:
					headshot_mult += skill_tree.get_effect_value("headshot_bonus") / 100.0
				final_damage *= headshot_mult

			collider.take_damage(final_damage, hit_pos)
			hit_something = true

			# Spawn blood effect
			if has_node("/root/GoreSystem"):
				get_node("/root/GoreSystem").spawn_blood_effect(hit_pos, Vector3.UP, 2 if is_headshot else 1)

			# Life steal
			if skill_tree:
				var life_steal = skill_tree.get_effect_value("life_steal")
				if life_steal > 0:
					heal(final_damage * life_steal / 100.0)

	# Play swing sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("melee_swing", global_position, 0.6)
		if hit_something:
			get_node("/root/AudioManager").play_sound_3d("melee_hit", global_position, 0.8)

	# Melee weapons don't consume ammo, but have cooldown
	var fire_rate = current_weapon_data.fire_rate if current_weapon_data else 0.5
	fire_rate_timer = fire_rate

func _fire_shotgun_weapon():
	"""Handle shotgun-style spread weapons"""
	# Check viewmodel can fire
	if viewmodel and viewmodel.has_method("fire_weapon"):
		if not viewmodel.fire_weapon():
			return

	var pellet_count = current_weapon_data.projectile_count if current_weapon_data and "projectile_count" in current_weapon_data else 6
	var spread_angle = current_weapon_data.spread_angle if current_weapon_data and "spread_angle" in current_weapon_data else 5.0
	var base_damage = (current_weapon_data.damage if current_weapon_data else 15.0) / pellet_count  # Split damage across pellets

	# Apply damage modifiers
	var damage_per_pellet = base_damage
	if character_attributes:
		damage_per_pellet = character_attributes.calculate_ranged_damage(base_damage)
	if skill_tree:
		var damage_bonus = skill_tree.get_effect_value("damage_bonus")
		damage_per_pellet *= (1.0 + damage_bonus / 100.0)
	if player_conditions:
		damage_per_pellet *= player_conditions.get_damage_dealt_modifier()

	# Fire multiple pellets
	var total_damage_dealt = 0.0
	var cam_origin = camera.global_position
	var cam_forward = -camera.global_transform.basis.z
	var cam_right = camera.global_transform.basis.x
	var cam_up = camera.global_transform.basis.y

	for i in range(pellet_count):
		# Random spread in a cone
		var spread_x = randf_range(-spread_angle, spread_angle)
		var spread_y = randf_range(-spread_angle, spread_angle)

		var direction = cam_forward
		direction = direction.rotated(cam_up, deg_to_rad(spread_x))
		direction = direction.rotated(cam_right, deg_to_rad(spread_y))
		direction = direction.normalized()

		# Raycast for this pellet
		var space_state = get_world_3d().direct_space_state
		var ray_end = cam_origin + direction * 100.0
		var query = PhysicsRayQueryParameters3D.create(cam_origin, ray_end)
		query.collision_mask = 0b11111
		query.exclude = [self]

		var result = space_state.intersect_ray(query)

		if result:
			var hit_point = result.position
			var hit_normal = result.normal
			var collider = result.collider

			if collider.has_method("take_damage"):
				var is_headshot = _check_headshot(collider, hit_point)
				var final_damage = damage_per_pellet

				if is_headshot:
					var headshot_mult = 2.0
					if skill_tree:
						headshot_mult += skill_tree.get_effect_value("headshot_bonus") / 100.0
					final_damage *= headshot_mult

				collider.take_damage(final_damage, hit_point)
				total_damage_dealt += final_damage

				# Spawn blood for first few pellet hits
				if i < 3 and has_node("/root/GoreSystem"):
					get_node("/root/GoreSystem").spawn_blood_effect(hit_point, hit_normal, 1)
			else:
				# Environment impact
				var surface_type = _get_surface_type(collider)
				if i < 3 and has_node("/root/VFXManager"):
					get_node("/root/VFXManager").spawn_impact_effect(hit_point, hit_normal, surface_type)

	# Life steal on total damage
	if skill_tree and total_damage_dealt > 0:
		var life_steal = skill_tree.get_effect_value("life_steal")
		if life_steal > 0:
			heal(total_damage_dealt * life_steal / 100.0)

	# Consume ammo
	var consume_ammo = true
	if skill_tree and skill_tree.has_skill("lucky_shot"):
		if randf() < 0.1:
			consume_ammo = false

	if consume_ammo:
		current_ammo -= 1

	# Fire rate cooldown
	var fire_rate = current_weapon_data.fire_rate if current_weapon_data else 0.8
	var attack_speed_mult = 1.0
	if skill_tree:
		attack_speed_mult -= skill_tree.get_effect_value("attack_speed_bonus") / 100.0
	if player_conditions:
		attack_speed_mult /= player_conditions.get_attack_speed_modifier()

	fire_rate_timer = fire_rate * max(attack_speed_mult, 0.2)
	_update_hud()

func _fire_hitscan_weapon():
	"""Handle standard hitscan weapons (pistols, rifles, etc.)"""
	# Check viewmodel can fire
	if viewmodel and viewmodel.has_method("fire_weapon"):
		if not viewmodel.fire_weapon():
			return

	# Perform raycast
	if raycast and raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var hit_normal = raycast.get_collision_normal()
		var collider = raycast.get_collider()

		# Calculate base damage
		var base_damage = current_weapon_data.damage if current_weapon_data else 15.0
		var damage = base_damage

		# Apply attribute damage bonus
		if character_attributes:
			damage = character_attributes.calculate_ranged_damage(base_damage)

		# Apply skill bonuses
		if skill_tree:
			var damage_bonus = skill_tree.get_effect_value("damage_bonus")
			damage *= (1.0 + damage_bonus / 100.0)

		# Apply condition damage modifiers
		if player_conditions:
			damage *= player_conditions.get_damage_dealt_modifier()

		var is_headshot = false

		# Check for headshot
		if collider and collider.has_method("take_damage"):
			is_headshot = _check_headshot(collider, hit_point)
			if is_headshot:
				var headshot_mult = 2.0
				# Headhunter skill bonus
				if skill_tree:
					headshot_mult += skill_tree.get_effect_value("headshot_bonus") / 100.0
				damage *= headshot_mult

		# Executioner skill - bonus damage to low health enemies
		if skill_tree and skill_tree.has_skill("executioner") and collider:
			if "current_health" in collider and "max_health" in collider and collider.max_health > 0:
				if collider.current_health / collider.max_health < 0.3:
					damage *= 1.5  # 50% bonus damage

		# Deal damage
		if collider and collider.has_method("take_damage"):
			collider.take_damage(damage, hit_point)

			# Life steal skill
			if skill_tree:
				var life_steal = skill_tree.get_effect_value("life_steal")
				if life_steal > 0:
					heal(damage * life_steal / 100.0)

			# Spawn blood effect
			if has_node("/root/GoreSystem"):
				get_node("/root/GoreSystem").spawn_blood_effect(hit_point, hit_normal, 2 if is_headshot else 1)

			# Dismemberment on headshot kill
			if is_headshot and "current_health" in collider and collider.current_health <= 0:
				if has_node("/root/GoreSystem"):
					get_node("/root/GoreSystem").spawn_dismemberment_effect(hit_point, "head")
		else:
			# Hit environment - spawn impact
			var surface_type = _get_surface_type(collider)
			if has_node("/root/VFXManager"):
				get_node("/root/VFXManager").spawn_impact_effect(hit_point, hit_normal, surface_type)

	# Check for ammo conservation skill (Lucky Shot)
	var consume_ammo = true
	if skill_tree and skill_tree.has_skill("lucky_shot"):
		if randf() < 0.1:  # 10% chance
			consume_ammo = false

	if consume_ammo:
		current_ammo -= 1

	# Set fire rate cooldown with skill modifiers
	var fire_rate = current_weapon_data.fire_rate if current_weapon_data else 0.2

	# Apply attack speed bonus
	var attack_speed_mult = 1.0
	if skill_tree:
		attack_speed_mult -= skill_tree.get_effect_value("attack_speed_bonus") / 100.0
	if player_conditions:
		attack_speed_mult /= player_conditions.get_attack_speed_modifier()

	fire_rate_timer = fire_rate * max(attack_speed_mult, 0.2)

	# Update HUD
	_update_hud()

func _reload_weapon():
	if current_ammo >= (current_weapon_data.magazine_size if current_weapon_data else 15):
		return  # Already full

	if reserve_ammo <= 0:
		return  # No ammo left

	# Start reload via viewmodel
	if viewmodel and viewmodel.has_method("start_reload"):
		await viewmodel.start_reload()

	# Calculate ammo to reload
	var mag_size = current_weapon_data.magazine_size if current_weapon_data else 15
	var ammo_needed = mag_size - current_ammo
	var ammo_to_reload = min(ammo_needed, reserve_ammo)

	# Reload
	current_ammo += ammo_to_reload
	reserve_ammo -= ammo_to_reload

	_update_hud()

func _switch_weapon(index: int):
	if index < 0 or index >= equipped_weapons.size():
		return

	if index == current_weapon_index:
		return

	current_weapon_index = index
	current_weapon_data = equipped_weapons[index]

	# Load weapon scene
	var weapon_scene_path = _get_weapon_scene_path(current_weapon_data.item_name)
	var weapon_scene = load(weapon_scene_path) if ResourceLoader.exists(weapon_scene_path) else null

	# Equip via viewmodel
	if viewmodel and viewmodel.has_method("equip_weapon"):
		await viewmodel.equip_weapon(weapon_scene, current_weapon_data)

	# Reset ammo (simplified - should load from inventory)
	current_ammo = current_weapon_data.magazine_size if current_weapon_data else 15
	reserve_ammo = current_weapon_data.magazine_size * 3 if current_weapon_data else 45

	_update_hud()

func _get_weapon_scene_path(weapon_name: String) -> String:
	# Map weapon names to scene paths
	var name_lower = weapon_name.to_lower()

	var scene_map = {
		"pistol": "res://scenes/weapons/weapon_pistol.tscn",
		"ak-47": "res://scenes/weapons/weapon_ak47.tscn",
		"ak47": "res://scenes/weapons/weapon_ak47.tscn",
		"shotgun": "res://scenes/weapons/weapon_shotgun.tscn",
		"m16": "res://scenes/weapons/weapon_m16.tscn",
		"revolver": "res://scenes/weapons/weapon_revolver.tscn",
		"sniper": "res://scenes/weapons/weapon_sniper.tscn",
		"machine gun": "res://scenes/weapons/weapon_machine_gun.tscn",
		"rpg": "res://scenes/weapons/weapon_rpg.tscn"
	}

	if scene_map.has(name_lower):
		return scene_map[name_lower]

	return "res://scenes/weapons/weapon_pistol.tscn"  # Default

func _check_headshot(target: Node, hit_position: Vector3) -> bool:
	if not "global_position" in target:
		return false

	# Simple headshot check - hit point is above center of target
	var target_pos = target.global_position
	var height_diff = hit_position.y - target_pos.y

	# Assume head is at top 20% of target height
	return height_diff > 0.8

func _get_surface_type(collider: Node) -> String:
	if not collider:
		return "concrete"

	# Check collision layer or groups
	if collider.is_in_group("metal"):
		return "metal"
	elif collider.is_in_group("wood"):
		return "wood"
	elif collider.is_in_group("zombies"):
		return "flesh"

	return "concrete"

# ============================================
# UI UPDATES
# ============================================

func _update_hud():
	# Find and update HUD
	var hud = get_tree().get_first_node_in_group("hud")
	if not hud:
		return

	if hud.has_method("update_weapon_info"):
		hud.update_weapon_info(current_weapon_data, current_ammo, reserve_ammo)

# ============================================
# DAMAGE & HEALING
# ============================================

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	"""Take damage with condition and skill modifiers"""
	var final_damage = amount

	# Apply condition damage modifiers
	if player_conditions:
		final_damage *= player_conditions.get_damage_taken_modifier()

	# Apply skill damage reduction
	if skill_tree:
		var damage_reduction = skill_tree.get_effect_value("damage_reduction")
		final_damage *= (1.0 - damage_reduction / 100.0)

		# Last Stand skill check
		if skill_tree.has_skill("last_stand") and max_health > 0 and current_health / max_health < 0.25:
			final_damage *= 0.7  # 30% damage reduction

	# Apply armor reduction
	if character_attributes:
		final_damage = character_attributes.calculate_incoming_damage(final_damage)

	current_health -= final_damage
	current_health = max(current_health, 0)

	# Emit signal for UI
	health_changed.emit(current_health, max_health)

	# Update HUD
	_update_hud()

	# Camera shake on damage
	_camera_shake(0.2, 0.1)

	if current_health <= 0:
		_die()

func heal(amount: float):
	"""Heal the player"""
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func add_experience(amount: int):
	"""Add experience to the player"""
	if character_attributes:
		character_attributes.add_experience(amount)
	experience_gained.emit(amount)

func add_points(amount: int, reason: String = ""):
	"""Add points (for kills, etc.) - integrates with PointsSystem and ArenaManager"""
	# Forward to points system if available
	if has_node("/root/PointsSystem"):
		var points_system = get_node("/root/PointsSystem")
		if points_system.has_method("add_points"):
			points_system.add_points(amount, reason)

	# Also notify arena manager if in arena (for per-player tracking in multiplayer)
	var arena_manager = get_tree().get_first_node_in_group("arena_manager")
	if arena_manager and arena_manager.has_method("add_player_points"):
		arena_manager.add_player_points(multiplayer.get_unique_id(), amount)

	# Update HUD with new points
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_points"):
		var total_points = 0
		if has_node("/root/PointsSystem"):
			total_points = get_node("/root/PointsSystem").get_points()
		elif arena_manager:
			total_points = arena_manager.player_points
		hud.update_points(total_points)

func add_kill_points(zombie_class: String, was_headshot: bool = false):
	"""Add points for killing a zombie with proper rewards"""
	if has_node("/root/PointsSystem"):
		var points_system = get_node("/root/PointsSystem")
		if points_system.has_method("reward_zombie_kill"):
			points_system.reward_zombie_kill(zombie_class, was_headshot, false)
	else:
		# Fallback point values if no PointsSystem
		var points = 100
		match zombie_class.to_lower():
			"shambler": points = 100
			"runner": points = 120
			"tank": points = 200
			"monster": points = 300
			"boss": points = 1000
		if was_headshot:
			points += 25
		add_points(points, "Killed " + zombie_class)

func apply_status_effect(effect_type: String, _value: float, duration: float):
	"""Apply a status effect to the player"""
	if player_conditions:
		player_conditions.apply_condition(effect_type, duration)

func _die():
	"""Handle player death"""
	print("Player died!")

	# Disable player controls
	set_physics_process(false)
	set_process_input(false)

	# Hide viewmodel
	if viewmodel:
		viewmodel.visible = false

	# Disable main camera
	if camera:
		camera.current = false

	# Enable spectator mode for multiplayer
	if multiplayer.has_multiplayer_peer() and spectator_controller:
		spectator_controller.enable_spectating()
	elif spectator_controller:
		# Single player - still allow spectating zombies/arena
		spectator_controller.enable_spectating()

	# Show death screen
	_show_death_screen()

	# Play death sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_2d("player_death", 0.9)

	# Network replicate death
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_player_died.rpc(multiplayer.get_unique_id())

	# Schedule respawn
	await get_tree().create_timer(5.0).timeout
	_respawn()

@rpc("authority", "call_local", "reliable")
func _player_died(_player_id: int):
	"""Network replicated player death"""
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Player died!")

func _show_death_screen():
	"""Show death UI"""
	# Could create a death screen UI here
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("You died! Respawning in 5 seconds...")

func _respawn():
	"""Respawn the player"""
	# Disable spectator mode
	if spectator_controller:
		spectator_controller.disable_spectating()

	# Reset health
	current_health = max_health
	current_stamina = max_stamina

	# Find spawn point
	var spawn_points = get_tree().get_nodes_in_group("player_spawn")
	if spawn_points.size() > 0:
		var spawn = spawn_points[randi() % spawn_points.size()]
		global_position = spawn.global_position

	# Re-enable controls
	set_physics_process(true)
	set_process_input(true)

	# Show viewmodel and enable camera
	if viewmodel:
		viewmodel.visible = true
	if camera:
		camera.current = true

	# Play respawn sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_2d("player_respawn", 0.7)

	# Network replicate respawn
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_player_respawned.rpc(multiplayer.get_unique_id(), global_position)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Respawned!")

@rpc("authority", "call_local", "reliable")
func _player_respawned(_player_id: int, _spawn_position: Vector3):
	"""Network replicated player respawn"""
	pass  # Could add respawn effects here

func _camera_shake(intensity: float, duration: float):
	if not camera:
		return

	var original_pos = camera.position
	var shake_time = 0.0

	while shake_time < duration:
		shake_time += get_physics_process_delta_time()

		var shake_offset = Vector3(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity),
			0
		)

		camera.position = original_pos + shake_offset
		await get_tree().physics_frame

	camera.position = original_pos

# ============================================
# PHASING SYSTEM
# ============================================

func _handle_phasing():
	"""JetBoom mechanic - hold Z to phase through props"""
	var wants_phase = Input.is_key_pressed(KEY_Z)

	if wants_phase and not is_phasing:
		# Start phasing
		is_phasing = true
		var props = get_tree().get_nodes_in_group("props")
		for prop in props:
			if prop.has_method("enable_phasing"):
				prop.enable_phasing()

	elif not wants_phase and is_phasing:
		# Stop phasing
		is_phasing = false
		var props = get_tree().get_nodes_in_group("props")
		for prop in props:
			if prop.has_method("disable_phasing"):
				prop.disable_phasing()

# ============================================
# INTERACTION & NAILING SYSTEM
# ============================================

func _handle_interaction(delta):
	"""Handle player interaction with objects and JetBoom-style nailing"""
	var hud = get_tree().get_first_node_in_group("hud")

	# Handle ongoing nailing
	if is_nailing:
		_process_nailing(delta, hud)
		return

	# Check for interactable objects
	if not interact_ray:
		return

	interact_ray.force_raycast_update()

	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		var distance = global_position.distance_to(interact_ray.get_collision_point())

		if distance <= interact_range:
			_show_interact_prompt(collider, hud)

			# Start interaction
			if Input.is_action_just_pressed("interact"):
				_start_interaction(collider)
		else:
			_hide_interact_prompt(hud)
	else:
		_hide_interact_prompt(hud)

func _show_interact_prompt(collider: Node, hud):
	"""Show context-sensitive interaction prompt"""
	if not hud or not hud.has_method("show_interact_prompt"):
		return

	# Barricade spots
	if collider.is_in_group("barricade_spot"):
		if "has_barricade" in collider and collider.has_barricade:
			if "current_barricade" in collider and collider.current_barricade:
				var barricade = collider.current_barricade
				if "current_health" in barricade and "max_health" in barricade:
					if barricade.current_health < barricade.max_health:
						hud.show_interact_prompt("[E] Hold to Repair")
					else:
						hud.show_interact_prompt("Barricade Full Health")
					return
		else:
			hud.show_interact_prompt("[E] Hold to Build Barricade")
		return

	# Existing barricades
	if collider.is_in_group("barricades"):
		if "current_health" in collider and "max_health" in collider:
			if collider.current_health < collider.max_health:
				hud.show_interact_prompt("[E] Hold to Repair (%d%%)" % [int(collider.current_health / collider.max_health * 100)])
			else:
				hud.show_interact_prompt("Barricade Full Health")
		return

	# Loot items
	if collider.is_in_group("loot"):
		var item_name = "Item"
		if "item_name" in collider:
			item_name = collider.item_name
		elif collider.has_method("get_item_data"):
			var data = collider.get_item_data()
			if data and "item_name" in data:
				item_name = data.item_name
		hud.show_interact_prompt("[E] Pick up %s" % item_name)
		return

	# Generic interactables
	if collider.has_method("interact"):
		hud.show_interact_prompt("[E] Interact")
		return

	# Hide if nothing valid
	_hide_interact_prompt(hud)

func _hide_interact_prompt(hud):
	if hud and hud.has_method("hide_interact_prompt"):
		hud.hide_interact_prompt()
	if hud and hud.has_method("update_nail_progress"):
		hud.update_nail_progress(0.0, false)

func _start_interaction(collider: Node):
	"""Begin an interaction based on collider type"""
	# Barricade spots - start building/repairing
	if collider.is_in_group("barricade_spot"):
		if "has_barricade" in collider and collider.has_barricade:
			if "current_barricade" in collider and collider.current_barricade:
				_start_nailing(collider.current_barricade)
		else:
			# Build new barricade
			if collider.has_method("interact"):
				collider.interact(self)
				# After placing, start nailing the new barricade
				if "current_barricade" in collider and collider.current_barricade:
					_start_nailing(collider.current_barricade)
		return

	# Direct barricade interaction
	if collider.is_in_group("barricades"):
		_start_nailing(collider)
		return

	# Loot pickup
	if collider.is_in_group("loot"):
		if collider.has_method("interact"):
			collider.interact(self)
		elif collider.has_method("pickup"):
			collider.pickup(self)
		return

	# Generic interaction
	if collider.has_method("interact"):
		collider.interact(self)

func _start_nailing(barricade: Node):
	"""Begin the JetBoom-style nailing process"""
	if not barricade:
		return

	# Check if barricade needs nails
	if "current_health" in barricade and "max_health" in barricade:
		if barricade.current_health >= barricade.max_health:
			return  # Already full

	is_nailing = true
	nailing_barricade = barricade
	nails_placed = 0
	nail_timer = nail_time

	# Get nails required from barricade if available
	if "nails_required" in barricade:
		nails_required = barricade.nails_required
	else:
		# Calculate based on missing health
		var health_missing = barricade.max_health - barricade.current_health if "max_health" in barricade else 100.0
		var nail_health = barricade.nail_health if "nail_health" in barricade else 20.0
		nails_required = int(ceil(health_missing / nail_health))

	# Play starting sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("hammer_start", barricade.global_position, 0.6)

	# Update HUD
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_interact_prompt"):
		hud.show_interact_prompt("Nailing... 0/%d" % nails_required)

func _process_nailing(delta, hud):
	"""Process the ongoing nailing - JetBoom style hold-to-nail"""
	# Cancel if player releases interact
	if not Input.is_action_pressed("interact"):
		_cancel_nailing(hud)
		return

	# Cancel if barricade is gone
	if not nailing_barricade or not is_instance_valid(nailing_barricade):
		_cancel_nailing(hud)
		return

	# Cancel if too far away
	var distance = global_position.distance_to(nailing_barricade.global_position)
	if distance > interact_range + 1.0:
		_cancel_nailing(hud)
		return

	# Cancel if barricade is full
	if "current_health" in nailing_barricade and "max_health" in nailing_barricade:
		if nailing_barricade.current_health >= nailing_barricade.max_health:
			_complete_nailing(hud)
			return

	# Progress nail timer
	nail_timer -= delta

	if nail_timer <= 0:
		_place_nail(hud)
		nail_timer = nail_time

func _place_nail(hud):
	"""Place a single nail"""
	nails_placed += 1

	# Add health to barricade
	if nailing_barricade.has_method("add_nail"):
		nailing_barricade.add_nail()
	elif "current_health" in nailing_barricade and "max_health" in nailing_barricade:
		var nail_health = nailing_barricade.nail_health if "nail_health" in nailing_barricade else 20.0
		nailing_barricade.current_health = min(nailing_barricade.current_health + nail_health, nailing_barricade.max_health)

	# Play hammer sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("hammer", nailing_barricade.global_position, 0.8)

	# Spawn nail particle effect
	if has_node("/root/VFXManager"):
		var hit_pos = nailing_barricade.global_position + Vector3(
			randf_range(-0.3, 0.3),
			randf_range(0.5, 1.5),
			randf_range(-0.3, 0.3)
		)
		get_node("/root/VFXManager").spawn_impact_effect(hit_pos, Vector3.UP, "wood")

	# Update HUD
	if hud and hud.has_method("show_interact_prompt"):
		hud.show_interact_prompt("Nailing... %d/%d" % [nails_placed, nails_required])
	if hud and hud.has_method("update_nail_progress"):
		hud.update_nail_progress(float(nails_placed) / float(nails_required), true)

	# Check if complete
	if nails_placed >= nails_required:
		_complete_nailing(hud)

func _complete_nailing(hud):
	"""Finish the nailing process"""
	# Complete repair on barricade
	if nailing_barricade and nailing_barricade.has_method("complete_repair"):
		nailing_barricade.complete_repair()

	# Play completion sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("hammer_complete", nailing_barricade.global_position if nailing_barricade else global_position, 0.7)

	# Update HUD
	if hud and hud.has_method("show_interact_prompt"):
		hud.show_interact_prompt("Barricade Complete!")
	if hud and hud.has_method("update_nail_progress"):
		hud.update_nail_progress(1.0, false)

	# Award points for repairing
	add_points(25, "Barricade repaired")

	# Reset state
	is_nailing = false
	nailing_barricade = null
	nails_placed = 0

	# Hide prompt after short delay
	await get_tree().create_timer(1.0).timeout
	if hud and hud.has_method("hide_interact_prompt"):
		hud.hide_interact_prompt()

func _cancel_nailing(hud):
	"""Cancel the nailing process"""
	is_nailing = false
	nailing_barricade = null
	nails_placed = 0

	if hud and hud.has_method("hide_interact_prompt"):
		hud.hide_interact_prompt()
	if hud and hud.has_method("update_nail_progress"):
		hud.update_nail_progress(0.0, false)

# ============================================
# NETWORK
# ============================================

func get_network_id() -> int:
	return multiplayer.get_unique_id()
