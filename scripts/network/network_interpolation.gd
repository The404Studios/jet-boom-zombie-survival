extends Node
class_name NetworkInterpolation

# Network interpolation/extrapolation for smooth multiplayer movement
# Attach to any networked entity (players, zombies, projectiles)

signal interpolation_complete

@export var interpolation_rate: float = 15.0  # Higher = faster catch-up
@export var extrapolation_limit: float = 0.25  # Max time to extrapolate (seconds)
@export var snap_distance: float = 5.0  # Teleport if too far

var target_position: Vector3 = Vector3.ZERO
var target_rotation: Vector3 = Vector3.ZERO
var target_velocity: Vector3 = Vector3.ZERO

var previous_position: Vector3 = Vector3.ZERO
var previous_rotation: Vector3 = Vector3.ZERO

var last_update_time: float = 0.0
var update_interval: float = 0.05  # Expected update frequency

var is_local_player: bool = false
var parent_node: Node3D = null

func _ready():
	parent_node = get_parent() as Node3D
	if parent_node:
		target_position = parent_node.global_position
		target_rotation = parent_node.global_rotation
		previous_position = target_position
		previous_rotation = target_rotation

func _physics_process(delta):
	if not parent_node or not is_instance_valid(parent_node):
		return

	if is_local_player:
		return  # Local player handles own movement

	_apply_interpolation(delta)

func _apply_interpolation(delta):
	var time_since_update = Time.get_ticks_msec() / 1000.0 - last_update_time

	# Check if we need to extrapolate
	if time_since_update > update_interval:
		if time_since_update < extrapolation_limit:
			# Extrapolate based on velocity
			_apply_extrapolation(time_since_update)
		else:
			# Too long since update - just use target position
			parent_node.global_position = target_position
			parent_node.global_rotation = target_rotation
		return

	# Interpolate position
	var distance = parent_node.global_position.distance_to(target_position)

	if distance > snap_distance:
		# Too far - snap directly
		parent_node.global_position = target_position
		parent_node.global_rotation = target_rotation
	else:
		# Smooth interpolation
		parent_node.global_position = parent_node.global_position.lerp(
			target_position,
			delta * interpolation_rate
		)

		# Rotation interpolation (slerp for better results)
		var current_quat = Quaternion.from_euler(parent_node.global_rotation)
		var target_quat = Quaternion.from_euler(target_rotation)
		var interpolated_quat = current_quat.slerp(target_quat, delta * interpolation_rate)
		parent_node.global_rotation = interpolated_quat.get_euler()

func _apply_extrapolation(time_since_update: float):
	"""Predict position based on last known velocity"""
	var extrapolated_position = target_position + target_velocity * time_since_update

	parent_node.global_position = parent_node.global_position.lerp(
		extrapolated_position,
		0.1  # Gentle extrapolation
	)

func receive_network_state(position: Vector3, rotation: Vector3, velocity: Vector3 = Vector3.ZERO):
	"""Called when receiving network position update"""
	previous_position = target_position
	previous_rotation = target_rotation

	target_position = position
	target_rotation = rotation
	target_velocity = velocity

	var current_time = Time.get_ticks_msec() / 1000.0

	# Calculate update interval
	if last_update_time > 0:
		update_interval = current_time - last_update_time

	last_update_time = current_time

func set_local_player(is_local: bool):
	"""Set whether this is the local player (no interpolation needed)"""
	is_local_player = is_local

func get_interpolated_position() -> Vector3:
	if parent_node:
		return parent_node.global_position
	return target_position

func get_interpolated_rotation() -> Vector3:
	if parent_node:
		return parent_node.global_rotation
	return target_rotation

# ============================================
# PREDICTION (CLIENT-SIDE)
# ============================================

var input_buffer: Array = []
var prediction_position: Vector3 = Vector3.ZERO
var last_acknowledged_input: int = 0

func add_predicted_input(input_id: int, input_data: Dictionary):
	"""Add input to prediction buffer for client-side prediction"""
	input_buffer.append({
		"id": input_id,
		"data": input_data,
		"position": parent_node.global_position if parent_node else Vector3.ZERO
	})

	# Limit buffer size
	while input_buffer.size() > 100:
		input_buffer.pop_front()

func acknowledge_input(input_id: int, server_position: Vector3):
	"""Server acknowledges input - reconcile prediction"""
	last_acknowledged_input = input_id

	# Find acknowledged input in buffer
	var ack_index = -1
	for i in range(input_buffer.size()):
		if input_buffer[i].id == input_id:
			ack_index = i
			break

	if ack_index >= 0:
		# Remove acknowledged and older inputs
		input_buffer = input_buffer.slice(ack_index + 1)

		# Check for prediction error
		var prediction_error = prediction_position.distance_to(server_position)
		if prediction_error > 0.1:
			# Re-apply unacknowledged inputs
			_reconcile_prediction(server_position)

func _reconcile_prediction(server_position: Vector3):
	"""Re-run unacknowledged inputs from server position"""
	if not parent_node:
		return

	parent_node.global_position = server_position

	# Re-apply unacknowledged inputs
	for input in input_buffer:
		_apply_input(input.data)

func _apply_input(input_data: Dictionary):
	"""Apply a single input to the entity"""
	# Override in subclass for specific movement logic
	if "velocity" in input_data and parent_node:
		parent_node.velocity = input_data.velocity
