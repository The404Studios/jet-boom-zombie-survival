## TransformComponent - Stores position, rotation, and scale data
## The fundamental spatial component for any entity in 3D space
class_name TransformComponent
extends Component

## World position
var position: Vector3 = Vector3.ZERO

## Rotation in radians (Euler angles)
var rotation: Vector3 = Vector3.ZERO

## Scale factor
var scale: Vector3 = Vector3.ONE

## Previous position (for interpolation)
var previous_position: Vector3 = Vector3.ZERO

## Previous rotation (for interpolation)
var previous_rotation: Vector3 = Vector3.ZERO

## Linked Node3D (for syncing with Godot scene)
var node_3d: Node3D = null


func get_component_name() -> String:
	return "Transform"


func _on_added() -> void:
	previous_position = position
	previous_rotation = rotation


## Get the forward direction vector
func get_forward() -> Vector3:
	var basis := Basis.from_euler(rotation)
	return -basis.z


## Get the right direction vector
func get_right() -> Vector3:
	var basis := Basis.from_euler(rotation)
	return basis.x


## Get the up direction vector
func get_up() -> Vector3:
	var basis := Basis.from_euler(rotation)
	return basis.y


## Get position as Transform3D
func get_transform() -> Transform3D:
	var basis := Basis.from_euler(rotation)
	basis = basis.scaled(scale)
	return Transform3D(basis, position)


## Set transform from Transform3D
func set_from_transform(t: Transform3D) -> void:
	position = t.origin
	rotation = t.basis.get_euler()
	scale = t.basis.get_scale()


## Look at a target position
func look_at_position(target: Vector3, up: Vector3 = Vector3.UP) -> void:
	if position.distance_to(target) < 0.001:
		return
	var t := Transform3D.IDENTITY
	t.origin = position
	t = t.looking_at(target, up)
	rotation = t.basis.get_euler()


## Get distance to another transform component
func distance_to(other: TransformComponent) -> float:
	return position.distance_to(other.position)


## Get direction to another transform component
func direction_to(other: TransformComponent) -> Vector3:
	return position.direction_to(other.position)


## Translate by a vector
func translate(offset: Vector3) -> void:
	previous_position = position
	position += offset


## Rotate by euler angles
func rotate_by(euler: Vector3) -> void:
	previous_rotation = rotation
	rotation += euler


## Sync to linked Node3D
func sync_to_node() -> void:
	if node_3d and is_instance_valid(node_3d):
		node_3d.global_position = position
		node_3d.rotation = rotation
		node_3d.scale = scale


## Sync from linked Node3D
func sync_from_node() -> void:
	if node_3d and is_instance_valid(node_3d):
		previous_position = position
		previous_rotation = rotation
		position = node_3d.global_position
		rotation = node_3d.rotation
		scale = node_3d.scale


## Interpolate position between previous and current (for smooth rendering)
func interpolate_position(factor: float) -> Vector3:
	return previous_position.lerp(position, factor)


## Interpolate rotation between previous and current
func interpolate_rotation(factor: float) -> Vector3:
	return previous_rotation.lerp(rotation, factor)


func serialize() -> Dictionary:
	var data := super.serialize()
	data["position"] = {"x": position.x, "y": position.y, "z": position.z}
	data["rotation"] = {"x": rotation.x, "y": rotation.y, "z": rotation.z}
	data["scale"] = {"x": scale.x, "y": scale.y, "z": scale.z}
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if data.has("position"):
		var p: Dictionary = data["position"]
		position = Vector3(p.get("x", 0), p.get("y", 0), p.get("z", 0))
	if data.has("rotation"):
		var r: Dictionary = data["rotation"]
		rotation = Vector3(r.get("x", 0), r.get("y", 0), r.get("z", 0))
	if data.has("scale"):
		var s: Dictionary = data["scale"]
		scale = Vector3(s.get("x", 1), s.get("y", 1), s.get("z", 1))
	previous_position = position
	previous_rotation = rotation
