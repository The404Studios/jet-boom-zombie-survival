extends Node

## Network-replicated building and prop system
## Props have HP and can be damaged/destroyed
## Supports barricades, doors, and destructible objects

signal prop_damaged(prop_id: int, damage: float, new_health: float)
signal prop_destroyed(prop_id: int, position: Vector3)
signal prop_repaired(prop_id: int, amount: float, new_health: float)
signal door_state_changed(door_id: int, is_open: bool)
signal barricade_placed(barricade_id: int, position: Vector3, rotation: Vector3)

# Prop types
enum PropType {
	DESTRUCTIBLE,
	BARRICADE,
	DOOR,
	WINDOW,
	FURNITURE,
	EXPLOSIVE
}

# Tracked props
var props: Dictionary = {}  # prop_id -> PropData
var next_prop_id: int = 1

# Network manager reference
var network_manager: Node = null
var is_server: bool = false

class PropData:
	var prop_id: int = 0
	var prop_type: PropType = PropType.DESTRUCTIBLE
	var node: Node3D = null
	var max_health: float = 100.0
	var current_health: float = 100.0
	var position: Vector3 = Vector3.ZERO
	var rotation: Vector3 = Vector3.ZERO
	var is_destroyed: bool = false
	var owner_peer_id: int = 0  # Who placed it (for barricades)
	var can_be_repaired: bool = true
	var repair_cost: int = 50

	# Door specific
	var is_open: bool = false
	var is_locked: bool = false

	func to_dict() -> Dictionary:
		return {
			"prop_id": prop_id,
			"prop_type": prop_type,
			"max_health": max_health,
			"current_health": current_health,
			"position": [position.x, position.y, position.z],
			"rotation": [rotation.x, rotation.y, rotation.z],
			"is_destroyed": is_destroyed,
			"owner_peer_id": owner_peer_id,
			"is_open": is_open,
			"is_locked": is_locked
		}

	static func from_dict(data: Dictionary) -> PropData:
		var prop = PropData.new()
		prop.prop_id = data.get("prop_id", 0)
		prop.prop_type = data.get("prop_type", PropType.DESTRUCTIBLE)
		prop.max_health = data.get("max_health", 100.0)
		prop.current_health = data.get("current_health", 100.0)

		var pos = data.get("position", [0, 0, 0])
		if pos is Array and pos.size() >= 3:
			prop.position = Vector3(pos[0], pos[1], pos[2])

		var rot = data.get("rotation", [0, 0, 0])
		if rot is Array and rot.size() >= 3:
			prop.rotation = Vector3(rot[0], rot[1], rot[2])

		prop.is_destroyed = data.get("is_destroyed", false)
		prop.owner_peer_id = data.get("owner_peer_id", 0)
		prop.is_open = data.get("is_open", false)
		prop.is_locked = data.get("is_locked", false)

		return prop

func _ready():
	network_manager = get_node_or_null("/root/NetworkManager")
	is_server = multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true

	# Register existing props in scene
	call_deferred("_register_scene_props")

func _register_scene_props():
	"""Find and register all props in the current scene"""
	# Find destructible props
	for prop in get_tree().get_nodes_in_group("destructible_props"):
		register_prop(prop, PropType.DESTRUCTIBLE)

	# Find doors
	for door in get_tree().get_nodes_in_group("doors"):
		register_prop(door, PropType.DOOR)

	# Find barricade points
	for barricade in get_tree().get_nodes_in_group("barricades"):
		register_prop(barricade, PropType.BARRICADE)

	# Find windows
	for window in get_tree().get_nodes_in_group("windows"):
		register_prop(window, PropType.WINDOW)

# ============================================
# PROP REGISTRATION
# ============================================

func register_prop(node: Node3D, type: PropType, max_hp: float = 100.0) -> int:
	"""Register a prop for network synchronization"""
	var prop = PropData.new()
	prop.prop_id = next_prop_id
	prop.prop_type = type
	prop.node = node
	prop.max_health = max_hp
	prop.current_health = max_hp
	prop.position = node.global_position
	prop.rotation = node.rotation

	# Get health from node if it has it
	if "max_health" in node:
		prop.max_health = node.max_health
		prop.current_health = node.max_health
	if "health" in node:
		prop.current_health = node.health

	props[next_prop_id] = prop
	next_prop_id += 1

	# Set prop ID on node if possible
	if "prop_id" in node:
		node.prop_id = prop.prop_id

	return prop.prop_id

func unregister_prop(prop_id: int):
	"""Remove a prop from tracking"""
	if props.has(prop_id):
		props.erase(prop_id)

# ============================================
# DAMAGE SYSTEM
# ============================================

func damage_prop(prop_id: int, damage: float, attacker_peer_id: int = 0) -> bool:
	"""Damage a prop (server authoritative)"""
	if not props.has(prop_id):
		return false

	var prop = props[prop_id]
	if prop.is_destroyed:
		return false

	# Apply damage
	prop.current_health = max(0, prop.current_health - damage)

	# Update node if exists
	if is_instance_valid(prop.node) and "health" in prop.node:
		prop.node.health = prop.current_health

	# Broadcast damage
	if is_server:
		_sync_prop_damage.rpc(prop_id, damage, prop.current_health)

	prop_damaged.emit(prop_id, damage, prop.current_health)

	# Check for destruction
	if prop.current_health <= 0:
		_destroy_prop(prop_id)
		return true

	return false

func _destroy_prop(prop_id: int):
	"""Destroy a prop"""
	if not props.has(prop_id):
		return

	var prop = props[prop_id]
	prop.is_destroyed = true

	var position = prop.position
	if is_instance_valid(prop.node):
		position = prop.node.global_position

		# Play destruction effect if available
		if prop.node.has_method("on_destroyed"):
			prop.node.on_destroyed()
		else:
			prop.node.queue_free()

	# Broadcast destruction
	if is_server:
		_sync_prop_destroyed.rpc(prop_id, position)

	prop_destroyed.emit(prop_id, position)

func repair_prop(prop_id: int, amount: float, repairer_peer_id: int = 0) -> bool:
	"""Repair a prop"""
	if not props.has(prop_id):
		return false

	var prop = props[prop_id]
	if prop.is_destroyed or not prop.can_be_repaired:
		return false

	if prop.current_health >= prop.max_health:
		return false

	prop.current_health = min(prop.max_health, prop.current_health + amount)

	if is_instance_valid(prop.node) and "health" in prop.node:
		prop.node.health = prop.current_health

	# Broadcast repair
	if is_server:
		_sync_prop_repaired.rpc(prop_id, amount, prop.current_health)

	prop_repaired.emit(prop_id, amount, prop.current_health)
	return true

# ============================================
# DOOR SYSTEM
# ============================================

func toggle_door(door_id: int, opener_peer_id: int = 0) -> bool:
	"""Toggle a door open/closed"""
	if not props.has(door_id):
		return false

	var prop = props[door_id]
	if prop.prop_type != PropType.DOOR:
		return false

	if prop.is_locked:
		return false

	prop.is_open = not prop.is_open

	if is_instance_valid(prop.node):
		if prop.node.has_method("set_open"):
			prop.node.set_open(prop.is_open)
		elif "is_open" in prop.node:
			prop.node.is_open = prop.is_open

	# Broadcast state change
	if is_server:
		_sync_door_state.rpc(door_id, prop.is_open)

	door_state_changed.emit(door_id, prop.is_open)
	return true

func lock_door(door_id: int, locked: bool) -> bool:
	"""Lock/unlock a door"""
	if not props.has(door_id):
		return false

	var prop = props[door_id]
	if prop.prop_type != PropType.DOOR:
		return false

	prop.is_locked = locked

	if is_instance_valid(prop.node) and "is_locked" in prop.node:
		prop.node.is_locked = locked

	return true

# ============================================
# BARRICADE SYSTEM
# ============================================

func place_barricade(position: Vector3, rotation: Vector3, placer_peer_id: int, barricade_type: String = "wooden") -> int:
	"""Place a new barricade"""
	# Load barricade scene - use correct path in environment folder
	var scene_path = "res://scenes/environment/barricade.tscn"
	if not ResourceLoader.exists(scene_path):
		push_warning("Barricade scene not found: %s" % scene_path)
		return -1

	var barricade_scene = load(scene_path)
	if not barricade_scene:
		return -1

	var barricade = barricade_scene.instantiate()
	barricade.global_position = position
	barricade.rotation = rotation

	var scene = get_tree().current_scene
	if scene:
		scene.add_child(barricade)

	# Register the barricade
	var prop_id = register_prop(barricade, PropType.BARRICADE, 200.0)
	props[prop_id].owner_peer_id = placer_peer_id

	# Broadcast placement
	if is_server:
		_sync_barricade_placed.rpc(prop_id, position, rotation, barricade_type)

	barricade_placed.emit(prop_id, position, rotation)
	return prop_id

func remove_barricade(prop_id: int, remover_peer_id: int) -> bool:
	"""Remove a barricade (only owner or with enough damage)"""
	if not props.has(prop_id):
		return false

	var prop = props[prop_id]
	if prop.prop_type != PropType.BARRICADE:
		return false

	# Only owner can remove without damage
	if prop.owner_peer_id != remover_peer_id and remover_peer_id != 0:
		return false

	_destroy_prop(prop_id)
	return true

# ============================================
# NETWORK SYNCHRONIZATION
# ============================================

@rpc("authority", "call_remote", "reliable")
func _sync_prop_damage(_prop_id: int, _damage: float, _new_health: float):
	"""Client receives prop damage"""
	if props.has(_prop_id):
		props[_prop_id].current_health = _new_health
		if is_instance_valid(props[_prop_id].node) and "health" in props[_prop_id].node:
			props[_prop_id].node.health = _new_health
		prop_damaged.emit(_prop_id, _damage, _new_health)

@rpc("authority", "call_remote", "reliable")
func _sync_prop_destroyed(_prop_id: int, _position: Vector3):
	"""Client receives prop destruction"""
	if props.has(_prop_id):
		var prop = props[_prop_id]
		prop.is_destroyed = true
		if is_instance_valid(prop.node):
			if prop.node.has_method("on_destroyed"):
				prop.node.on_destroyed()
			else:
				prop.node.queue_free()
		prop_destroyed.emit(_prop_id, _position)

@rpc("authority", "call_remote", "reliable")
func _sync_prop_repaired(_prop_id: int, _amount: float, _new_health: float):
	"""Client receives prop repair"""
	if props.has(_prop_id):
		props[_prop_id].current_health = _new_health
		if is_instance_valid(props[_prop_id].node) and "health" in props[_prop_id].node:
			props[_prop_id].node.health = _new_health
		prop_repaired.emit(_prop_id, _amount, _new_health)

@rpc("authority", "call_remote", "reliable")
func _sync_door_state(_door_id: int, _is_open: bool):
	"""Client receives door state change"""
	if props.has(_door_id):
		props[_door_id].is_open = _is_open
		if is_instance_valid(props[_door_id].node):
			if props[_door_id].node.has_method("set_open"):
				props[_door_id].node.set_open(_is_open)
			elif "is_open" in props[_door_id].node:
				props[_door_id].node.is_open = _is_open
		door_state_changed.emit(_door_id, _is_open)

@rpc("authority", "call_remote", "reliable")
func _sync_barricade_placed(_prop_id: int, _position: Vector3, _rotation: Vector3, _type: String):
	"""Client receives barricade placement"""
	if not is_server:
		# Spawn barricade on client - use correct path in environment folder
		var scene_path = "res://scenes/environment/barricade.tscn"
		if not ResourceLoader.exists(scene_path):
			push_warning("Barricade scene not found on client: %s" % scene_path)
			return

		var barricade_scene = load(scene_path)
		if barricade_scene:
			var barricade = barricade_scene.instantiate()
			barricade.global_position = _position
			barricade.rotation = _rotation

			var scene = get_tree().current_scene
			if scene:
				scene.add_child(barricade)

			# Register locally with same ID
			var prop = PropData.new()
			prop.prop_id = _prop_id
			prop.prop_type = PropType.BARRICADE
			prop.node = barricade
			prop.position = _position
			prop.rotation = _rotation
			props[_prop_id] = prop

		barricade_placed.emit(_prop_id, _position, _rotation)

# Request to place barricade (client to server)
@rpc("any_peer", "reliable")
func request_place_barricade(position: Vector3, rotation: Vector3, barricade_type: String):
	"""Client requests to place a barricade"""
	if is_server:
		var peer_id = multiplayer.get_remote_sender_id()
		place_barricade(position, rotation, peer_id, barricade_type)

# Request to damage prop (client to server)
@rpc("any_peer", "reliable")
func request_damage_prop(prop_id: int, damage: float):
	"""Client requests to damage a prop"""
	if is_server:
		var peer_id = multiplayer.get_remote_sender_id()
		damage_prop(prop_id, damage, peer_id)

# Request to toggle door (client to server)
@rpc("any_peer", "reliable")
func request_toggle_door(door_id: int):
	"""Client requests to toggle a door"""
	if is_server:
		var peer_id = multiplayer.get_remote_sender_id()
		toggle_door(door_id, peer_id)

# ============================================
# FULL STATE SYNC
# ============================================

func get_all_props_state() -> Array:
	"""Get state of all props for new player sync"""
	var states = []
	for prop_id in props:
		states.append(props[prop_id].to_dict())
	return states

func sync_all_props_to_peer(peer_id: int):
	"""Send all prop states to a specific peer"""
	var states = get_all_props_state()
	_receive_full_prop_sync.rpc_id(peer_id, states)

@rpc("authority", "reliable")
func _receive_full_prop_sync(states: Array):
	"""Client receives full prop state sync"""
	for state_dict in states:
		var prop_id = state_dict.get("prop_id", 0)
		if props.has(prop_id):
			# Update existing prop
			var prop = props[prop_id]
			prop.current_health = state_dict.get("current_health", 100.0)
			prop.is_destroyed = state_dict.get("is_destroyed", false)
			prop.is_open = state_dict.get("is_open", false)
			prop.is_locked = state_dict.get("is_locked", false)

			if is_instance_valid(prop.node):
				if "health" in prop.node:
					prop.node.health = prop.current_health
				if prop.prop_type == PropType.DOOR and prop.node.has_method("set_open"):
					prop.node.set_open(prop.is_open)

# ============================================
# UTILITY
# ============================================

func get_prop(prop_id: int) -> PropData:
	return props.get(prop_id, null)

func get_props_in_radius(position: Vector3, radius: float) -> Array:
	"""Get all props within a radius"""
	var result = []
	for prop_id in props:
		var prop = props[prop_id]
		if not prop.is_destroyed:
			var prop_pos = prop.position
			if is_instance_valid(prop.node):
				prop_pos = prop.node.global_position
			if prop_pos.distance_to(position) <= radius:
				result.append(prop)
	return result

func get_nearest_interactable(position: Vector3, max_distance: float = 3.0) -> PropData:
	"""Get nearest interactable prop (door, barricade point)"""
	var nearest: PropData = null
	var nearest_dist: float = max_distance

	for prop_id in props:
		var prop = props[prop_id]
		if prop.is_destroyed:
			continue
		if prop.prop_type not in [PropType.DOOR, PropType.BARRICADE]:
			continue

		var prop_pos = prop.position
		if is_instance_valid(prop.node):
			prop_pos = prop.node.global_position

		var dist = position.distance_to(prop_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = prop

	return nearest
