extends Node3D
class_name PropSpawner

# Spawns pickupable props in levels for barricade building
# Configure spawn points and prop types per level

signal props_spawned(count: int)
signal prop_picked_up(prop: Node)

@export var spawn_on_ready: bool = true
@export var initial_prop_count: int = 20
@export var max_props_in_level: int = 50
@export var respawn_interval: float = 60.0  # Respawn props every 60 seconds
@export var respawn_batch_size: int = 5

# Prop scenes to spawn
@export var prop_scenes: Array[PackedScene] = []

# Spawn area bounds
@export var spawn_area_size: Vector3 = Vector3(20, 0, 20)
@export var spawn_height: float = 1.0
@export var use_spawn_points: bool = false  # Use child Node3D as spawn points

# Runtime tracking
var spawned_props: Array[Node] = []
var spawn_points: Array[Node3D] = []
var respawn_timer: float = 0.0

# Default prop scene paths
var default_prop_paths: Array[String] = [
	"res://scenes/props/pickupable_crate.tscn",
	"res://scenes/props/pickupable_barrel.tscn",
	"res://scenes/props/pickupable_plank.tscn",
	"res://scenes/props/pickupable_table.tscn",
	"res://scenes/props/pickupable_metal_sheet.tscn"
]

func _ready():
	add_to_group("prop_spawners")

	# Load default prop scenes if none specified
	if prop_scenes.is_empty():
		_load_default_props()

	# Find spawn points if using them
	if use_spawn_points:
		_find_spawn_points()

	# Spawn initial props
	if spawn_on_ready:
		spawn_initial_props()

func _process(delta):
	# Handle respawning
	if respawn_interval > 0 and spawned_props.size() < max_props_in_level:
		respawn_timer += delta
		if respawn_timer >= respawn_interval:
			respawn_timer = 0.0
			spawn_props(respawn_batch_size)

func _load_default_props():
	"""Load default prop scenes"""
	for path in default_prop_paths:
		if ResourceLoader.exists(path):
			var scene = load(path)
			if scene:
				prop_scenes.append(scene)

	if prop_scenes.is_empty():
		push_warning("PropSpawner: No prop scenes found!")

func _find_spawn_points():
	"""Find child nodes to use as spawn points"""
	for child in get_children():
		if child is Node3D and child.name.begins_with("SpawnPoint"):
			spawn_points.append(child)

	if spawn_points.is_empty():
		push_warning("PropSpawner: use_spawn_points enabled but no spawn points found!")
		use_spawn_points = false

func spawn_initial_props():
	"""Spawn the initial batch of props"""
	spawn_props(initial_prop_count)

func spawn_props(count: int):
	"""Spawn a batch of props"""
	if prop_scenes.is_empty():
		return

	var spawned = 0
	for i in range(count):
		if spawned_props.size() >= max_props_in_level:
			break

		var prop = _spawn_single_prop()
		if prop:
			spawned += 1

	if spawned > 0:
		props_spawned.emit(spawned)

func _spawn_single_prop() -> Node:
	"""Spawn a single random prop"""
	if prop_scenes.is_empty():
		return null

	# Pick random prop scene
	var scene = prop_scenes[randi() % prop_scenes.size()]
	if not scene:
		return null

	# Instance prop
	var prop = scene.instantiate()
	if not prop:
		return null

	# Get spawn position
	var spawn_pos = _get_spawn_position()
	prop.global_position = spawn_pos

	# Random rotation
	prop.rotation.y = randf() * TAU

	# Add to level
	get_parent().add_child(prop)
	spawned_props.append(prop)

	# Connect to prop destruction
	if prop.has_signal("destroyed"):
		prop.destroyed.connect(_on_prop_destroyed.bind(prop))
	if prop.has_signal("picked_up"):
		prop.picked_up.connect(_on_prop_picked_up.bind(prop))

	return prop

func _get_spawn_position() -> Vector3:
	"""Get a position to spawn a prop"""
	if use_spawn_points and not spawn_points.is_empty():
		# Use random spawn point
		var point = spawn_points[randi() % spawn_points.size()]
		return point.global_position
	else:
		# Random position in spawn area
		var pos = global_position + Vector3(
			randf_range(-spawn_area_size.x / 2, spawn_area_size.x / 2),
			spawn_height,
			randf_range(-spawn_area_size.z / 2, spawn_area_size.z / 2)
		)

		# Raycast to find ground
		pos = _find_ground(pos)
		return pos

func _find_ground(pos: Vector3) -> Vector3:
	"""Raycast down to find ground level"""
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 5, 0),
		pos - Vector3(0, 20, 0)
	)
	query.collision_mask = 1  # World layer

	var result = space_state.intersect_ray(query)
	if result:
		return result.position + Vector3(0, 0.5, 0)  # Slightly above ground

	return pos

func _on_prop_destroyed(prop: Node):
	"""Handle prop being destroyed"""
	spawned_props.erase(prop)

func _on_prop_picked_up(_player: Node, prop: Node):
	"""Handle prop being picked up"""
	prop_picked_up.emit(prop)
	# Don't remove from tracking - prop still exists

# ============================================
# UTILITY
# ============================================

func get_nearby_props(position: Vector3, radius: float) -> Array[Node]:
	"""Get all props within radius of position"""
	var result: Array[Node] = []
	for prop in spawned_props:
		if is_instance_valid(prop):
			if prop.global_position.distance_to(position) <= radius:
				result.append(prop)
	return result

func get_spawned_prop_count() -> int:
	"""Get current number of spawned props"""
	# Clean up invalid references
	spawned_props = spawned_props.filter(func(p): return is_instance_valid(p))
	return spawned_props.size()

func despawn_all_props():
	"""Remove all spawned props"""
	for prop in spawned_props:
		if is_instance_valid(prop):
			prop.queue_free()
	spawned_props.clear()

func spawn_prop_at(scene: PackedScene, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> Node:
	"""Spawn a specific prop at a specific location"""
	if not scene:
		return null

	var prop = scene.instantiate()
	if not prop:
		return null

	prop.global_position = position
	prop.rotation = rotation

	get_parent().add_child(prop)
	spawned_props.append(prop)

	if prop.has_signal("destroyed"):
		prop.destroyed.connect(_on_prop_destroyed.bind(prop))
	if prop.has_signal("picked_up"):
		prop.picked_up.connect(_on_prop_picked_up.bind(prop))

	return prop
