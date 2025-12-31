extends Camera3D
class_name SpectatorCamera

# Spectator camera for observing other players when dead
# Supports multiple view modes: follow, free-fly, fixed positions

signal target_changed(target: Node)
signal mode_changed(mode: int)

enum SpectatorMode {
	FOLLOW_FIRST_PERSON,  # First-person view through target's eyes
	FOLLOW_THIRD_PERSON,  # Third-person camera behind target
	FREE_FLY,             # Free movement camera
	FIXED_POSITION,       # Fixed camera positions
	ORBIT                 # Orbit around target
}

# Mode settings
@export var current_mode: SpectatorMode = SpectatorMode.FOLLOW_THIRD_PERSON
@export var default_mode: SpectatorMode = SpectatorMode.FOLLOW_THIRD_PERSON

# Third person settings
@export var third_person_distance: float = 5.0
@export var third_person_height: float = 2.0
@export var third_person_lerp_speed: float = 8.0

# First person settings
@export var first_person_offset: Vector3 = Vector3(0, 1.6, 0)

# Free fly settings
@export var fly_speed: float = 10.0
@export var fly_sprint_multiplier: float = 2.5
@export var fly_sensitivity: float = 0.003

# Orbit settings
@export var orbit_distance: float = 8.0
@export var orbit_speed: float = 1.0
@export var orbit_height: float = 3.0

# Target tracking
var current_target: Node3D = null
var target_index: int = 0
var available_targets: Array = []

# Fixed positions
var fixed_positions: Array[Transform3D] = []
var fixed_position_index: int = 0

# Free fly state
var fly_velocity: Vector3 = Vector3.ZERO
var fly_rotation: Vector2 = Vector2.ZERO

# Orbit state
var orbit_angle: float = 0.0

# Smooth follow
var target_position: Vector3 = Vector3.ZERO
var target_look_at: Vector3 = Vector3.ZERO

# UI
var spectator_ui: Control = null
var target_name_label: Label = null
var mode_label: Label = null
var controls_label: Label = null

func _ready():
	# Initially disabled
	current = false

	# Create spectator UI
	_create_spectator_ui()

	# Find fixed camera positions
	_collect_fixed_positions()

func _process(delta):
	if not current:
		return

	match current_mode:
		SpectatorMode.FOLLOW_FIRST_PERSON:
			_process_first_person(delta)
		SpectatorMode.FOLLOW_THIRD_PERSON:
			_process_third_person(delta)
		SpectatorMode.FREE_FLY:
			_process_free_fly(delta)
		SpectatorMode.FIXED_POSITION:
			_process_fixed_position(delta)
		SpectatorMode.ORBIT:
			_process_orbit(delta)

	_update_ui()

func _input(event):
	if not current:
		return

	# Mouse look for free fly and orbit modes
	if event is InputEventMouseMotion:
		if current_mode == SpectatorMode.FREE_FLY:
			fly_rotation.y -= event.relative.x * fly_sensitivity
			fly_rotation.x -= event.relative.y * fly_sensitivity
			fly_rotation.x = clamp(fly_rotation.x, -PI/2, PI/2)

	# Keyboard controls
	if event.is_action_pressed("spectate_next") or event.is_action_pressed("ui_right"):
		next_target()
	elif event.is_action_pressed("spectate_prev") or event.is_action_pressed("ui_left"):
		previous_target()
	elif event.is_action_pressed("spectate_mode") or event.is_action_pressed("ui_accept"):
		cycle_mode()
	elif event.is_action_pressed("spectate_free") or event.is_action_pressed("jump"):
		set_mode(SpectatorMode.FREE_FLY)

# ============================================
# MODE PROCESSING
# ============================================

func _process_first_person(delta: float):
	if not is_instance_valid(current_target):
		_find_new_target()
		return

	# Get target camera or head position
	var target_camera = current_target.get_node_or_null("Camera3D")
	if target_camera:
		global_transform = target_camera.global_transform
	else:
		global_position = current_target.global_position + first_person_offset
		# Copy target rotation
		rotation = current_target.rotation

func _process_third_person(delta: float):
	if not is_instance_valid(current_target):
		_find_new_target()
		return

	# Calculate desired position behind target
	var target_pos = current_target.global_position
	var target_back = -current_target.global_transform.basis.z
	var desired_position = target_pos + target_back * third_person_distance + Vector3.UP * third_person_height

	# Smooth follow
	global_position = global_position.lerp(desired_position, third_person_lerp_speed * delta)

	# Look at target
	var look_target = target_pos + Vector3.UP * 1.5
	look_at(look_target, Vector3.UP)

func _process_free_fly(delta: float):
	# Get input
	var input_dir = Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		input_dir.z -= 1
	if Input.is_action_pressed("move_back"):
		input_dir.z += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	if Input.is_action_pressed("jump"):
		input_dir.y += 1
	if Input.is_action_pressed("crouch"):
		input_dir.y -= 1

	input_dir = input_dir.normalized()

	# Apply rotation
	rotation = Vector3(fly_rotation.x, fly_rotation.y, 0)

	# Calculate velocity
	var speed = fly_speed
	if Input.is_action_pressed("sprint"):
		speed *= fly_sprint_multiplier

	var move_dir = global_transform.basis * input_dir
	fly_velocity = move_dir * speed

	# Apply movement
	global_position += fly_velocity * delta

func _process_fixed_position(_delta: float):
	if fixed_positions.is_empty():
		return

	var target_transform = fixed_positions[fixed_position_index]
	global_transform = target_transform

	# Look at current target if available
	if is_instance_valid(current_target):
		look_at(current_target.global_position + Vector3.UP, Vector3.UP)

func _process_orbit(delta: float):
	if not is_instance_valid(current_target):
		_find_new_target()
		return

	# Rotate around target
	orbit_angle += orbit_speed * delta

	var offset = Vector3(
		cos(orbit_angle) * orbit_distance,
		orbit_height,
		sin(orbit_angle) * orbit_distance
	)

	global_position = current_target.global_position + offset
	look_at(current_target.global_position + Vector3.UP, Vector3.UP)

# ============================================
# TARGET MANAGEMENT
# ============================================

func next_target():
	"""Switch to next available target"""
	_refresh_targets()

	if available_targets.is_empty():
		return

	target_index = (target_index + 1) % available_targets.size()
	current_target = available_targets[target_index]

	target_changed.emit(current_target)

func previous_target():
	"""Switch to previous available target"""
	_refresh_targets()

	if available_targets.is_empty():
		return

	target_index = (target_index - 1 + available_targets.size()) % available_targets.size()
	current_target = available_targets[target_index]

	target_changed.emit(current_target)

func set_target(target: Node3D):
	"""Set specific target to observe"""
	if not is_instance_valid(target):
		return

	current_target = target

	_refresh_targets()
	target_index = available_targets.find(target)
	if target_index < 0:
		target_index = 0

	target_changed.emit(current_target)

func _find_new_target():
	"""Find a new target when current is invalid"""
	_refresh_targets()

	if available_targets.is_empty():
		current_target = null
		return

	target_index = mini(target_index, available_targets.size() - 1)
	current_target = available_targets[target_index]

func _refresh_targets():
	"""Refresh list of available targets"""
	available_targets.clear()

	# Get all alive players
	var player_manager = get_node_or_null("/root/PlayerManager")
	if player_manager and player_manager.has_method("get_alive_players"):
		available_targets = player_manager.get_alive_players()
	else:
		# Fallback to group
		for player in get_tree().get_nodes_in_group("players"):
			if player is Node3D:
				# Check if alive
				var is_alive = true
				if "is_dead" in player:
					is_alive = not player.is_dead
				elif "current_health" in player:
					is_alive = player.current_health > 0

				if is_alive:
					available_targets.append(player)

# ============================================
# MODE MANAGEMENT
# ============================================

func set_mode(mode: SpectatorMode):
	"""Set spectator mode"""
	current_mode = mode

	# Mode-specific setup
	match mode:
		SpectatorMode.FREE_FLY:
			# Capture mouse for free fly
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			fly_rotation = Vector2(rotation.x, rotation.y)
		SpectatorMode.FOLLOW_FIRST_PERSON, SpectatorMode.FOLLOW_THIRD_PERSON:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if not is_instance_valid(current_target):
				_find_new_target()
		SpectatorMode.FIXED_POSITION:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_collect_fixed_positions()
		SpectatorMode.ORBIT:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			orbit_angle = 0.0

	mode_changed.emit(mode)

func cycle_mode():
	"""Cycle through spectator modes"""
	var new_mode = (current_mode + 1) % SpectatorMode.size()
	set_mode(new_mode as SpectatorMode)

func next_fixed_position():
	"""Switch to next fixed camera position"""
	if fixed_positions.is_empty():
		return

	fixed_position_index = (fixed_position_index + 1) % fixed_positions.size()

func _collect_fixed_positions():
	"""Find fixed camera positions in scene"""
	fixed_positions.clear()

	for cam_pos in get_tree().get_nodes_in_group("spectator_camera"):
		if cam_pos is Node3D:
			fixed_positions.append(cam_pos.global_transform)

# ============================================
# ACTIVATION
# ============================================

func activate(initial_target: Node3D = null):
	"""Activate spectator mode"""
	current = true

	if initial_target:
		set_target(initial_target)
	else:
		_find_new_target()

	set_mode(default_mode)

	if spectator_ui:
		spectator_ui.visible = true

func deactivate():
	"""Deactivate spectator mode"""
	current = false

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if spectator_ui:
		spectator_ui.visible = false

func is_active() -> bool:
	return current

# ============================================
# UI
# ============================================

func _create_spectator_ui():
	"""Create spectator overlay UI"""
	spectator_ui = Control.new()
	spectator_ui.name = "SpectatorUI"
	spectator_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	spectator_ui.visible = false

	# Background panel at bottom
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.custom_minimum_size = Vector2(0, 60)
	spectator_ui.add_child(panel)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	# Target name
	target_name_label = Label.new()
	target_name_label.text = "Spectating: None"
	target_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(target_name_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(50, 0)
	hbox.add_child(spacer)

	# Mode label
	mode_label = Label.new()
	mode_label.text = "Mode: Third Person"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(mode_label)

	# Controls hint at top
	controls_label = Label.new()
	controls_label.text = "[←/→] Change Target  [Space] Free Fly  [Enter] Change Mode"
	controls_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	controls_label.position.y = 20
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spectator_ui.add_child(controls_label)

	# Add to viewport
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	canvas.add_child(spectator_ui)
	add_child(canvas)

func _update_ui():
	"""Update spectator UI"""
	if not spectator_ui or not spectator_ui.visible:
		return

	# Update target name
	if target_name_label:
		if is_instance_valid(current_target):
			var name = current_target.name
			if current_target.has_method("get_player_name"):
				name = current_target.get_player_name()
			elif "player_name" in current_target:
				name = current_target.player_name
			target_name_label.text = "Spectating: %s (%d/%d)" % [name, target_index + 1, available_targets.size()]
		else:
			target_name_label.text = "Spectating: None"

	# Update mode label
	if mode_label:
		var mode_names = ["First Person", "Third Person", "Free Fly", "Fixed Camera", "Orbit"]
		mode_label.text = "Mode: %s" % mode_names[current_mode]

# ============================================
# UTILITY
# ============================================

func get_current_target() -> Node3D:
	return current_target

func get_target_count() -> int:
	return available_targets.size()

func get_mode_name() -> String:
	var names = ["First Person", "Third Person", "Free Fly", "Fixed", "Orbit"]
	return names[current_mode]
