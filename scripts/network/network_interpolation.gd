extends Node
class_name NetworkInterpolation

# Network interpolation/extrapolation for smooth multiplayer movement
# Attach to any networked entity (players, zombies, projectiles)
# Server: 162.248.94.149

signal interpolation_complete
signal position_corrected(correction_amount: float)
signal latency_updated(latency_ms: float)

@export var interpolation_rate: float = 15.0  # Higher = faster catch-up
@export var extrapolation_limit: float = 0.25  # Max time to extrapolate (seconds)
@export var snap_distance: float = 5.0  # Teleport if too far
@export var interpolation_delay: float = 0.1  # 100ms buffer for smooth playback
@export var max_history_size: int = 20  # Position history buffer size
@export var use_cubic_interpolation: bool = true

var target_position: Vector3 = Vector3.ZERO
var target_rotation: Vector3 = Vector3.ZERO
var target_velocity: Vector3 = Vector3.ZERO

var previous_position: Vector3 = Vector3.ZERO
var previous_rotation: Vector3 = Vector3.ZERO

var last_update_time: float = 0.0
var update_interval: float = 0.05  # Expected update frequency

var is_local_player: bool = false
var parent_node: Node3D = null

# Position history for smooth interpolation
var state_history: Array = []

# Jitter buffer for handling network variance
var average_latency: float = 0.0
var latency_samples: Array = []
const MAX_LATENCY_SAMPLES: int = 20

# Network quality
var packet_loss_count: int = 0
var total_packets: int = 0
var last_sequence_id: int = -1

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
	var current_time = Time.get_ticks_msec() / 1000.0
	var render_time = current_time - interpolation_delay

	# Use state buffer interpolation if we have history
	if state_history.size() >= 2:
		_interpolate_from_history(render_time, delta)
	else:
		_apply_simple_interpolation(delta)

func _interpolate_from_history(render_time: float, delta: float):
	"""Interpolate between buffered states for smooth movement"""
	# Find the two states to interpolate between
	var from_state = null
	var to_state = null

	for i in range(state_history.size() - 1):
		if state_history[i].timestamp <= render_time and state_history[i + 1].timestamp >= render_time:
			from_state = state_history[i]
			to_state = state_history[i + 1]
			break

	if from_state and to_state:
		# Calculate interpolation factor
		var total_time = to_state.timestamp - from_state.timestamp
		var elapsed_time = render_time - from_state.timestamp
		var t = clampf(elapsed_time / total_time, 0.0, 1.0) if total_time > 0 else 1.0

		if use_cubic_interpolation and state_history.size() >= 4:
			# Cubic interpolation for smoother curves
			var idx = state_history.find(from_state)
			if idx >= 1 and idx < state_history.size() - 2:
				parent_node.global_position = _cubic_interpolate(
					state_history[idx - 1].position,
					from_state.position,
					to_state.position,
					state_history[idx + 2].position if idx + 2 < state_history.size() else to_state.position,
					t
				)
			else:
				parent_node.global_position = from_state.position.lerp(to_state.position, t)
		else:
			# Linear interpolation
			parent_node.global_position = from_state.position.lerp(to_state.position, t)

		# Rotation interpolation (slerp)
		var from_quat = Quaternion.from_euler(from_state.rotation)
		var to_quat = Quaternion.from_euler(to_state.rotation)
		parent_node.global_rotation = from_quat.slerp(to_quat, t).get_euler()

	elif state_history.size() > 0:
		# Extrapolate from latest state
		var latest = state_history[-1]
		var time_since_last = render_time - latest.timestamp

		if time_since_last < extrapolation_limit:
			_apply_extrapolation(time_since_last, latest)
		else:
			# Too old, snap to latest
			parent_node.global_position = latest.position
			parent_node.global_rotation = latest.rotation

	# Clean old states
	_cleanup_old_states(render_time)

func _cleanup_old_states(render_time: float):
	"""Remove states older than needed"""
	while state_history.size() > 2 and state_history[0].timestamp < render_time - 0.5:
		state_history.pop_front()

func _cubic_interpolate(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	"""Catmull-Rom cubic interpolation for smooth curves"""
	var t2 = t * t
	var t3 = t2 * t

	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _apply_simple_interpolation(delta: float):
	"""Simple lerp interpolation when no history available"""
	var time_since_update = Time.get_ticks_msec() / 1000.0 - last_update_time

	# Check if we need to extrapolate
	if time_since_update > update_interval:
		if time_since_update < extrapolation_limit:
			_apply_extrapolation_simple(time_since_update)
		else:
			parent_node.global_position = target_position
			parent_node.global_rotation = target_rotation
		return

	var distance = parent_node.global_position.distance_to(target_position)

	if distance > snap_distance:
		parent_node.global_position = target_position
		parent_node.global_rotation = target_rotation
		position_corrected.emit(distance)
	else:
		parent_node.global_position = parent_node.global_position.lerp(
			target_position,
			delta * interpolation_rate
		)

		var current_quat = Quaternion.from_euler(parent_node.global_rotation)
		var target_quat = Quaternion.from_euler(target_rotation)
		var interpolated_quat = current_quat.slerp(target_quat, delta * interpolation_rate)
		parent_node.global_rotation = interpolated_quat.get_euler()

func _apply_extrapolation(time_elapsed: float, last_state: Dictionary):
	"""Predict position based on velocity from state history"""
	var velocity = last_state.get("velocity", Vector3.ZERO)
	var extrapolated_position = last_state.position + velocity * time_elapsed

	# Apply with damping to prevent overshoot
	var damping = 1.0 - clampf(time_elapsed / extrapolation_limit, 0.0, 0.5)
	parent_node.global_position = parent_node.global_position.lerp(extrapolated_position, damping * 0.3)

func _apply_extrapolation_simple(time_since_update: float):
	"""Simple velocity-based extrapolation"""
	var extrapolated_position = target_position + target_velocity * time_since_update

	parent_node.global_position = parent_node.global_position.lerp(
		extrapolated_position,
		0.1  # Gentle extrapolation
	)

func receive_network_state(position: Vector3, rotation: Vector3, velocity: Vector3 = Vector3.ZERO, sequence_id: int = -1):
	"""Called when receiving network position update"""
	var current_time = Time.get_ticks_msec() / 1000.0

	# Track packet loss
	total_packets += 1
	if sequence_id >= 0:
		if last_sequence_id >= 0 and sequence_id > last_sequence_id + 1:
			packet_loss_count += sequence_id - last_sequence_id - 1
		last_sequence_id = sequence_id

	# Store in history
	var state = {
		"timestamp": current_time,
		"position": position,
		"rotation": rotation,
		"velocity": velocity,
		"sequence_id": sequence_id
	}
	state_history.append(state)

	# Limit history size
	while state_history.size() > max_history_size:
		state_history.pop_front()

	# Update target (fallback)
	previous_position = target_position
	previous_rotation = target_rotation
	target_position = position
	target_rotation = rotation
	target_velocity = velocity

	# Calculate update interval
	if last_update_time > 0:
		var new_interval = current_time - last_update_time
		update_interval = lerp(update_interval, new_interval, 0.1)

	last_update_time = current_time

func receive_network_state_with_timestamp(position: Vector3, rotation: Vector3, velocity: Vector3, server_timestamp: float):
	"""Receive state with server timestamp for better synchronization"""
	var current_time = Time.get_ticks_msec() / 1000.0

	# Calculate latency
	var latency = current_time - server_timestamp
	_update_latency(latency)

	# Store in history with adjusted timestamp
	var state = {
		"timestamp": server_timestamp,
		"position": position,
		"rotation": rotation,
		"velocity": velocity
	}

	# Insert in chronological order
	var inserted = false
	for i in range(state_history.size() - 1, -1, -1):
		if state_history[i].timestamp < server_timestamp:
			state_history.insert(i + 1, state)
			inserted = true
			break

	if not inserted:
		state_history.push_front(state)

	while state_history.size() > max_history_size:
		state_history.pop_front()

	target_position = position
	target_rotation = rotation
	target_velocity = velocity
	last_update_time = current_time

func _update_latency(latency: float):
	"""Track average network latency"""
	latency_samples.append(latency)
	while latency_samples.size() > MAX_LATENCY_SAMPLES:
		latency_samples.pop_front()

	var sum = 0.0
	for sample in latency_samples:
		sum += sample
	average_latency = sum / latency_samples.size() if latency_samples.size() > 0 else 0.0

	latency_updated.emit(average_latency * 1000.0)  # Emit in milliseconds

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

func get_average_latency_ms() -> float:
	return average_latency * 1000.0

func get_packet_loss_percent() -> float:
	if total_packets == 0:
		return 0.0
	return (float(packet_loss_count) / float(total_packets)) * 100.0

func reset_stats():
	"""Reset network statistics"""
	packet_loss_count = 0
	total_packets = 0
	latency_samples.clear()
	average_latency = 0.0

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
		"position": parent_node.global_position if parent_node else Vector3.ZERO,
		"timestamp": Time.get_ticks_msec() / 1000.0
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
			position_corrected.emit(prediction_error)

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
	if "position" in input_data and parent_node:
		parent_node.global_position = input_data.position
