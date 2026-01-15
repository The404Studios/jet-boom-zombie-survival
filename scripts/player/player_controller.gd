extends CharacterBody3D
class_name PlayerController

## FPS Player Controller with full input handling
## Supports movement, shooting, interaction, inventory, ADS, and leaning

signal health_changed(old_value: float, new_value: float)
signal stamina_changed(old_value: float, new_value: float)
signal hunger_changed(old_value: float, new_value: float)
signal thirst_changed(old_value: float, new_value: float)
signal died(killer_name: String)
signal respawned
signal weapon_changed(weapon_index: int)
signal ammo_changed(current: int, reserve: int)
signal reload_started
signal reload_finished
signal interacted(target: Node)
signal ads_changed(is_aiming: bool)
signal lean_changed(lean_direction: int)

# Movement settings
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002
@export var ads_sensitivity_mult: float = 0.5
@export var gravity_mult: float = 2.0

# Stats
@export_group("Stats")
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var max_hunger: float = 100.0
@export var max_thirst: float = 100.0
@export var stamina_drain_rate: float = 15.0
@export var stamina_regen_rate: float = 10.0
@export var stamina_regen_delay: float = 1.5
@export var hunger_drain_rate: float = 0.5  # Per minute
@export var thirst_drain_rate: float = 0.8  # Per minute

# ADS Settings
@export_group("ADS")
@export var default_fov: float = 90.0
@export var ads_fov: float = 60.0
@export var ads_transition_speed: float = 12.0
@export var ads_weapon_offset: Vector3 = Vector3(0, -0.05, 0.1)

# Leaning Settings
@export_group("Leaning")
@export var lean_angle: float = 15.0
@export var lean_offset: float = 0.3
@export var lean_speed: float = 10.0

# Current state
var current_health: float = 100.0
var current_stamina: float = 100.0
var current_hunger: float = 100.0
var current_thirst: float = 100.0
var is_dead: bool = false
var is_sprinting: bool = false
var is_crouching: bool = false
var is_aiming: bool = false

# ADS state
var ads_progress: float = 0.0  # 0 = hip fire, 1 = full ADS
var weapon_base_position: Vector3 = Vector3.ZERO

# Leaning state
var lean_direction: int = 0  # -1 = left, 0 = none, 1 = right
var current_lean: float = 0.0

# Stamina
var stamina_regen_timer: float = 0.0
var can_regen_stamina: bool = true

# References
@onready var camera: Camera3D = $Camera3D
@onready var weapon_holder: Node3D = $Camera3D/WeaponHolder
@onready var raycast: RayCast3D = $Camera3D/InteractRay
@onready var collision: CollisionShape3D = $CollisionShape3D

# Head rotation tracking (camera acts as head)
var head_rotation_x: float = 0.0

# Weapon system
var weapons: Array = []
var current_weapon_index: int = 0
var current_weapon: Node = null
var is_reloading: bool = false

# Input
var mouse_captured: bool = true
var input_direction: Vector2 = Vector2.ZERO
var look_rotation: Vector2 = Vector2.ZERO

# Network
var peer_id: int = 1
var is_local_player: bool = true

# System references
var player_conditions: Node = null
var survival_system: Node = null

func _ready():
	if multiplayer.has_multiplayer_peer():
		peer_id = get_multiplayer_authority()
		is_local_player = peer_id == multiplayer.get_unique_id()

	# Get system references
	player_conditions = get_node_or_null("PlayerConditions")
	survival_system = get_node_or_null("/root/SurvivalSystem")

	# Create PlayerConditions if not present
	if not player_conditions:
		var conditions_script = load("res://scripts/systems/player_conditions.gd")
		if conditions_script:
			player_conditions = Node.new()
			player_conditions.set_script(conditions_script)
			player_conditions.name = "PlayerConditions"
			add_child(player_conditions)

	if is_local_player:
		camera.current = true
		camera.fov = default_fov
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_setup_weapons()
	else:
		camera.current = false

	# Store weapon holder base position for ADS
	if weapon_holder:
		weapon_base_position = weapon_holder.position

func _setup_weapons():
	for child in weapon_holder.get_children():
		weapons.append(child)
		child.visible = false
	if weapons.size() > 0:
		_equip_weapon(0)

func _unhandled_input(event):
	if not is_local_player or is_dead:
		return

	# Mouse look with ADS sensitivity adjustment
	if event is InputEventMouseMotion and mouse_captured:
		var sens = mouse_sensitivity
		if is_aiming:
			sens *= ads_sensitivity_mult
		look_rotation.x -= event.relative.x * sens
		look_rotation.y -= event.relative.y * sens
		look_rotation.y = clamp(look_rotation.y, -1.5, 1.5)

	if event.is_action_pressed("ui_cancel"):
		mouse_captured = not mouse_captured
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE

	if event.is_action_pressed("shoot"):
		_shoot()

	if event.is_action_pressed("reload"):
		_reload()

	if event.is_action_pressed("interact"):
		_interact()

	# Weapon selection
	if event.is_action_pressed("weapon_1"):
		_equip_weapon(0)
	elif event.is_action_pressed("weapon_2"):
		_equip_weapon(1)
	elif event.is_action_pressed("weapon_3"):
		_equip_weapon(2)

	if event.is_action_pressed("scroll_up"):
		_equip_weapon((current_weapon_index - 1 + weapons.size()) % weapons.size())
	elif event.is_action_pressed("scroll_down"):
		_equip_weapon((current_weapon_index + 1) % weapons.size())

func _physics_process(delta):
	if not is_local_player:
		return

	if is_dead:
		return

	_update_look()
	_update_movement(delta)
	_update_stamina(delta)
	_update_survival(delta)
	_update_ads(delta)
	_update_lean(delta)

func _update_look():
	rotation.y = look_rotation.x
	head_rotation_x = look_rotation.y
	camera.rotation.x = look_rotation.y

func _update_movement(delta):
	var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_mult

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = jump_velocity

	# Update states
	var old_aiming = is_aiming
	is_sprinting = Input.is_action_pressed("sprint") and current_stamina > 0 and not is_crouching and not is_aiming
	is_crouching = Input.is_action_pressed("crouch")
	is_aiming = Input.is_action_pressed("aim")

	# Emit signal when ADS state changes
	if is_aiming != old_aiming:
		ads_changed.emit(is_aiming)

	var speed = walk_speed
	if is_sprinting:
		speed = sprint_speed
	elif is_crouching:
		speed = crouch_speed
	elif is_aiming:
		speed = walk_speed * 0.6  # Slower while ADS

	# Apply skill modifiers
	var skill_system = get_node_or_null("/root/SkillSystem")
	if skill_system:
		speed *= skill_system.get_attribute("sprint_speed") if is_sprinting else 1.0
		speed *= skill_system.get_attribute("move_speed")

	# Apply hunger/thirst penalties
	if current_hunger < 20:
		speed *= 0.8  # 20% slower when very hungry
	if current_thirst < 20:
		speed *= 0.85  # 15% slower when very thirsty

	# Apply condition modifiers (freeze, slow, speed boost, etc.)
	if player_conditions and player_conditions.has_method("get_movement_speed_modifier"):
		speed *= player_conditions.get_movement_speed_modifier()

	input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

func _update_stamina(delta):
	if is_sprinting and input_direction.length() > 0:
		# Drain faster when hungry/thirsty
		var drain = stamina_drain_rate
		if current_hunger < 30:
			drain *= 1.3
		if current_thirst < 30:
			drain *= 1.2

		current_stamina = max(0, current_stamina - drain * delta)
		stamina_regen_timer = stamina_regen_delay
		can_regen_stamina = false
		stamina_changed.emit(current_stamina + drain * delta, current_stamina)
	else:
		if not can_regen_stamina:
			stamina_regen_timer -= delta
			if stamina_regen_timer <= 0:
				can_regen_stamina = true

		if can_regen_stamina and current_stamina < max_stamina:
			var old = current_stamina
			var regen = stamina_regen_rate

			# Slower regen when hungry/thirsty
			if current_hunger < 50:
				regen *= 0.7
			if current_thirst < 50:
				regen *= 0.8

			var skill_system = get_node_or_null("/root/SkillSystem")
			if skill_system:
				regen *= skill_system.get_attribute("stamina_regen")
			current_stamina = min(max_stamina, current_stamina + regen * delta)
			stamina_changed.emit(old, current_stamina)

func _update_survival(delta):
	# Drain hunger and thirst over time
	var hunger_drain = (hunger_drain_rate / 60.0) * delta
	var thirst_drain = (thirst_drain_rate / 60.0) * delta

	# Sprint increases drain
	if is_sprinting:
		hunger_drain *= 2.0
		thirst_drain *= 1.5

	var old_hunger = current_hunger
	var old_thirst = current_thirst

	current_hunger = max(0, current_hunger - hunger_drain)
	current_thirst = max(0, current_thirst - thirst_drain)

	if abs(current_hunger - old_hunger) > 0.01:
		hunger_changed.emit(old_hunger, current_hunger)
	if abs(current_thirst - old_thirst) > 0.01:
		thirst_changed.emit(old_thirst, current_thirst)

	# Take damage when starving/dehydrated
	if current_hunger <= 0:
		take_damage(2.0 * delta, "Starvation")
	if current_thirst <= 0:
		take_damage(3.0 * delta, "Dehydration")

# ============================================
# ADS (AIM DOWN SIGHTS)
# ============================================

func _update_ads(delta):
	var target_ads = 1.0 if is_aiming else 0.0
	ads_progress = lerp(ads_progress, target_ads, ads_transition_speed * delta)

	# Update FOV
	var target_fov = lerp(default_fov, ads_fov, ads_progress)
	camera.fov = target_fov

	# Update weapon position
	if weapon_holder:
		var target_pos = weapon_base_position
		if ads_progress > 0.01:
			target_pos = weapon_base_position + ads_weapon_offset * ads_progress
			# Center the weapon for ADS
			target_pos.x = lerp(weapon_base_position.x, 0.0, ads_progress)
		weapon_holder.position = target_pos

	# Notify viewmodel controller if it exists
	var viewmodel = weapon_holder.get_node_or_null("../Viewmodel") if weapon_holder else null
	if viewmodel and viewmodel.has_method("set_aiming"):
		viewmodel.set_aiming(is_aiming)

func get_ads_accuracy_bonus() -> float:
	"""Returns accuracy multiplier based on ADS state"""
	# More accurate when ADS
	return lerp(1.0, 0.5, ads_progress)  # 50% less spread when fully ADS

func get_current_fov() -> float:
	return camera.fov if camera else default_fov

# ============================================
# LEANING
# ============================================

func _update_lean(delta):
	# Get lean input
	var old_lean_dir = lean_direction
	lean_direction = 0

	if Input.is_action_pressed("lean_left"):
		lean_direction = -1
	elif Input.is_action_pressed("lean_right"):
		lean_direction = 1

	# Can't lean while sprinting
	if is_sprinting:
		lean_direction = 0

	if lean_direction != old_lean_dir:
		lean_changed.emit(lean_direction)

	# Smoothly interpolate lean
	var target_lean = float(lean_direction)
	current_lean = lerp(current_lean, target_lean, lean_speed * delta)

	# Apply lean rotation and offset to camera
	camera.rotation.z = deg_to_rad(-lean_angle * current_lean)
	camera.position.x = lean_offset * current_lean

func get_lean_state() -> int:
	return lean_direction

# ============================================
# COMBAT
# ============================================

func _shoot():
	if is_reloading or not current_weapon:
		return

	if current_weapon.has_method("shoot"):
		# Pass accuracy info to weapon
		if current_weapon.has_method("set_accuracy_modifier"):
			current_weapon.set_accuracy_modifier(get_ads_accuracy_bonus())
		current_weapon.shoot()
		_send_shoot_action()

func _reload():
	if is_reloading or not current_weapon:
		return

	if current_weapon.has_method("reload"):
		is_reloading = true
		reload_started.emit()
		current_weapon.reload()

		var reload_time = 2.0
		if current_weapon.has_method("get_reload_time"):
			reload_time = current_weapon.get_reload_time()

		var skill_system = get_node_or_null("/root/SkillSystem")
		if skill_system:
			reload_time /= skill_system.get_attribute("reload_speed")

		await get_tree().create_timer(reload_time).timeout
		is_reloading = false
		reload_finished.emit()

func _equip_weapon(index: int):
	if index < 0 or index >= weapons.size():
		return

	# Can't switch weapons while ADS (optional - remove if you want)
	# if is_aiming:
	# 	return

	if current_weapon:
		current_weapon.visible = false

	current_weapon_index = index
	current_weapon = weapons[index]
	current_weapon.visible = true

	weapon_changed.emit(index)

func _send_shoot_action():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_method("send_player_action"):
		network_manager.send_player_action("shoot", {
			"origin": camera.global_position,
			"direction": -camera.global_transform.basis.z,
			"weapon": current_weapon.name if current_weapon else "unknown",
			"is_ads": is_aiming,
			"lean": lean_direction
		})

# ============================================
# DAMAGE & HEALTH
# ============================================

func take_damage(amount: float, attacker_name: String = ""):
	if is_dead:
		return

	# Check for invulnerability condition
	if player_conditions and player_conditions.has_method("has_condition"):
		if player_conditions.has_condition("invulnerable"):
			return

	# Apply condition damage modifier (vulnerable/fortified)
	if player_conditions and player_conditions.has_method("get_damage_taken_modifier"):
		amount *= player_conditions.get_damage_taken_modifier()

	var skill_system = get_node_or_null("/root/SkillSystem")
	if skill_system:
		amount *= (1.0 - skill_system.get_attribute("damage_reduction"))

	var old_health = current_health
	current_health = max(0, current_health - amount)
	health_changed.emit(old_health, current_health)

	if current_health <= 0:
		die(attacker_name)

func heal(amount: float):
	if is_dead:
		return

	var old_health = current_health
	var skill_system = get_node_or_null("/root/SkillSystem")
	if skill_system:
		var max_hp = max_health + skill_system.get_attribute("max_health")
		current_health = min(max_hp, current_health + amount)
	else:
		current_health = min(max_health, current_health + amount)

	health_changed.emit(old_health, current_health)

func die(killer_name: String = ""):
	if is_dead:
		return

	is_dead = true
	died.emit(killer_name)

	if is_local_player:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func respawn_at(pos: Vector3):
	global_position = pos
	current_health = max_health
	current_stamina = max_stamina
	current_hunger = max_hunger
	current_thirst = max_thirst
	is_dead = false
	velocity = Vector3.ZERO

	# Reset lean and ADS
	lean_direction = 0
	current_lean = 0.0
	is_aiming = false
	ads_progress = 0.0

	if is_local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.fov = default_fov
		camera.rotation.z = 0
		camera.position.x = 0

	respawned.emit()

# ============================================
# SURVIVAL - CONSUME ITEMS
# ============================================

func consume_food(amount: float):
	"""Restore hunger"""
	var old = current_hunger
	current_hunger = min(max_hunger, current_hunger + amount)
	hunger_changed.emit(old, current_hunger)

func consume_water(amount: float):
	"""Restore thirst"""
	var old = current_thirst
	current_thirst = min(max_thirst, current_thirst + amount)
	thirst_changed.emit(old, current_thirst)

func consume_item(item_type: String, value: float):
	"""Generic consume function for items"""
	match item_type:
		"food":
			consume_food(value)
		"water":
			consume_water(value)
		"health", "medkit":
			heal(value)
		"stamina", "energy":
			var old = current_stamina
			current_stamina = min(max_stamina, current_stamina + value)
			stamina_changed.emit(old, current_stamina)

# ============================================
# CHARACTER MODEL
# ============================================

# Character model paths for each character ID
const CHARACTER_MODELS = {
	"dizzy": "res://Free_Character/ShowcaseFreeCharacter/Characters/Street/Dizzy.glb",
	"piggy": "res://Free_Character/ShowcaseFreeCharacter/Characters/NWorld/Piggy.glb",
	"popcorn": "res://Free_Character/ShowcaseFreeCharacter/Characters/Popcorn/Popcorn.glb",
	"spawn": "res://Free_Character/ShowcaseFreeCharacter/Characters/Under/Spawn.glb",
	"nanzy": "res://Free_Character/ShowcaseFreeCharacter/Characters/Popcorn/Nanzy.glb"
}

var character_model_holder: Node3D = null
var current_character_id: String = ""

func set_character_model(character_id: String):
	"""Set the player's character model by ID"""
	if character_id.is_empty():
		return

	current_character_id = character_id

	var model_path = CHARACTER_MODELS.get(character_id, "")
	if model_path.is_empty():
		push_warning("Unknown character ID: %s" % character_id)
		return

	load_character_model(model_path)

func load_character_model(model_path: String):
	"""Load and apply a character model from path"""
	if not ResourceLoader.exists(model_path):
		push_warning("Character model not found: %s" % model_path)
		return

	var model_scene = load(model_path)
	if not model_scene:
		push_warning("Failed to load character model: %s" % model_path)
		return

	# Find or create model holder
	if not character_model_holder:
		character_model_holder = get_node_or_null("CharacterModel")
		if not character_model_holder:
			character_model_holder = Node3D.new()
			character_model_holder.name = "CharacterModel"
			add_child(character_model_holder)

	# Clear existing model
	for child in character_model_holder.get_children():
		child.queue_free()

	# Add new model
	var model_instance = model_scene.instantiate()
	character_model_holder.add_child(model_instance)

	# Position the model (centered at player feet)
	model_instance.position = Vector3(0, -0.9, 0)

	print("Loaded character model: %s" % model_path)

func get_character_id() -> String:
	return current_character_id

# ============================================
# INTERACTION
# ============================================

func _interact():
	if not raycast.is_colliding():
		return

	var target = raycast.get_collider()
	if not target:
		return

	if target.has_method("interact"):
		target.interact(self)
		interacted.emit(target)
	elif target.is_in_group("consumables"):
		_try_consume(target)
	elif target.is_in_group("doors"):
		var building_system = get_node_or_null("/root/BuildingSystem")
		if building_system and "prop_id" in target:
			building_system.request_toggle_door.rpc_id(1, target.prop_id)
	elif target.is_in_group("extraction"):
		var sigil_system = get_node_or_null("/root/SigilDefenseSystem")
		if sigil_system:
			sigil_system.request_start_extraction.rpc_id(1)

func _try_consume(target: Node):
	"""Try to consume a consumable item"""
	if target.has_method("consume"):
		var result = target.consume(self)
		if result:
			interacted.emit(target)

# ============================================
# NETWORK STATE
# ============================================

func get_state() -> Dictionary:
	var state = {
		"position": global_position,
		"rotation": rotation,
		"camera_rotation": camera.rotation,
		"velocity": velocity,
		"health": current_health,
		"hunger": current_hunger,
		"thirst": current_thirst,
		"is_crouching": is_crouching,
		"is_sprinting": is_sprinting,
		"is_aiming": is_aiming,
		"lean_direction": lean_direction,
		"weapon_index": current_weapon_index
	}

	# Include active conditions
	if player_conditions and player_conditions.has_method("get_active_conditions_display"):
		var conditions_data = []
		for cond in player_conditions.get_active_conditions_display():
			conditions_data.append({
				"id": cond.id,
				"stacks": cond.stacks,
				"time_remaining": cond.time_remaining
			})
		state["conditions"] = conditions_data

	return state

func apply_state(state: Dictionary):
	if state.has("position"):
		global_position = global_position.lerp(state.position, 0.5)
	if state.has("rotation"):
		rotation = rotation.lerp(state.rotation, 0.5)
	if state.has("camera_rotation"):
		camera.rotation = camera.rotation.lerp(state.camera_rotation, 0.5)
	if state.has("health"):
		current_health = state.health
	if state.has("hunger"):
		current_hunger = state.hunger
	if state.has("thirst"):
		current_thirst = state.thirst
	if state.has("is_crouching"):
		is_crouching = state.is_crouching
	if state.has("is_sprinting"):
		is_sprinting = state.is_sprinting
	if state.has("is_aiming"):
		is_aiming = state.is_aiming
	if state.has("lean_direction"):
		lean_direction = state.lean_direction
	if state.has("weapon_index") and state.weapon_index != current_weapon_index:
		_equip_weapon(state.weapon_index)

# ============================================
# SURVIVAL SYSTEM INTEGRATION
# ============================================

func set_survival_state(data: Dictionary):
	"""Called by SurvivalSystem to update survival stats"""
	if data.has("hunger"):
		var old_hunger = current_hunger
		current_hunger = data.hunger
		if current_hunger != old_hunger:
			hunger_changed.emit(old_hunger, current_hunger)

	if data.has("thirst"):
		var old_thirst = current_thirst
		current_thirst = data.thirst
		if current_thirst != old_thirst:
			thirst_changed.emit(old_thirst, current_thirst)

func apply_status_effect(effect_id: String, duration: float = -1.0, stacks: int = 1) -> bool:
	"""Apply a status effect/condition to the player"""
	if not player_conditions:
		return false

	if player_conditions.has_method("apply_condition"):
		return player_conditions.apply_condition(effect_id, duration, stacks)

	return false

func remove_status_effect(effect_id: String):
	"""Remove a status effect from the player"""
	if player_conditions and player_conditions.has_method("remove_condition"):
		player_conditions.remove_condition(effect_id)

func has_status_effect(effect_id: String) -> bool:
	"""Check if player has a status effect"""
	if player_conditions and player_conditions.has_method("has_condition"):
		return player_conditions.has_condition(effect_id)
	return false

func clear_debuffs():
	"""Clear all negative status effects"""
	if player_conditions and player_conditions.has_method("clear_debuffs"):
		player_conditions.clear_debuffs()

func get_active_conditions() -> Array:
	"""Get list of active conditions for UI/display"""
	if player_conditions and player_conditions.has_method("get_active_conditions_display"):
		return player_conditions.get_active_conditions_display()
	return []

func restore_stamina(amount: float):
	"""Restore stamina (used by consumables)"""
	var old_stamina = current_stamina
	current_stamina = min(max_stamina, current_stamina + amount)
	stamina_changed.emit(old_stamina, current_stamina)

func is_indoors() -> bool:
	"""Check if player is indoors (for temperature calculation)"""
	# Simple check - can be expanded with proper indoor detection
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.5,
		global_position + Vector3.UP * 10.0
	)
	query.collision_mask = 1  # Check against environment layer
	var result = space_state.intersect_ray(query)
	return not result.is_empty()  # Has ceiling = indoors
