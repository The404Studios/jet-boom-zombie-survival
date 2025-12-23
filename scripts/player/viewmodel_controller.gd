extends Node3D

# First-person viewmodel controller
# Handles arms, weapons, animations, and procedural effects

signal weapon_fired
signal weapon_reloaded
signal weapon_switched(weapon_name: String)

# Nodes
@onready var camera: Camera3D = get_parent()
@onready var arms: Node3D = $Arms
@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Current weapon
var current_weapon: Node3D = null
var weapon_data: Resource = null

# Animation state
var is_reloading: bool = false
var is_switching: bool = false
var can_fire: bool = true

# Procedural animation
var sway_amount: float = 0.002
var bob_amount: float = 0.05
var bob_speed: float = 12.0
var recoil_strength: float = 1.0

# Sway
var mouse_movement: Vector2 = Vector2.ZERO
var sway_velocity: Vector2 = Vector2.ZERO
var current_sway: Vector2 = Vector2.ZERO

# Bob
var bob_time: float = 0.0
var bob_offset: Vector3 = Vector3.ZERO

# Recoil
var recoil_rotation: Vector3 = Vector3.ZERO
var recoil_position: Vector3 = Vector3.ZERO
var recoil_recovery: float = 10.0

# Base transform
var base_position: Vector3 = Vector3(0.3, -0.3, -0.5)
var base_rotation: Vector3 = Vector3.ZERO

func _ready():
	# Set base transform
	weapon_pivot.position = base_position
	weapon_pivot.rotation = base_rotation

	# Create animation player if not exists
	if not animation_player:
		animation_player = AnimationPlayer.new()
		add_child(animation_player)
		_create_default_animations()

func _process(delta):
	if not current_weapon:
		return

	# Update procedural animations
	_update_weapon_sway(delta)
	_update_weapon_bob(delta)
	_update_recoil(delta)

	# Apply all transformations
	_apply_transformations()

func _input(event):
	# Track mouse movement for sway
	if event is InputEventMouseMotion:
		mouse_movement = event.relative

# ============================================
# WEAPON MANAGEMENT
# ============================================

func equip_weapon(weapon_scene: PackedScene, weapon_resource: Resource):
	"""Equip a weapon from scene and resource"""
	# Play unequip animation if weapon exists
	if current_weapon:
		await _play_unequip_animation()

	# Remove old weapon
	if current_weapon:
		current_weapon.queue_free()
		current_weapon = null

	# Instantiate new weapon
	if weapon_scene:
		current_weapon = weapon_scene.instantiate()
		weapon_pivot.add_child(current_weapon)

		# Position weapon
		current_weapon.position = Vector3.ZERO
		current_weapon.rotation = Vector3.ZERO

	weapon_data = weapon_resource

	# Play equip animation
	await _play_equip_animation()

	is_switching = false
	weapon_switched.emit(weapon_resource.item_name if weapon_resource else "None")

func unequip_weapon():
	"""Remove current weapon"""
	if current_weapon:
		await _play_unequip_animation()
		current_weapon.queue_free()
		current_weapon = null
		weapon_data = null

# ============================================
# FIRING
# ============================================

func fire_weapon() -> bool:
	"""Attempt to fire current weapon"""
	if not can_fire or is_reloading or is_switching:
		return false

	if not current_weapon or not weapon_data:
		return false

	# Play fire animation
	_play_fire_animation()

	# Apply recoil
	_apply_fire_recoil()

	# Spawn muzzle flash
	_spawn_muzzle_flash()

	# Play sound
	_play_weapon_sound("fire")

	# Spawn shell casing
	_eject_shell()

	weapon_fired.emit()
	return true

func _play_fire_animation():
	if animation_player.has_animation("fire"):
		animation_player.play("fire")
	else:
		# Simple recoil animation
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(weapon_pivot, "position", base_position + Vector3(0, 0, 0.05), 0.05)
		tween.tween_property(weapon_pivot, "rotation:x", deg_to_rad(-5), 0.05)

		tween.chain()
		tween.set_parallel(true)
		tween.tween_property(weapon_pivot, "position", base_position, 0.15)
		tween.tween_property(weapon_pivot, "rotation:x", 0, 0.15)

func _apply_fire_recoil():
	# Add recoil based on weapon
	var recoil_amount = 1.0
	if weapon_data:
		# More damage = more recoil
		recoil_amount = weapon_data.damage / 25.0

	recoil_rotation.x += randf_range(2.0, 4.0) * recoil_amount * recoil_strength
	recoil_rotation.y += randf_range(-1.0, 1.0) * recoil_amount * recoil_strength
	recoil_position.z += 0.02 * recoil_amount

func _spawn_muzzle_flash():
	if not current_weapon:
		return

	# Find muzzle point
	var muzzle_point = current_weapon.find_child("MuzzlePoint")
	if muzzle_point:
		var muzzle_pos = muzzle_point.global_position
		var muzzle_dir = -muzzle_point.global_transform.basis.z

		# Spawn via VFXManager
		if has_node("/root/VFXManager"):
			var weapon_type = "default"
			if weapon_data and weapon_data.item_name:
				weapon_type = weapon_data.item_name.to_lower()

			get_node("/root/VFXManager").spawn_muzzle_flash(muzzle_pos, muzzle_dir, weapon_type)

	# Play muzzle flash particles on weapon
	var muzzle_flash = current_weapon.find_child("MuzzleFlash")
	if muzzle_flash and muzzle_flash is GPUParticles3D:
		muzzle_flash.restart()

func _eject_shell():
	if not current_weapon:
		return

	var ejection_point = current_weapon.find_child("ShellEjectionPoint")
	if ejection_point:
		var eject_pos = ejection_point.global_position
		var eject_dir = ejection_point.global_transform.basis.x

		# Spawn shell via VFXManager
		if has_node("/root/VFXManager"):
			get_node("/root/VFXManager").spawn_shell_casing(eject_pos, eject_dir)

# ============================================
# RELOADING
# ============================================

func start_reload():
	"""Begin reload sequence"""
	if is_reloading or is_switching:
		return

	if not current_weapon or not weapon_data:
		return

	is_reloading = true
	can_fire = false

	# Play reload animation
	await _play_reload_animation()

	# Play sound
	_play_weapon_sound("reload")

	is_reloading = false
	can_fire = true

	weapon_reloaded.emit()

func _play_reload_animation():
	if animation_player.has_animation("reload"):
		animation_player.play("reload")
		await animation_player.animation_finished
	else:
		# Default reload animation
		var reload_time = weapon_data.reload_time if weapon_data else 2.0

		var tween = create_tween()
		# Lower weapon
		tween.tween_property(weapon_pivot, "position:y", base_position.y - 0.3, reload_time * 0.3)
		# Bring back up
		tween.tween_property(weapon_pivot, "position:y", base_position.y, reload_time * 0.3)

		await tween.finished

# ============================================
# WEAPON SWITCHING
# ============================================

func _play_equip_animation():
	is_switching = true

	if animation_player.has_animation("equip"):
		animation_player.play("equip")
		await animation_player.animation_finished
	else:
		# Default equip animation - slide up from bottom
		weapon_pivot.position.y = base_position.y - 0.5

		var tween = create_tween()
		tween.tween_property(weapon_pivot, "position:y", base_position.y, 0.3)

		await tween.finished

func _play_unequip_animation():
	if animation_player.has_animation("unequip"):
		animation_player.play("unequip")
		await animation_player.animation_finished
	else:
		# Default unequip - slide down
		var tween = create_tween()
		tween.tween_property(weapon_pivot, "position:y", base_position.y - 0.5, 0.2)

		await tween.finished

# ============================================
# PROCEDURAL ANIMATIONS
# ============================================

func _update_weapon_sway(delta):
	# Smooth sway based on mouse movement
	var target_sway = mouse_movement * sway_amount
	mouse_movement = mouse_movement.lerp(Vector2.ZERO, delta * 5.0)

	# Spring physics for smooth sway
	var sway_difference = target_sway - current_sway
	sway_velocity += sway_difference * delta * 20.0
	sway_velocity = sway_velocity.lerp(Vector2.ZERO, delta * 10.0)
	current_sway += sway_velocity * delta * 10.0

func _update_weapon_bob(delta):
	if not get_parent().get_parent():
		return

	var player = get_parent().get_parent()

	# Check if player is moving
	var is_moving = false
	if player.has("velocity"):
		is_moving = player.velocity.length() > 0.1

	if is_moving:
		bob_time += delta * bob_speed
	else:
		bob_time = lerp(bob_time, 0.0, delta * 10.0)

	# Calculate bob offset
	bob_offset.y = sin(bob_time) * bob_amount
	bob_offset.x = sin(bob_time * 0.5) * bob_amount * 0.5

func _update_recoil(delta):
	# Recover from recoil
	recoil_rotation = recoil_rotation.lerp(Vector3.ZERO, delta * recoil_recovery)
	recoil_position = recoil_position.lerp(Vector3.ZERO, delta * recoil_recovery)

func _apply_transformations():
	# Combine all procedural animations
	var final_position = base_position + bob_offset + recoil_position
	final_position.x += current_sway.x
	final_position.y += current_sway.y

	var final_rotation = base_rotation + recoil_rotation
	final_rotation.z += current_sway.x * 2.0  # Roll based on sway

	weapon_pivot.position = final_position
	weapon_pivot.rotation = final_rotation

# ============================================
# AUDIO
# ============================================

func _play_weapon_sound(sound_type: String):
	if not has_node("/root/AudioManager"):
		return

	var audio = get_node("/root/AudioManager")
	var weapon_name = "default"

	if weapon_data and weapon_data.item_name:
		weapon_name = weapon_data.item_name.to_lower()

	match sound_type:
		"fire":
			audio.play_gunshot(weapon_name, global_position)
		"reload":
			audio.play_sound_3d("reload_%s" % weapon_name, global_position, 0.8)

# ============================================
# ANIMATION CREATION
# ============================================

func _create_default_animations():
	# Create basic fire animation
	var fire_anim = Animation.new()
	fire_anim.length = 0.2

	# Position track
	var pos_track = fire_anim.add_track(Animation.TYPE_POSITION_3D)
	fire_anim.track_set_path(pos_track, "WeaponPivot:position")
	fire_anim.track_insert_key(pos_track, 0.0, base_position)
	fire_anim.track_insert_key(pos_track, 0.05, base_position + Vector3(0, 0, 0.05))
	fire_anim.track_insert_key(pos_track, 0.2, base_position)

	# Rotation track
	var rot_track = fire_anim.add_track(Animation.TYPE_ROTATION_3D)
	fire_anim.track_set_path(rot_track, "WeaponPivot:rotation")
	fire_anim.track_insert_key(rot_track, 0.0, base_rotation)
	fire_anim.track_insert_key(rot_track, 0.05, base_rotation + Vector3(deg_to_rad(-5), 0, 0))
	fire_anim.track_insert_key(rot_track, 0.2, base_rotation)

	var library = AnimationLibrary.new()
	library.add_animation("fire", fire_anim)
	animation_player.add_animation_library("", library)

# ============================================
# SETTINGS
# ============================================

func set_fov(fov: float):
	"""Adjust viewmodel FOV (separate from main camera)"""
	# Viewmodel should have slightly different FOV for better appearance
	if camera:
		camera.fov = fov

func set_bob_enabled(enabled: bool):
	bob_amount = 0.05 if enabled else 0.0

func set_sway_enabled(enabled: bool):
	sway_amount = 0.002 if enabled else 0.0
