## PlayerControllerComponent - Handles player input and FPS camera control
## Processes keyboard/mouse input and translates to entity movement
class_name PlayerControllerComponent
extends ControllerComponent

## Mouse sensitivity
var mouse_sensitivity: float = 0.003

## Camera pitch limits (radians)
var pitch_min: float = -PI / 2.0 + 0.1
var pitch_max: float = PI / 2.0 - 0.1

## Current camera pitch
var camera_pitch: float = 0.0

## Current camera yaw
var camera_yaw: float = 0.0

## Walk speed
var walk_speed: float = 5.0

## Sprint speed
var sprint_speed: float = 8.0

## Crouch speed
var crouch_speed: float = 2.5

## Jump velocity
var jump_velocity: float = 6.0

## Whether sprinting
var is_sprinting: bool = false

## Whether crouching
var is_crouching: bool = false

## Whether aiming down sights
var is_aiming: bool = false

## Camera node reference
var camera: Camera3D = null

## Weapon holder reference
var weapon_holder: Node3D = null

## Current weapon slot (0-4)
var current_weapon_slot: int = 0

## Pending weapon switch slot (-1 = none)
var pending_weapon_slot: int = -1

## Interact ray reference
var interact_ray: RayCast3D = null

## Stamina for sprinting
var stamina: float = 100.0
var max_stamina: float = 100.0
var stamina_regen_rate: float = 20.0
var sprint_stamina_cost: float = 15.0

## Input action names (customizable)
var input_forward: String = "move_forward"
var input_back: String = "move_back"
var input_left: String = "move_left"
var input_right: String = "move_right"
var input_sprint: String = "sprint"
var input_jump: String = "jump"
var input_shoot: String = "shoot"
var input_reload: String = "reload"
var input_interact: String = "interact"
var input_inventory: String = "inventory"

## Signal when weapon slot changed
signal weapon_slot_changed(slot: int)

## Signal when stamina changed
signal stamina_changed(current: float, maximum: float)


func get_component_name() -> String:
	return "PlayerController"


func _init() -> void:
	controller_type = ControllerType.PLAYER


## Setup camera and weapon holder references
func setup_camera(cam: Camera3D, holder: Node3D = null) -> void:
	camera = cam
	weapon_holder = holder

	if camera:
		camera_pitch = camera.rotation.x
		camera_yaw = camera.get_parent().rotation.y if camera.get_parent() else 0.0


## Setup interact ray
func setup_interact_ray(ray: RayCast3D) -> void:
	interact_ray = ray


## Handle mouse motion input
func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not controller_active:
		return

	# Update yaw (horizontal)
	camera_yaw -= event.relative.x * mouse_sensitivity

	# Update pitch (vertical)
	camera_pitch -= event.relative.y * mouse_sensitivity
	camera_pitch = clampf(camera_pitch, pitch_min, pitch_max)

	# Update look direction
	var basis := Basis.from_euler(Vector3(camera_pitch, camera_yaw, 0))
	look_direction = -basis.z


## Update controller with input
func _update_controller(delta: float) -> void:
	if not controller_active:
		clear_input()
		return

	# Movement input
	var move_input := Vector3.ZERO

	if Input.is_action_pressed(input_forward):
		move_input.z -= 1
	if Input.is_action_pressed(input_back):
		move_input.z += 1
	if Input.is_action_pressed(input_left):
		move_input.x -= 1
	if Input.is_action_pressed(input_right):
		move_input.x += 1

	# Transform movement to camera direction
	if move_input.length() > 0:
		var cam_basis := Basis.from_euler(Vector3(0, camera_yaw, 0))
		input_direction = cam_basis * move_input.normalized()
	else:
		input_direction = Vector3.ZERO

	# Sprint check
	is_sprinting = Input.is_action_pressed(input_sprint) and stamina > 0 and is_moving()
	action_special = is_sprinting

	# Update stamina
	if is_sprinting:
		stamina -= sprint_stamina_cost * delta
		stamina = maxf(stamina, 0)
		stamina_changed.emit(stamina, max_stamina)
	elif stamina < max_stamina:
		stamina += stamina_regen_rate * delta
		stamina = minf(stamina, max_stamina)
		stamina_changed.emit(stamina, max_stamina)

	# Jump
	if Input.is_action_just_pressed(input_jump):
		action_jump = true
	else:
		action_jump = false

	# Combat actions
	action_primary = Input.is_action_pressed(input_shoot)
	action_reload = Input.is_action_just_pressed(input_reload)
	action_interact = Input.is_action_just_pressed(input_interact)

	# Weapon switching (number keys)
	for i in range(5):
		var action_name := "weapon_%d" % (i + 1)
		if Input.is_action_just_pressed(action_name):
			switch_weapon(i)
			break

	# Update state
	_update_state()


## Update player state
func _update_state() -> void:
	if is_crouching:
		change_state("crouch")
	elif is_sprinting and is_moving():
		change_state("sprint")
	elif is_moving():
		change_state("walk")
	elif action_primary:
		change_state("attack")
	else:
		change_state("idle")


## Switch to weapon slot
func switch_weapon(slot: int) -> void:
	if slot < 0 or slot > 4:
		return

	if slot != current_weapon_slot:
		pending_weapon_slot = slot
		weapon_slot_changed.emit(slot)


## Confirm weapon switch (called after equip animation)
func confirm_weapon_switch() -> void:
	if pending_weapon_slot >= 0:
		current_weapon_slot = pending_weapon_slot
		pending_weapon_slot = -1


## Get current movement speed
func get_movement_speed() -> float:
	if is_crouching:
		return crouch_speed
	elif is_sprinting:
		return sprint_speed
	return walk_speed


## Apply camera rotation to nodes
func apply_camera_rotation() -> void:
	if not camera:
		return

	camera.rotation.x = camera_pitch

	var parent := camera.get_parent()
	if parent and parent is Node3D:
		parent.rotation.y = camera_yaw


## Check what the player is looking at
func get_look_target() -> Dictionary:
	if not interact_ray:
		return {}

	if interact_ray.is_colliding():
		return {
			"collider": interact_ray.get_collider(),
			"position": interact_ray.get_collision_point(),
			"normal": interact_ray.get_collision_normal()
		}

	return {}


## Toggle crouch
func toggle_crouch() -> void:
	is_crouching = not is_crouching


## Start aiming
func start_aim() -> void:
	is_aiming = true
	action_secondary = true


## Stop aiming
func stop_aim() -> void:
	is_aiming = false
	action_secondary = false


## Enable/disable controller
func set_controller_enabled(is_enabled: bool) -> void:
	controller_active = is_enabled
	if not is_enabled:
		clear_input()
		is_sprinting = false


func serialize() -> Dictionary:
	var data := super.serialize()
	data["mouse_sensitivity"] = mouse_sensitivity
	data["walk_speed"] = walk_speed
	data["sprint_speed"] = sprint_speed
	data["crouch_speed"] = crouch_speed
	data["jump_velocity"] = jump_velocity
	data["stamina"] = stamina
	data["max_stamina"] = max_stamina
	data["camera_pitch"] = camera_pitch
	data["camera_yaw"] = camera_yaw
	data["current_weapon_slot"] = current_weapon_slot
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	mouse_sensitivity = data.get("mouse_sensitivity", 0.003)
	walk_speed = data.get("walk_speed", 5.0)
	sprint_speed = data.get("sprint_speed", 8.0)
	crouch_speed = data.get("crouch_speed", 2.5)
	jump_velocity = data.get("jump_velocity", 6.0)
	stamina = data.get("stamina", 100.0)
	max_stamina = data.get("max_stamina", 100.0)
	camera_pitch = data.get("camera_pitch", 0.0)
	camera_yaw = data.get("camera_yaw", 0.0)
	current_weapon_slot = data.get("current_weapon_slot", 0)
