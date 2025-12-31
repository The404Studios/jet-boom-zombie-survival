extends Node
class_name StateSynchronizer

# Efficient state synchronization for multiplayer
# Handles delta compression, interest management, and priority-based updates

signal state_received(entity_id: int, state: Dictionary)
signal sync_error(error: String)

# Sync settings
@export var tick_rate: int = 20  # Updates per second
@export var max_packet_size: int = 1024  # Bytes
@export var interest_radius: float = 50.0  # Only sync nearby entities
@export var priority_distance: float = 20.0  # High priority within this range

# Entity tracking
var tracked_entities: Dictionary = {}  # entity_id -> EntityState
var entity_priorities: Dictionary = {}  # entity_id -> priority (0-1)

# State compression
var previous_states: Dictionary = {}  # entity_id -> last sent state
var dirty_entities: Array = []  # Entities needing sync

# Timing
var tick_interval: float = 0.05
var tick_timer: float = 0.0
var current_tick: int = 0

# Network
var is_authority: bool = false

class EntityState:
	var entity_id: int = 0
	var entity_type: String = ""
	var owner_id: int = 1
	var position: Vector3 = Vector3.ZERO
	var rotation: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var custom_data: Dictionary = {}
	var last_update_tick: int = 0
	var is_dirty: bool = false

	func to_dict() -> Dictionary:
		return {
			"id": entity_id,
			"type": entity_type,
			"owner": owner_id,
			"pos": _compress_vector(position),
			"rot": _compress_vector(rotation),
			"vel": _compress_vector(velocity),
			"data": custom_data,
			"tick": last_update_tick
		}

	func from_dict(dict: Dictionary):
		entity_id = dict.get("id", 0)
		entity_type = dict.get("type", "")
		owner_id = dict.get("owner", 1)
		position = _decompress_vector(dict.get("pos", [0, 0, 0]))
		rotation = _decompress_vector(dict.get("rot", [0, 0, 0]))
		velocity = _decompress_vector(dict.get("vel", [0, 0, 0]))
		custom_data = dict.get("data", {})
		last_update_tick = dict.get("tick", 0)

	func _compress_vector(v: Vector3) -> Array:
		# Compress to 2 decimal places
		return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

	func _decompress_vector(arr: Array) -> Vector3:
		if arr.size() < 3:
			return Vector3.ZERO
		return Vector3(arr[0], arr[1], arr[2])

	func get_delta(previous: EntityState) -> Dictionary:
		"""Get only changed fields"""
		var delta = {"id": entity_id}

		if position.distance_to(previous.position) > 0.01:
			delta["pos"] = _compress_vector(position)

		if rotation.distance_to(previous.rotation) > 0.01:
			delta["rot"] = _compress_vector(rotation)

		if velocity.distance_to(previous.velocity) > 0.1:
			delta["vel"] = _compress_vector(velocity)

		if custom_data != previous.custom_data:
			delta["data"] = custom_data

		delta["tick"] = last_update_tick

		return delta

func _ready():
	tick_interval = 1.0 / tick_rate
	is_authority = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _process(delta):
	tick_timer += delta

	if tick_timer >= tick_interval:
		tick_timer -= tick_interval
		current_tick += 1
		_process_tick()

func _process_tick():
	"""Process one sync tick"""
	if not is_authority:
		return

	# Update priorities based on local player position
	_update_priorities()

	# Collect dirty entities
	_collect_dirty_entities()

	# Build and send state packets
	_send_state_updates()

# ============================================
# ENTITY REGISTRATION
# ============================================

func register_entity(entity: Node, entity_type: String = "generic") -> int:
	"""Register an entity for state sync"""
	var entity_id = entity.get_instance_id()

	var state = EntityState.new()
	state.entity_id = entity_id
	state.entity_type = entity_type
	state.owner_id = entity.get_multiplayer_authority() if entity.has_method("get_multiplayer_authority") else 1

	if entity is Node3D:
		state.position = entity.global_position
		state.rotation = entity.rotation

	tracked_entities[entity_id] = state
	entity_priorities[entity_id] = 0.5

	return entity_id

func unregister_entity(entity_id: int):
	"""Unregister an entity"""
	tracked_entities.erase(entity_id)
	previous_states.erase(entity_id)
	entity_priorities.erase(entity_id)
	dirty_entities.erase(entity_id)

func update_entity_state(entity_id: int, position: Vector3 = Vector3.INF,
						 rotation: Vector3 = Vector3.INF, velocity: Vector3 = Vector3.INF,
						 custom_data: Dictionary = {}):
	"""Update an entity's state"""
	if not tracked_entities.has(entity_id):
		return

	var state = tracked_entities[entity_id] as EntityState

	if position != Vector3.INF:
		if state.position.distance_to(position) > 0.01:
			state.position = position
			state.is_dirty = true

	if rotation != Vector3.INF:
		if state.rotation.distance_to(rotation) > 0.01:
			state.rotation = rotation
			state.is_dirty = true

	if velocity != Vector3.INF:
		state.velocity = velocity

	if not custom_data.is_empty():
		state.custom_data.merge(custom_data, true)
		state.is_dirty = true

	state.last_update_tick = current_tick

func mark_dirty(entity_id: int):
	"""Mark entity as needing sync"""
	if tracked_entities.has(entity_id):
		tracked_entities[entity_id].is_dirty = true

# ============================================
# PRIORITY & INTEREST
# ============================================

func _update_priorities():
	"""Update sync priorities based on distance to local player"""
	var local_player = _get_local_player()
	if not local_player:
		return

	var player_pos = local_player.global_position

	for entity_id in tracked_entities:
		var state = tracked_entities[entity_id] as EntityState
		var distance = state.position.distance_to(player_pos)

		# Calculate priority (1.0 = highest, 0.0 = lowest)
		if distance <= priority_distance:
			entity_priorities[entity_id] = 1.0
		elif distance <= interest_radius:
			# Linear falloff
			entity_priorities[entity_id] = 1.0 - ((distance - priority_distance) / (interest_radius - priority_distance))
		else:
			entity_priorities[entity_id] = 0.0

func _collect_dirty_entities():
	"""Collect entities that need syncing"""
	dirty_entities.clear()

	for entity_id in tracked_entities:
		var state = tracked_entities[entity_id] as EntityState
		var priority = entity_priorities.get(entity_id, 0.0)

		# Skip low priority entities that aren't dirty
		if priority < 0.1 and not state.is_dirty:
			continue

		# High priority entities sync every tick
		# Lower priority entities sync less frequently
		var sync_interval = max(1, int(10 * (1.0 - priority)))
		if current_tick % sync_interval == 0 or state.is_dirty:
			dirty_entities.append(entity_id)

	# Sort by priority (highest first)
	dirty_entities.sort_custom(func(a, b):
		return entity_priorities.get(a, 0) > entity_priorities.get(b, 0)
	)

# ============================================
# NETWORK SYNC
# ============================================

func _send_state_updates():
	"""Send state updates to all clients"""
	if dirty_entities.is_empty():
		return

	var packets = _build_packets()

	for packet in packets:
		_broadcast_state.rpc(packet)

func _build_packets() -> Array:
	"""Build state update packets with size limits"""
	var packets = []
	var current_packet = []
	var current_size = 0

	for entity_id in dirty_entities:
		if not tracked_entities.has(entity_id):
			continue

		var state = tracked_entities[entity_id] as EntityState
		var state_dict: Dictionary

		# Use delta compression if we have previous state
		if previous_states.has(entity_id):
			state_dict = state.get_delta(previous_states[entity_id])
		else:
			state_dict = state.to_dict()

		# Estimate size (rough approximation)
		var estimated_size = str(state_dict).length()

		if current_size + estimated_size > max_packet_size and not current_packet.is_empty():
			packets.append(current_packet)
			current_packet = []
			current_size = 0

		current_packet.append(state_dict)
		current_size += estimated_size

		# Store for delta compression
		var prev = EntityState.new()
		prev.position = state.position
		prev.rotation = state.rotation
		prev.velocity = state.velocity
		prev.custom_data = state.custom_data.duplicate()
		previous_states[entity_id] = prev

		# Clear dirty flag
		state.is_dirty = false

	if not current_packet.is_empty():
		packets.append(current_packet)

	return packets

@rpc("authority", "unreliable_ordered")
func _broadcast_state(states: Array):
	"""Receive state updates from server"""
	for state_dict in states:
		var entity_id = state_dict.get("id", 0)
		if entity_id == 0:
			continue

		# Apply state
		_apply_received_state(entity_id, state_dict)

		state_received.emit(entity_id, state_dict)

func _apply_received_state(entity_id: int, state_dict: Dictionary):
	"""Apply received state to tracked entity"""
	# Update or create entity state
	if not tracked_entities.has(entity_id):
		var state = EntityState.new()
		state.from_dict(state_dict)
		tracked_entities[entity_id] = state
	else:
		var state = tracked_entities[entity_id] as EntityState

		# Apply delta updates
		if state_dict.has("pos"):
			state.position = state._decompress_vector(state_dict.pos)
		if state_dict.has("rot"):
			state.rotation = state._decompress_vector(state_dict.rot)
		if state_dict.has("vel"):
			state.velocity = state._decompress_vector(state_dict.vel)
		if state_dict.has("data"):
			state.custom_data.merge(state_dict.data, true)
		if state_dict.has("tick"):
			state.last_update_tick = state_dict.tick

# ============================================
# RELIABLE STATE SYNC
# ============================================

func sync_reliable(entity_id: int, data: Dictionary):
	"""Send reliable state update (for important changes)"""
	if not multiplayer.has_multiplayer_peer():
		return

	_reliable_sync.rpc(entity_id, data)

@rpc("any_peer", "reliable")
func _reliable_sync(entity_id: int, data: Dictionary):
	"""Receive reliable state update"""
	_apply_received_state(entity_id, data)
	state_received.emit(entity_id, data)

# ============================================
# FULL STATE SYNC
# ============================================

func request_full_state():
	"""Request full state from server (for late joiners)"""
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_full_state.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_full_state():
	"""Handle full state request"""
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()

	# Build full state for all entities
	var full_state = []
	for entity_id in tracked_entities:
		var state = tracked_entities[entity_id] as EntityState
		full_state.append(state.to_dict())

	_receive_full_state.rpc_id(sender_id, full_state)

@rpc("authority", "reliable")
func _receive_full_state(states: Array):
	"""Receive full state from server"""
	for state_dict in states:
		var entity_id = state_dict.get("id", 0)
		if entity_id == 0:
			continue

		_apply_received_state(entity_id, state_dict)

# ============================================
# UTILITY
# ============================================

func _get_local_player() -> Node3D:
	"""Get the local player node"""
	var player_manager = get_node_or_null("/root/PlayerManager")
	if player_manager and player_manager.has_method("get_local_player"):
		return player_manager.get_local_player()

	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player is Node3D:
			var authority = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 1
			if authority == multiplayer.get_unique_id():
				return player

	return null

func get_entity_state(entity_id: int) -> EntityState:
	"""Get current state of an entity"""
	return tracked_entities.get(entity_id, null)

func get_tracked_count() -> int:
	"""Get number of tracked entities"""
	return tracked_entities.size()

func set_tick_rate(rate: int):
	"""Change tick rate"""
	tick_rate = rate
	tick_interval = 1.0 / tick_rate

func get_current_tick() -> int:
	return current_tick
