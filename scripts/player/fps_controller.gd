extends CharacterBody3D

# Complete FPS controller with viewmodel integration
# Handles movement, looking, shooting, and weapon management

@export var mouse_sensitivity: float = 0.003
@export var move_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 9.8

# Nodes
@onready var camera: Camera3D = $Camera3D
@onready var viewmodel: Node3D = $Camera3D/Viewmodel
@onready var raycast: RayCast3D = $Camera3D/RayCast3D

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

# Stats (from character system)
var max_health: float = 100.0
var current_health: float = 100.0
var max_stamina: float = 100.0
var current_stamina: float = 100.0

func _ready():
	# Capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Setup raycast
	if raycast:
		raycast.target_position = Vector3(0, 0, -100)
		raycast.enabled = true

	# Equip starting weapon
	_equip_starting_weapon()

	add_to_group("player")

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
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Sprint
	is_sprinting = Input.is_action_pressed("sprint") and is_on_floor()
	current_speed = sprint_speed if is_sprinting else move_speed

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

func _fire_weapon():
	if current_ammo <= 0:
		# Play empty click sound
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sound_2d("weapon_empty", 0.5)
		return

	# Check viewmodel can fire
	if viewmodel and viewmodel.has_method("fire_weapon"):
		if not viewmodel.fire_weapon():
			return

	# Perform raycast
	if raycast and raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var hit_normal = raycast.get_collision_normal()
		var collider = raycast.get_collider()

		# Calculate damage
		var damage = current_weapon_data.damage if current_weapon_data else 15.0
		var is_headshot = false

		# Check for headshot
		if collider and collider.has_method("take_damage"):
			is_headshot = _check_headshot(collider, hit_point)
			if is_headshot:
				damage *= 2.0

		# Deal damage
		if collider and collider.has_method("take_damage"):
			collider.take_damage(damage, is_headshot)

			# Spawn blood effect
			if has_node("/root/GoreSystem"):
				get_node("/root/GoreSystem").spawn_blood_effect(hit_point, hit_normal, 2 if is_headshot else 1)

			# Dismemberment on headshot kill
			if is_headshot and collider.current_health <= 0:
				if has_node("/root/GoreSystem"):
					get_node("/root/GoreSystem").spawn_dismemberment_effect(hit_point, "head")
		else:
			# Hit environment - spawn impact
			var surface_type = _get_surface_type(collider)
			if has_node("/root/VFXManager"):
				get_node("/root/VFXManager").spawn_impact_effect(hit_point, hit_normal, surface_type)

	# Consume ammo
	current_ammo -= 1

	# Set fire rate cooldown
	var fire_rate = current_weapon_data.fire_rate if current_weapon_data else 0.2
	fire_rate_timer = fire_rate

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
# DAMAGE
# ============================================

func take_damage(amount: float):
	current_health -= amount
	current_health = max(current_health, 0)

	# Update HUD
	_update_hud()

	# Camera shake on damage
	_camera_shake(0.2, 0.1)

	if current_health <= 0:
		_die()

func _die():
	"""Handle player death"""
	print("Player died!")

	# Disable player controls
	set_physics_process(false)
	set_process_input(false)

	# Hide viewmodel
	if viewmodel:
		viewmodel.visible = false

	# Show death screen
	_show_death_screen()

	# Network replicate death
	if multiplayer.is_server():
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

	# Show viewmodel
	if viewmodel:
		viewmodel.visible = true

	# Network replicate respawn
	if multiplayer.is_server():
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
# NETWORK
# ============================================

func get_network_id() -> int:
	return multiplayer.get_unique_id()
