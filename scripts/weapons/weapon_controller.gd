extends Node3D
class_name WeaponController

# Weapon controller with animations for shooting, reloading, and equipping

signal shot_fired
signal reload_started
signal reload_finished
signal weapon_equipped(weapon_data: Resource)
signal weapon_dropped(weapon_data: Resource)

@export var sway_amount: float = 0.002
@export var sway_smooth: float = 10.0
@export var bob_amount: Vector2 = Vector2(0.01, 0.008)
@export var bob_speed: float = 8.0

var weapon_data: Resource = null
var current_ammo: int = 0
var is_aiming: bool = false
var is_reloading: bool = false
var can_shoot: bool = true

# Animation state
var weapon_mesh: Node3D = null
var muzzle_point: Marker3D = null
var original_position: Vector3 = Vector3.ZERO
var original_rotation: Vector3 = Vector3.ZERO
var current_sway: Vector2 = Vector2.ZERO
var bob_time: float = 0.0
var recoil_offset: float = 0.0

# Hand nodes for animation
var left_hand: Node3D = null
var right_hand: Node3D = null

func _ready():
	original_position = position
	original_rotation = rotation
	_setup_hands()

func _setup_hands():
	# Create hand markers for IK targeting
	left_hand = Marker3D.new()
	left_hand.name = "LeftHandIK"
	add_child(left_hand)
	left_hand.position = Vector3(-0.05, -0.03, 0.1)

	right_hand = Marker3D.new()
	right_hand.name = "RightHandIK"
	add_child(right_hand)
	right_hand.position = Vector3(0.05, -0.02, 0.05)

func _process(delta):
	_apply_weapon_sway(delta)
	_apply_weapon_bob(delta)
	_apply_recoil_recovery(delta)

func _apply_weapon_sway(delta):
	# Get mouse movement for sway
	var mouse_input = Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input = Input.get_last_mouse_velocity() * 0.001

	# Smooth sway
	current_sway = current_sway.lerp(mouse_input * sway_amount, sway_smooth * delta)

	# Apply to rotation
	rotation.y = original_rotation.y - current_sway.x
	rotation.x = original_rotation.x - current_sway.y

func _apply_weapon_bob(delta):
	# Only bob when moving
	var player = get_parent().get_parent() if get_parent() else null
	if player and "velocity" in player:
		var vel = Vector2(player.velocity.x, player.velocity.z)
		if vel.length() > 0.5 and player.is_on_floor():
			bob_time += delta * bob_speed * (2.0 if player.is_sprinting else 1.0)

			var bob_offset = Vector3(
				sin(bob_time) * bob_amount.x,
				abs(cos(bob_time)) * bob_amount.y - bob_amount.y,
				0
			)

			position = original_position + bob_offset
		else:
			bob_time = 0
			position = position.lerp(original_position, delta * 5.0)

func _apply_recoil_recovery(delta):
	if recoil_offset > 0:
		recoil_offset = move_toward(recoil_offset, 0, delta * 10.0)
		rotation.x = original_rotation.x - current_sway.y - recoil_offset * 0.1

func equip_weapon(new_weapon_data: Resource):
	"""Equip a weapon with visual feedback"""
	weapon_data = new_weapon_data

	# Clear existing weapon mesh
	if weapon_mesh:
		weapon_mesh.queue_free()
		weapon_mesh = null

	if not weapon_data:
		return

	# Spawn weapon mesh
	if "mesh_scene" in weapon_data and weapon_data.mesh_scene:
		weapon_mesh = weapon_data.mesh_scene.instantiate()
		add_child(weapon_mesh)

		# Find muzzle point
		muzzle_point = weapon_mesh.get_node_or_null("MuzzlePoint")

	# Set ammo
	if "magazine_size" in weapon_data:
		current_ammo = weapon_data.magazine_size

	# Play equip animation
	play_equip_animation()

	weapon_equipped.emit(weapon_data)
	print("[WeaponController] Equipped: ", weapon_data.item_name if "item_name" in weapon_data else "Unknown")

func unequip_weapon():
	"""Unequip current weapon"""
	if weapon_mesh:
		weapon_mesh.queue_free()
		weapon_mesh = null

	weapon_data = null
	muzzle_point = null

func play_equip_animation():
	"""Play weapon equip animation"""
	# Start below view
	position.y = original_position.y - 0.3
	rotation.x = original_rotation.x + 0.5

	# Animate up
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", original_position.y, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation:x", original_rotation.x, 0.3).set_ease(Tween.EASE_OUT)

func play_shoot_animation():
	"""Play weapon shooting animation with recoil"""
	if not weapon_mesh:
		return

	shot_fired.emit()

	# Apply recoil
	recoil_offset = 0.3

	# Weapon kick back
	var original_z = weapon_mesh.position.z
	var tween = create_tween()
	tween.tween_property(weapon_mesh, "position:z", original_z + 0.05, 0.03)
	tween.tween_property(weapon_mesh, "position:z", original_z, 0.1)

	# Muzzle flash
	_spawn_muzzle_flash()

	# Shell eject
	_spawn_shell_casing()

func play_reload_animation():
	"""Play reload animation"""
	if is_reloading:
		return

	is_reloading = true
	reload_started.emit()

	# Magazine drop animation
	var tween = create_tween()

	# Tilt weapon down
	tween.tween_property(self, "rotation:x", original_rotation.x + 0.3, 0.2)

	# Lower slightly
	tween.tween_property(self, "position:y", original_position.y - 0.1, 0.2)

	# Wait for reload time
	var reload_time = weapon_data.reload_time if weapon_data and "reload_time" in weapon_data else 1.5
	tween.tween_interval(reload_time - 0.4)

	# Bring back up
	tween.tween_property(self, "position:y", original_position.y, 0.2)
	tween.tween_property(self, "rotation:x", original_rotation.x, 0.2)

	tween.tween_callback(_on_reload_complete)

func _on_reload_complete():
	if weapon_data and "magazine_size" in weapon_data:
		current_ammo = weapon_data.magazine_size
	is_reloading = false
	reload_finished.emit()

func _spawn_muzzle_flash():
	"""Create muzzle flash effect"""
	var flash_pos = muzzle_point.global_position if muzzle_point else global_position

	# Create light flash
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.3)
	light.light_energy = 5.0
	light.omni_range = 5.0
	light.global_position = flash_pos
	get_tree().current_scene.add_child(light)

	# Fade and remove
	var tween = create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.05)
	tween.tween_callback(light.queue_free)

	# Spawn particles via VFXManager if available
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_muzzle_flash"):
		vfx.spawn_muzzle_flash(flash_pos, -global_transform.basis.z)

func _spawn_shell_casing():
	"""Spawn ejected shell casing"""
	var eject_pos = global_position + Vector3(0.02, 0, 0)

	# Create simple shell mesh
	var shell = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.003
	capsule.height = 0.015
	shell.mesh = capsule

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.6, 0.2)
	mat.metallic = 0.9
	shell.material_override = mat

	get_tree().current_scene.add_child(shell)
	shell.global_position = eject_pos

	# Animate shell ejection
	var end_pos = shell.global_position + Vector3(randf_range(0.3, 0.5), randf_range(0.1, 0.3), randf_range(-0.2, 0.2))

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell, "rotation", Vector3(randf() * TAU, randf() * TAU, randf() * TAU), 0.3)

	# Fade out and remove
	tween.chain()
	tween.tween_interval(2.0)
	tween.tween_callback(shell.queue_free)

func get_muzzle_position() -> Vector3:
	if muzzle_point:
		return muzzle_point.global_position
	return global_position

func get_muzzle_direction() -> Vector3:
	if muzzle_point:
		return -muzzle_point.global_transform.basis.z
	return -global_transform.basis.z

func has_ammo() -> bool:
	return current_ammo > 0

func use_ammo() -> bool:
	if current_ammo > 0:
		current_ammo -= 1
		return true
	return false
