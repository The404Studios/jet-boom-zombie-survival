extends CharacterBody3D
class_name PlayerController

## FPS Player Controller with full input handling
## Supports movement, shooting, interaction, and inventory

signal health_changed(old_value: float, new_value: float)
signal stamina_changed(old_value: float, new_value: float)
signal died(killer_name: String)
signal respawned
signal weapon_changed(weapon_index: int)
signal ammo_changed(current: int, reserve: int)
signal reload_started
signal reload_finished
signal interacted(target: Node)

# Movement settings
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002
@export var gravity_mult: float = 2.0

# Stats
@export_group("Stats")
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 15.0
@export var stamina_regen_rate: float = 10.0
@export var stamina_regen_delay: float = 1.5

# Current state
var current_health: float = 100.0
var current_stamina: float = 100.0
var is_dead: bool = false
var is_sprinting: bool = false
var is_crouching: bool = false
var is_aiming: bool = false

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

func _ready():
	if multiplayer.has_multiplayer_peer():
		peer_id = get_multiplayer_authority()
		is_local_player = peer_id == multiplayer.get_unique_id()
	
	if is_local_player:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_setup_weapons()
	else:
		camera.current = false

func _setup_weapons():
	for child in weapon_holder.get_children():
		weapons.append(child)
		child.visible = false
	if weapons.size() > 0:
		_equip_weapon(0)

func _unhandled_input(event):
	if not is_local_player or is_dead:
		return
	
	if event is InputEventMouseMotion and mouse_captured:
		look_rotation.x -= event.relative.x * mouse_sensitivity
		look_rotation.y -= event.relative.y * mouse_sensitivity
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
	
	is_sprinting = Input.is_action_pressed("sprint") and current_stamina > 0 and not is_crouching and not is_aiming
	is_crouching = Input.is_action_pressed("crouch")
	is_aiming = Input.is_action_pressed("aim")
	
	var speed = walk_speed
	if is_sprinting:
		speed = sprint_speed
	elif is_crouching:
		speed = crouch_speed
	elif is_aiming:
		speed = walk_speed * 0.7
	
	# Apply skill modifiers
	var skill_system = get_node_or_null("/root/SkillSystem")
	if skill_system:
		speed *= skill_system.get_attribute("sprint_speed") if is_sprinting else 1.0
		speed *= skill_system.get_attribute("move_speed")
	
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
		current_stamina = max(0, current_stamina - stamina_drain_rate * delta)
		stamina_regen_timer = stamina_regen_delay
		can_regen_stamina = false
		stamina_changed.emit(current_stamina + stamina_drain_rate * delta, current_stamina)
	else:
		if not can_regen_stamina:
			stamina_regen_timer -= delta
			if stamina_regen_timer <= 0:
				can_regen_stamina = true
		
		if can_regen_stamina and current_stamina < max_stamina:
			var old = current_stamina
			var regen = stamina_regen_rate
			var skill_system = get_node_or_null("/root/SkillSystem")
			if skill_system:
				regen *= skill_system.get_attribute("stamina_regen")
			current_stamina = min(max_stamina, current_stamina + regen * delta)
			stamina_changed.emit(old, current_stamina)

# ============================================
# COMBAT
# ============================================

func _shoot():
	if is_reloading or not current_weapon:
		return
	
	if current_weapon.has_method("shoot"):
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
			"weapon": current_weapon.name if current_weapon else "unknown"
		})

# ============================================
# DAMAGE & HEALTH
# ============================================

func take_damage(amount: float, attacker_name: String = ""):
	if is_dead:
		return
	
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
	is_dead = false
	velocity = Vector3.ZERO
	
	if is_local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	respawned.emit()

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
	elif target.is_in_group("doors"):
		var building_system = get_node_or_null("/root/BuildingSystem")
		if building_system and "prop_id" in target:
			building_system.request_toggle_door.rpc_id(1, target.prop_id)
	elif target.is_in_group("extraction"):
		var sigil_system = get_node_or_null("/root/SigilDefenseSystem")
		if sigil_system:
			sigil_system.request_start_extraction.rpc_id(1)

# ============================================
# NETWORK STATE
# ============================================

func get_state() -> Dictionary:
	return {
		"position": global_position,
		"rotation": rotation,
		"camera_rotation": camera.rotation,
		"velocity": velocity,
		"health": current_health,
		"is_crouching": is_crouching,
		"is_sprinting": is_sprinting,
		"weapon_index": current_weapon_index
	}

func apply_state(state: Dictionary):
	if state.has("position"):
		global_position = global_position.lerp(state.position, 0.5)
	if state.has("rotation"):
		rotation = rotation.lerp(state.rotation, 0.5)
	if state.has("camera_rotation"):
		camera.rotation = camera.rotation.lerp(state.camera_rotation, 0.5)
	if state.has("health"):
		current_health = state.health
	if state.has("is_crouching"):
		is_crouching = state.is_crouching
	if state.has("is_sprinting"):
		is_sprinting = state.is_sprinting
	if state.has("weapon_index") and state.weapon_index != current_weapon_index:
		_equip_weapon(state.weapon_index)
