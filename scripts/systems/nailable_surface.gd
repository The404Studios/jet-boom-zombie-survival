extends StaticBody3D
class_name NailableSurface

# Surface that props can be nailed to
# Used for walls, floors, and other static objects that accept barricades

signal prop_nailed(prop: Node, position: Vector3)
signal prop_removed(prop: Node)

@export var surface_name: String = "Surface"
@export var surface_type: SurfaceType = SurfaceType.WOOD
@export var max_attached_props: int = 10
@export var nail_resistance: float = 1.0  # Multiplier for nail health

enum SurfaceType {
	WOOD,
	CONCRETE,
	METAL,
	DIRT
}

# Attached props tracking
var attached_props: Array[Node] = []
var attachment_points: Array[Dictionary] = []  # {prop, position, rotation, nails}

func _ready():
	add_to_group("nailable_surfaces")
	add_to_group("surfaces")

	# Add to appropriate material group for effects
	match surface_type:
		SurfaceType.WOOD:
			add_to_group("wood")
		SurfaceType.CONCRETE:
			add_to_group("concrete")
		SurfaceType.METAL:
			add_to_group("metal")
		SurfaceType.DIRT:
			add_to_group("dirt")

func can_attach_prop() -> bool:
	"""Check if surface can accept more props"""
	return attached_props.size() < max_attached_props

func attach_prop(prop: Node, attach_position: Vector3, attach_rotation: Vector3 = Vector3.ZERO) -> bool:
	"""Attach a prop to this surface"""
	if not can_attach_prop():
		return false

	if prop in attached_props:
		return false  # Already attached

	attached_props.append(prop)
	attachment_points.append({
		"prop": prop,
		"position": attach_position,
		"rotation": attach_rotation,
		"nails": 0,
		"attached_time": Time.get_unix_time_from_system()
	})

	# Connect to prop destruction
	if prop.has_signal("destroyed"):
		prop.destroyed.connect(_on_prop_destroyed.bind(prop))

	prop_nailed.emit(prop, attach_position)
	return true

func detach_prop(prop: Node) -> bool:
	"""Remove a prop from this surface"""
	var index = attached_props.find(prop)
	if index == -1:
		return false

	attached_props.remove_at(index)

	# Remove attachment point
	for i in range(attachment_points.size()):
		if attachment_points[i].prop == prop:
			attachment_points.remove_at(i)
			break

	# Disconnect signal
	if prop.has_signal("destroyed") and prop.destroyed.is_connected(_on_prop_destroyed):
		prop.destroyed.disconnect(_on_prop_destroyed)

	prop_removed.emit(prop)
	return true

func _on_prop_destroyed(prop: Node):
	"""Handle attached prop being destroyed"""
	detach_prop(prop)

func get_attached_props() -> Array[Node]:
	"""Get all attached props"""
	return attached_props.duplicate()

func get_attachment_data(prop: Node) -> Dictionary:
	"""Get attachment info for a prop"""
	for data in attachment_points:
		if data.prop == prop:
			return data
	return {}

func get_surface_hardness() -> float:
	"""Get surface hardness for nail damage calculations"""
	match surface_type:
		SurfaceType.WOOD:
			return 1.0
		SurfaceType.CONCRETE:
			return 1.5  # Harder to nail into
		SurfaceType.METAL:
			return 2.0  # Much harder
		SurfaceType.DIRT:
			return 0.5  # Easier
	return 1.0

func get_nail_sound() -> String:
	"""Get appropriate nailing sound for this surface"""
	match surface_type:
		SurfaceType.WOOD:
			return "hammer"
		SurfaceType.CONCRETE:
			return "hammer_concrete"
		SurfaceType.METAL:
			return "hammer_metal"
		SurfaceType.DIRT:
			return "hammer_dirt"
	return "hammer"

# Utility function to check if a point is on this surface
func is_point_on_surface(point: Vector3, threshold: float = 0.5) -> bool:
	"""Check if a world position is near this surface"""
	var closest = _get_closest_point(point)
	return point.distance_to(closest) <= threshold

func _get_closest_point(point: Vector3) -> Vector3:
	"""Get closest point on surface to given point (simplified)"""
	# For simple box collision, project to AABB
	if has_node("CollisionShape3D"):
		var shape = get_node("CollisionShape3D")
		if shape.shape is BoxShape3D:
			var box = shape.shape as BoxShape3D
			var local = to_local(point)
			local.x = clamp(local.x, -box.size.x/2, box.size.x/2)
			local.y = clamp(local.y, -box.size.y/2, box.size.y/2)
			local.z = clamp(local.z, -box.size.z/2, box.size.z/2)
			return to_global(local)

	return global_position
