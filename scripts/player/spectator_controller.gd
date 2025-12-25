extends Node3D
class_name SpectatorController

# Spectator camera for dead players to watch others
# Supports cycling through players and free camera mode

signal spectating_player_changed(player: Node)
signal spectating_mode_changed(mode: String)

enum SpectatorMode {
	FOLLOW_PLAYER,  # Third-person view of a player
	FREE_CAM,       # Free-flying camera
	FIRST_PERSON    # First-person view of a player
}

@export var follow_distance: float = 5.0
@export var follow_height: float = 2.0
@export var free_cam_speed: float = 10.0
@export var mouse_sensitivity: float = 0.003

var current_mode: SpectatorMode = SpectatorMode.FOLLOW_PLAYER
var target_player: Node = null
var player_index: int = 0
var players: Array = []

@onready var camera: Camera3D = $Camera3D

# Free cam rotation
var rotation_x: float = 0.0
var rotation_y: float = 0.0

func _ready():
	# Start disabled
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	visible = false

func enable_spectating():
	"""Enable spectator mode"""
	visible = true
	set_process(true)
	set_physics_process(true)
	set_process_input(true)

	if camera:
		camera.current = true

	# Find players to spectate
	_refresh_player_list()

	if players.size() > 0:
		_spectate_player(0)
	else:
		# No players, switch to free cam
		current_mode = SpectatorMode.FREE_CAM
		spectating_mode_changed.emit("free_cam")

func disable_spectating():
	"""Disable spectator mode"""
	visible = false
	set_process(false)
	set_physics_process(false)
	set_process_input(false)

	if camera:
		camera.current = false

	target_player = null

func _input(event):
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, deg_to_rad(-89), deg_to_rad(89))

	# Switch players (Mouse1 = next, Mouse2 = prev)
	if event.is_action_pressed("shoot"):
		_next_player()

	if event.is_action_pressed("aim"):
		_previous_player()

	# Switch modes (Tab or Space)
	if event.is_action_pressed("jump"):
		_cycle_mode()

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	match current_mode:
		SpectatorMode.FOLLOW_PLAYER:
			_update_follow_camera(delta)
		SpectatorMode.FIRST_PERSON:
			_update_first_person_camera(delta)
		SpectatorMode.FREE_CAM:
			_update_free_camera(delta)

func _update_follow_camera(delta):
	"""Third-person follow camera"""
	if not target_player or not is_instance_valid(target_player):
		_refresh_player_list()
		if players.is_empty():
			current_mode = SpectatorMode.FREE_CAM
			return
		_spectate_player(0)
		return

	# Orbit around player
	var target_pos = target_player.global_position + Vector3(0, follow_height, 0)

	# Calculate orbit position
	var offset = Vector3(
		sin(rotation_y) * follow_distance,
		follow_height,
		cos(rotation_y) * follow_distance
	)

	var desired_pos = target_player.global_position + offset

	# Smooth follow
	global_position = global_position.lerp(desired_pos, delta * 5.0)

	# Look at player
	if camera:
		camera.look_at(target_pos, Vector3.UP)

func _update_first_person_camera(_delta):
	"""First-person view of spectated player"""
	if not target_player or not is_instance_valid(target_player):
		_refresh_player_list()
		if players.is_empty():
			current_mode = SpectatorMode.FREE_CAM
			return
		_spectate_player(0)
		return

	# Find player camera
	var player_camera = target_player.get_node_or_null("Camera3D")
	if player_camera:
		global_transform = player_camera.global_transform
	else:
		# Fallback to player head position
		global_position = target_player.global_position + Vector3(0, 1.6, 0)
		global_rotation = target_player.global_rotation

func _update_free_camera(delta):
	"""Free-flying camera"""
	# Apply rotation
	rotation = Vector3(rotation_x, rotation_y, 0)

	# Movement input
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

	# Apply movement in camera space
	var move_speed = free_cam_speed
	if Input.is_action_pressed("sprint"):
		move_speed *= 2.0

	var movement = (transform.basis * input_dir.normalized()) * move_speed * delta
	global_position += movement

func _refresh_player_list():
	"""Update list of spectatable players"""
	players.clear()

	var all_players = get_tree().get_nodes_in_group("player")
	for player in all_players:
		if is_instance_valid(player) and not _is_dead(player):
			players.append(player)

func _is_dead(player: Node) -> bool:
	"""Check if player is dead"""
	if "is_dead" in player:
		return player.is_dead
	if "current_health" in player:
		return player.current_health <= 0
	return false

func _spectate_player(index: int):
	"""Start spectating a specific player"""
	if players.is_empty():
		return

	player_index = index % players.size()
	target_player = players[player_index]

	# Position near player
	if target_player:
		global_position = target_player.global_position + Vector3(0, follow_height, follow_distance)

	spectating_player_changed.emit(target_player)

	# Notify HUD
	_update_spectator_hud()

func _next_player():
	"""Switch to next player"""
	_refresh_player_list()
	if players.size() > 0:
		player_index = (player_index + 1) % players.size()
		_spectate_player(player_index)

func _previous_player():
	"""Switch to previous player"""
	_refresh_player_list()
	if players.size() > 0:
		player_index = (player_index - 1) % players.size()
		if player_index < 0:
			player_index = players.size() - 1
		_spectate_player(player_index)

func _cycle_mode():
	"""Cycle through spectator modes"""
	match current_mode:
		SpectatorMode.FOLLOW_PLAYER:
			current_mode = SpectatorMode.FIRST_PERSON
			spectating_mode_changed.emit("first_person")
		SpectatorMode.FIRST_PERSON:
			current_mode = SpectatorMode.FREE_CAM
			spectating_mode_changed.emit("free_cam")
		SpectatorMode.FREE_CAM:
			current_mode = SpectatorMode.FOLLOW_PLAYER
			spectating_mode_changed.emit("follow")

	_update_spectator_hud()

func _update_spectator_hud():
	"""Update HUD with spectator info"""
	var hud = get_tree().get_first_node_in_group("hud")
	if not hud:
		return

	var mode_name = ""
	match current_mode:
		SpectatorMode.FOLLOW_PLAYER:
			mode_name = "Following"
		SpectatorMode.FIRST_PERSON:
			mode_name = "First Person"
		SpectatorMode.FREE_CAM:
			mode_name = "Free Camera"

	var player_name = "None"
	if target_player and is_instance_valid(target_player):
		if "player_name" in target_player:
			player_name = target_player.player_name
		else:
			player_name = "Player %d" % (player_index + 1)

	if hud.has_method("show_spectator_info"):
		hud.show_spectator_info(mode_name, player_name)
	elif hud.has_method("show_interact_prompt"):
		# Fallback to interact prompt
		if current_mode == SpectatorMode.FREE_CAM:
			hud.show_interact_prompt("Free Cam - Click to cycle players, Space to change mode")
		else:
			hud.show_interact_prompt("Spectating: %s (%s) - Click to switch" % [player_name, mode_name])

func get_spectated_player() -> Node:
	return target_player

func get_current_mode() -> SpectatorMode:
	return current_mode
