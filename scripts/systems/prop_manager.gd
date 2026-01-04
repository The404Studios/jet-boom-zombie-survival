extends Node
class_name PropManager

## Manages all props/barricades in the game
## Handles placement, tracking, zombie targeting, and network sync

signal prop_placed(prop: Node, owner_id: int)
signal prop_destroyed(prop: Node)
signal prop_picked_up(prop: Node, picker_id: int)
signal props_updated

# Prop scenes by type
const PROP_SCENES = {
	Barricade.BarricadeType.DOORWAY: "res://scenes/props/doorway_barricade.tscn",
	Barricade.BarricadeType.WALL: "res://scenes/props/wall_barricade.tscn",
	Barricade.BarricadeType.WINDOW_BOARD: "res://scenes/props/window_board.tscn",
	Barricade.BarricadeType.WIRE_FENCE: "res://scenes/props/wire_fence.tscn",
	Barricade.BarricadeType.SANDBAG: "res://scenes/props/sandbag.tscn",
	Barricade.BarricadeType.METAL_SHEET: "res://scenes/props/metal_sheet.tscn",
	Barricade.BarricadeType.WOODEN_PLANK: "res://scenes/props/wooden_plank.tscn",
	Barricade.BarricadeType.HALLWAY_BLOCK: "res://scenes/props/hallway_block.tscn",
	Barricade.BarricadeType.FLOOR_TRAP: "res://scenes/props/floor_trap.tscn",
	Barricade.BarricadeType.SIGIL: "res://scenes/props/sigil.tscn"
}

# Prop costs
const PROP_COSTS = {
	Barricade.BarricadeType.DOORWAY: 200,
	Barricade.BarricadeType.WALL: 150,
	Barricade.BarricadeType.WINDOW_BOARD: 50,
	Barricade.BarricadeType.WIRE_FENCE: 100,
	Barricade.BarricadeType.SANDBAG: 75,
	Barricade.BarricadeType.METAL_SHEET: 125,
	Barricade.BarricadeType.WOODEN_PLANK: 25,
	Barricade.BarricadeType.HALLWAY_BLOCK: 175,
	Barricade.BarricadeType.FLOOR_TRAP: 150,
	Barricade.BarricadeType.SIGIL: 300
}

# Prop HP
const PROP_HP = {
	Barricade.BarricadeType.DOORWAY: 200.0,
	Barricade.BarricadeType.WALL: 300.0,
	Barricade.BarricadeType.WINDOW_BOARD: 75.0,
	Barricade.BarricadeType.WIRE_FENCE: 100.0,
	Barricade.BarricadeType.SANDBAG: 150.0,
	Barricade.BarricadeType.METAL_SHEET: 200.0,
	Barricade.BarricadeType.WOODEN_PLANK: 50.0,
	Barricade.BarricadeType.HALLWAY_BLOCK: 250.0,
	Barricade.BarricadeType.FLOOR_TRAP: 100.0,
	Barricade.BarricadeType.SIGIL: 500.0
}

# Active props tracking
var active_props: Dictionary = {}  # network_id -> Barricade
var prop_by_owner: Dictionary = {}  # peer_id -> [Barricade]
var props_container: Node3D = null

# Network
var next_prop_id: int = 1

func _ready():
	# Create container for props
	props_container = Node3D.new()
	props_container.name = "PropsContainer"
	add_child(props_container)

	# Connect to network manager signals
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.player_disconnected.connect(_on_player_disconnected)

func _process(_delta):
	# Cleanup destroyed props
	_cleanup_destroyed_props()

# ============================================
# PROP PLACEMENT
# ============================================

func place_prop(prop_type: int, position: Vector3, rotation: Vector3, owner_id: int) -> Barricade:
	"""Place a new prop at the specified location"""
	var scene_path = PROP_SCENES.get(prop_type, "")
	if scene_path.is_empty():
		# Use default barricade scene
		scene_path = "res://scenes/props/barricade.tscn"

	var scene: PackedScene
	if ResourceLoader.exists(scene_path):
		scene = load(scene_path)
	else:
		# Create basic barricade
		return _create_basic_barricade(prop_type, position, rotation, owner_id)

	var prop = scene.instantiate() as Barricade
	if not prop:
		push_error("Failed to instantiate prop scene")
		return null

	# Configure prop
	prop.network_id = next_prop_id
	next_prop_id += 1
	prop.barricade_type = prop_type
	prop.owner_peer_id = owner_id
	prop.max_health = PROP_HP.get(prop_type, 100.0)
	prop.current_health = prop.max_health
	prop.placement_cost = PROP_COSTS.get(prop_type, 100)

	# Position
	prop.global_position = position
	prop.global_rotation = rotation

	# Add to scene
	props_container.add_child(prop)

	# Track
	active_props[prop.network_id] = prop
	if not prop_by_owner.has(owner_id):
		prop_by_owner[owner_id] = []
	prop_by_owner[owner_id].append(prop)

	# Connect signals
	prop.destroyed.connect(_on_prop_destroyed.bind(prop))

	prop_placed.emit(prop, owner_id)

	# Network sync
	if multiplayer.is_server():
		_sync_prop_placed.rpc(prop.to_network_data())

	return prop

func _create_basic_barricade(prop_type: int, position: Vector3, rotation: Vector3, owner_id: int) -> Barricade:
	"""Create a basic barricade without a scene file"""
	var prop = Barricade.new()
	prop.name = "Barricade_%d" % next_prop_id

	# Create collision shape
	var collision = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = _get_prop_size(prop_type)
	collision.shape = box_shape
	prop.add_child(collision)

	# Create mesh
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var box_mesh = BoxMesh.new()
	box_mesh.size = box_shape.size
	mesh_instance.mesh = box_mesh

	# Material based on type
	var material = StandardMaterial3D.new()
	material.albedo_color = _get_prop_color(prop_type)
	mesh_instance.set_surface_override_material(0, material)
	prop.add_child(mesh_instance)

	# Configure
	prop.network_id = next_prop_id
	next_prop_id += 1
	prop.barricade_type = prop_type
	prop.owner_peer_id = owner_id
	prop.max_health = PROP_HP.get(prop_type, 100.0)
	prop.current_health = prop.max_health
	prop.placement_cost = PROP_COSTS.get(prop_type, 100)
	prop.global_position = position
	prop.global_rotation = rotation

	props_container.add_child(prop)

	# Track
	active_props[prop.network_id] = prop
	if not prop_by_owner.has(owner_id):
		prop_by_owner[owner_id] = []
	prop_by_owner[owner_id].append(prop)

	prop.destroyed.connect(_on_prop_destroyed.bind(prop))
	prop_placed.emit(prop, owner_id)

	if multiplayer.is_server():
		_sync_prop_placed.rpc(prop.to_network_data())

	return prop

func _get_prop_size(prop_type: int) -> Vector3:
	match prop_type:
		Barricade.BarricadeType.DOORWAY: return Vector3(2.0, 2.5, 0.3)
		Barricade.BarricadeType.WALL: return Vector3(3.0, 2.0, 0.2)
		Barricade.BarricadeType.WINDOW_BOARD: return Vector3(1.2, 1.0, 0.1)
		Barricade.BarricadeType.WIRE_FENCE: return Vector3(2.0, 1.5, 0.1)
		Barricade.BarricadeType.SANDBAG: return Vector3(1.0, 0.5, 0.5)
		Barricade.BarricadeType.METAL_SHEET: return Vector3(1.5, 2.0, 0.05)
		Barricade.BarricadeType.WOODEN_PLANK: return Vector3(0.2, 1.5, 0.05)
		Barricade.BarricadeType.HALLWAY_BLOCK: return Vector3(2.5, 2.0, 0.5)
		Barricade.BarricadeType.FLOOR_TRAP: return Vector3(1.0, 0.1, 1.0)
		Barricade.BarricadeType.SIGIL: return Vector3(1.5, 0.05, 1.5)
	return Vector3.ONE

func _get_prop_color(prop_type: int) -> Color:
	match prop_type:
		Barricade.BarricadeType.DOORWAY: return Color(0.4, 0.3, 0.2)  # Brown
		Barricade.BarricadeType.WALL: return Color(0.5, 0.5, 0.5)  # Gray
		Barricade.BarricadeType.WINDOW_BOARD: return Color(0.6, 0.4, 0.2)
		Barricade.BarricadeType.WIRE_FENCE: return Color(0.7, 0.7, 0.7)
		Barricade.BarricadeType.SANDBAG: return Color(0.6, 0.5, 0.3)
		Barricade.BarricadeType.METAL_SHEET: return Color(0.6, 0.6, 0.65)
		Barricade.BarricadeType.WOODEN_PLANK: return Color(0.5, 0.35, 0.2)
		Barricade.BarricadeType.HALLWAY_BLOCK: return Color(0.55, 0.45, 0.35)
		Barricade.BarricadeType.FLOOR_TRAP: return Color(0.3, 0.3, 0.3)
		Barricade.BarricadeType.SIGIL: return Color(0.8, 0.2, 0.8)  # Purple
	return Color.WHITE

# ============================================
# PROP REMOVAL
# ============================================

func remove_prop(network_id: int):
	"""Remove a prop from the game"""
	if not active_props.has(network_id):
		return

	var prop = active_props[network_id] as Barricade
	if not prop:
		return

	# Remove from tracking
	active_props.erase(network_id)

	if prop_by_owner.has(prop.owner_peer_id):
		prop_by_owner[prop.owner_peer_id].erase(prop)

	# Destroy
	prop.queue_free()

	if multiplayer.is_server():
		_sync_prop_removed.rpc(network_id)

func pick_up_prop(network_id: int, picker_id: int) -> bool:
	"""Pick up a prop (returns to inventory)"""
	if not active_props.has(network_id):
		return false

	var prop = active_props[network_id] as Barricade
	if not prop or not prop.can_be_picked_up:
		return false

	# Can only pick up undamaged or own props
	if prop.owner_peer_id != picker_id and prop.get_health_percent() < 1.0:
		return false

	prop_picked_up.emit(prop, picker_id)
	remove_prop(network_id)

	if multiplayer.is_server():
		_sync_prop_picked_up.rpc(network_id, picker_id)

	return true

func _on_prop_destroyed(prop: Barricade):
	"""Handle prop destruction"""
	if not is_instance_valid(prop):
		return

	var network_id = prop.network_id

	# Remove from tracking
	active_props.erase(network_id)

	if prop_by_owner.has(prop.owner_peer_id):
		prop_by_owner[prop.owner_peer_id].erase(prop)

	prop_destroyed.emit(prop)

func _cleanup_destroyed_props():
	"""Remove references to destroyed props"""
	var to_remove = []
	for network_id in active_props:
		var prop = active_props[network_id]
		if not is_instance_valid(prop) or prop.state == Barricade.BarricadeState.DESTROYED:
			to_remove.append(network_id)

	for network_id in to_remove:
		active_props.erase(network_id)

func _on_player_disconnected(peer_id: int):
	"""Handle player disconnect - props remain but become unowned"""
	if prop_by_owner.has(peer_id):
		for prop in prop_by_owner[peer_id]:
			if is_instance_valid(prop):
				prop.owner_peer_id = 0
		prop_by_owner.erase(peer_id)

# ============================================
# ZOMBIE TARGETING
# ============================================

func get_nearest_target_for_zombie(zombie_position: Vector3, max_distance: float = 50.0) -> Node:
	"""Get the nearest valid target for a zombie (prioritizes props over players)"""
	var best_target: Node = null
	var best_score: float = -1.0

	# Check props first (higher priority)
	for network_id in active_props:
		var prop = active_props[network_id] as Barricade
		if not is_instance_valid(prop) or prop.state == Barricade.BarricadeState.DESTROYED:
			continue

		var distance = zombie_position.distance_to(prop.global_position)
		if distance > max_distance:
			continue

		# Score based on distance and priority weight
		var score = (1.0 / max(distance, 1.0)) * prop.priority_weight * 100.0

		if score > best_score:
			best_score = score
			best_target = prop

	# If no props found or player is much closer, consider players
	if best_target == null or best_score < 10.0:
		var players = get_tree().get_nodes_in_group("players")
		for player in players:
			if not is_instance_valid(player):
				continue

			# Check if player is alive
			if player.has_method("is_dead") and player.is_dead():
				continue

			var distance = zombie_position.distance_to(player.global_position)
			if distance > max_distance:
				continue

			# Players have lower base priority than props
			var score = (1.0 / max(distance, 1.0)) * 50.0

			if score > best_score:
				best_score = score
				best_target = player

	return best_target

func get_props_blocking_path(from: Vector3, to: Vector3) -> Array[Barricade]:
	"""Get all props between two points"""
	var blocking: Array[Barricade] = []

	var space_state = get_tree().current_scene.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 8  # Props layer

	var result = space_state.intersect_ray(query)
	while result:
		var collider = result.collider
		if collider is Barricade:
			blocking.append(collider)

		# Continue ray from hit point
		from = result.position + (to - from).normalized() * 0.1
		if from.distance_to(to) < 0.1:
			break
		query = PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 8
		query.exclude = [collider]
		result = space_state.intersect_ray(query)

	return blocking

func has_props_remaining() -> bool:
	"""Check if there are any intact props left"""
	for network_id in active_props:
		var prop = active_props[network_id] as Barricade
		if is_instance_valid(prop) and prop.state != Barricade.BarricadeState.DESTROYED:
			return true
	return false

func get_prop_count() -> int:
	"""Get count of active props"""
	return active_props.size()

func get_props_by_owner(owner_id: int) -> Array:
	"""Get all props owned by a player"""
	if prop_by_owner.has(owner_id):
		return prop_by_owner[owner_id]
	return []

# ============================================
# NETWORK SYNC
# ============================================

@rpc("authority", "call_remote", "reliable")
func _sync_prop_placed(data: Dictionary):
	"""Sync prop placement to clients"""
	var prop_type = data.get("type", Barricade.BarricadeType.WOODEN_PLANK)
	var position = data.get("position", Vector3.ZERO)
	var rotation = data.get("rotation", Vector3.ZERO)
	var owner_id = data.get("owner_peer_id", 0)

	# Create prop locally
	var prop = _create_basic_barricade(prop_type, position, rotation, owner_id)
	if prop:
		prop.network_id = data.get("network_id", prop.network_id)
		prop.current_health = data.get("health", prop.max_health)
		prop.is_nailed = data.get("is_nailed", false)

@rpc("authority", "call_remote", "reliable")
func _sync_prop_removed(network_id: int):
	"""Sync prop removal to clients"""
	if active_props.has(network_id):
		var prop = active_props[network_id]
		active_props.erase(network_id)
		if is_instance_valid(prop):
			prop.queue_free()

@rpc("authority", "call_remote", "reliable")
func _sync_prop_picked_up(_network_id: int, _picker_id: int):
	"""Sync prop pickup to clients"""
	# Handled by _sync_prop_removed
	pass

func sync_all_props_to_peer(peer_id: int):
	"""Send all prop data to a newly connected peer"""
	for network_id in active_props:
		var prop = active_props[network_id] as Barricade
		if is_instance_valid(prop):
			_sync_prop_placed.rpc_id(peer_id, prop.to_network_data())

# ============================================
# BUILD MENU DATA
# ============================================

func get_available_props() -> Array[Dictionary]:
	"""Get list of available props for the build menu"""
	var props: Array[Dictionary] = []

	for prop_type in PROP_COSTS.keys():
		props.append({
			"type": prop_type,
			"name": _get_prop_name(prop_type),
			"cost": PROP_COSTS[prop_type],
			"hp": PROP_HP[prop_type],
			"size": _get_prop_size(prop_type),
			"icon": _get_prop_icon(prop_type)
		})

	return props

func _get_prop_name(prop_type: int) -> String:
	match prop_type:
		Barricade.BarricadeType.DOORWAY: return "Doorway Barricade"
		Barricade.BarricadeType.WALL: return "Wall Section"
		Barricade.BarricadeType.WINDOW_BOARD: return "Window Board"
		Barricade.BarricadeType.WIRE_FENCE: return "Wire Fence"
		Barricade.BarricadeType.SANDBAG: return "Sandbag"
		Barricade.BarricadeType.METAL_SHEET: return "Metal Sheet"
		Barricade.BarricadeType.WOODEN_PLANK: return "Wooden Plank"
		Barricade.BarricadeType.HALLWAY_BLOCK: return "Hallway Block"
		Barricade.BarricadeType.FLOOR_TRAP: return "Floor Trap"
		Barricade.BarricadeType.SIGIL: return "Protective Sigil"
	return "Unknown"

func _get_prop_icon(prop_type: int) -> String:
	# Return icon path - would be actual icon paths
	return "res://assets/ui/icons/prop_%d.png" % prop_type
